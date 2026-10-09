"""Build the offline three-armor review from real, hash-bound runtime evidence.

This script only reads engine outputs. It does not render, edit images, certify
art quality, or run an engine. Missing delivery evidence remains NOT RUN.
"""
from __future__ import annotations

import argparse
from datetime import date
import hashlib
import json
import os
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
ART = ROOT / 'docs/art/original_armors_v1'
REFINED_ARMORS = {'atom', 'pegasus'}
PUBLISHED_ARMORS = {'thunder', 'atom', 'pegasus'}
BASELINE_COMMIT = '3ed1c2911e1eea5162e30d0bab331fd41a1d29f9'
DELIVERY_REVISION = 'draft_refinement_v3'
THUNDER_HISTORY_SHA256 = '8ef68f9c7d9e67b32d01c1632bdf765debc527117f872e1a56c8ab00c02c09fb'
BROWSER_LIMITATION = ('NOT RUN：本輪 CUA 預覽被安全政策拒絕，file:// 協定不受支援；'
                      '未以 HTTP 或其他介面繞過。已檢查 JavaScript 語法與本機資源 SHA。')
ARMORS = (
    ('thunder', 'Thunder', 'C-07', 6, 'thunder_draft_v3',
     'assets/armors/thunder/thunder.scn', 'c07_redline.json'),
    ('atom', 'Atom', 'C-08', 7, 'atom_runtime_v1',
     'assets/armors/atom_v1/atom.scn', 'c08_prism.json'),
    ('pegasus', 'Pegasus', 'C-09', 8, 'pegasus_runtime_v1',
     'assets/armors/pegasus_v1/pegasus.scn', 'c09_bulwark.json'),
)
VIEWS = (
    ('head_front', '頭盔・正面', 'head'),
    ('head_quarter', '頭盔・斜前', 'head'),
    ('head_side', '頭盔・側面', 'head'),
    ('head_rear', '頭盔・背面', 'head'),
    ('diffuse_front', '全身・正面', 'body'),
    ('diffuse_quarter', '全身・斜前', 'body'),
    ('diffuse_side', '全身・側面', 'body'),
    ('diffuse_rear', '全身・背面', 'body'),
    ('clay_front', '灰模・正面', 'clay'),
    ('clay_side', '灰模・側面', 'clay'),
    ('idle_rifle', '持槍待機', 'animation'),
    ('run_rifle', '持槍跑動', 'animation'),
    ('reload_04', '換彈中段', 'animation'),
    ('level_01_gameplay', '區域 01・遊戲', 'gameplay'),
    ('level_08_gameplay', '區域 08・遊戲', 'gameplay'),
)


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path: Path) -> str:
    return os.path.relpath(path, WORK).replace('\\', '/')


def resource(path: Path, expected_sha: str | None = None) -> dict:
    """Expose an existing local file only after its bound bytes match."""
    if not path.is_file():
        raise ValueError(f'Missing review resource: {path}')
    actual = sha(path)
    if expected_sha and actual != expected_sha:
        raise ValueError(f'Stale review resource SHA: {path}')
    return {'path': relative(path), 'sha256': actual, 'bytes': path.stat().st_size}


def lookup_record(records: list[dict], path: Path) -> dict | None:
    for record in records:
        raw = record.get('path', '').removeprefix('res://')
        if raw and (ROOT / raw).resolve() == path.resolve():
            return record
    return None


def collect_previous_refinement(work: Path, scene: Path) -> dict:
    """Bind the previous model-refinement stage to its immutable snapshot."""
    thunder = work.name == 'thunder_draft_v3'
    source_work = ROOT / 'docs/art/thunder_original_v2' if thunder else work
    frozen = work / ('revisions/before_draft_v3' if thunder else
                     'revisions/before_draft_refinement_v3')
    snapshot_path = frozen / 'snapshot.json'
    snapshot = load(snapshot_path)
    expected_status = ('FROZEN_ORIGINAL_BASED_THUNDER_V2_BASELINE' if thunder else
                       'FROZEN_DRAFT_REFINEMENT_V2_BASELINE')
    if (snapshot.get('source_commit') != BASELINE_COMMIT or
            snapshot.get('status') != expected_status):
        raise ValueError(f'Unexpected previous model refinement: {snapshot_path}')
    if thunder and sha(snapshot_path) != THUNDER_HISTORY_SHA256:
        raise ValueError('Thunder previous-delivery snapshot index changed')

    def frozen_resource(original: Path, expected_sha: str | None = None) -> dict:
        record = lookup_record(
            [{'path': row['original_path'], **row} for row in snapshot['files']], original)
        if not record or (expected_sha and record['sha256'] != expected_sha):
            raise ValueError(f'Baseline snapshot does not bind: {original}')
        path = ROOT / record['snapshot_path']
        if not path.resolve().is_relative_to(frozen.resolve()):
            raise ValueError(f'Baseline resource is outside its snapshot: {path}')
        return resource(path, record['sha256'])

    manifest_record = frozen_resource(source_work / 'manifest.json')
    manifest = load(WORK / manifest_record['path'])
    capture_record = frozen_resource(source_work / 'review/engine/capture.json')
    capture = load(WORK / capture_record['path'])
    scene_record = frozen_resource(scene)
    bound_capture = manifest.get('capture_summary', {})
    bound_scene = lookup_record(manifest.get('files', []), scene)
    if (bound_capture.get('sha256') != capture_record['sha256'] or not bound_scene or
            bound_scene['sha256'] != scene_record['sha256']):
        raise ValueError(f'Baseline manifest does not bind its frozen evidence: {work}')
    if (capture.get('runtime_scene_sha256') != scene_record['sha256'] or
            capture.get('resource_mode') != 'normal_imported_resources' or
            not capture.get('save_unchanged')):
        raise ValueError(f'Baseline capture does not bind its frozen scene: {work}')
    captures = {}
    for record in manifest.get('captures', []):
        original_path = ROOT / record['path']
        if original_path.stem.startswith('new_'):
            captures[original_path.stem] = {
                **frozen_resource(original_path, record['sha256']),
                'dimensions': record.get('dimensions'),
            }
    return {'source_commit': BASELINE_COMMIT, 'scene': scene_record,
            'snapshot': resource(snapshot_path), 'manifest': manifest_record,
            'capture_summary': capture_record, 'captures': captures}


def format_metrics(manifest: dict, runtime_id: int) -> list[dict]:
    geometry = manifest.get('geometry', {})
    topology = manifest.get('topology', {})
    uv = manifest.get('uv_summary', {})
    rows = []
    for part_name, label in [('ArmorHead', '頭部'), ('ArmorBody', '胸肩部')]:
        part = geometry.get('parts', {}).get(f'{part_name}_{runtime_id:02}', {})
        if 'max_displacement_fraction_of_smallest_dimension' in part:
            value = part['max_displacement_fraction_of_smallest_dimension']
            rows.append({'label': f'{label}相對原版最大位移', 'value': f'{value * 100:.3f}%',
                         'note': '按該原部件最小軸尺寸正規化；不是概念圖相似率。'})
    if uv:
        count = uv.get('original_coordinate_count')
        changed = uv.get('changed_coordinate_count', uv.get('changed_coordinates'))
        if isinstance(changed, (int, float)):
            rows.append({'label': 'UV 座標變更', 'value': str(changed),
                         'note': f"原版{'頭部' if uv.get('scope') == 'head_only' else ''}座標數 {count}；以工程報告為準。"})
        elif 'original_coordinate_count' in uv:
            rows.append({'label': '原版 UV 座標數', 'value': str(count),
                         'note': 'UV 改動結果另見完整 manifest。'})
    if topology:
        triangles = topology.get('triangles')
        bones = topology.get('bones', topology.get('original_bones'))
        if triangles is not None:
            rows.append({'label': '模型三角形', 'value': str(triangles),
                         'note': topology.get('note', '四部件合計；幾何數量不代表美術精細度。')})
        if bones is not None:
            rows.append({'label': '原骨架', 'value': str(bones),
                         'note': '部件裝配與動作驗證另列。'})
    return rows


def collect_armor(spec: tuple) -> dict:
    slug, name, design_id, runtime_id, directory, scene_path, metadata_name = spec
    work = ROOT / 'docs/art' / directory
    metadata = load(ART / metadata_name)
    manifest_path = work / 'manifest.json'
    result = {
        'key': slug, 'name': name, 'design_id': design_id, 'runtime_id': runtime_id,
        'status': '尚未取得完整正式擷取與驗收', 'ready': False,
        'scope': ('依目前圖集選定的 B 稿調整 Thunder 頭盔形狀與貼圖；'
                  '保留真正原版頭部 UV、拓撲與骨架，身甲維持 3ed 版本。'
                  if slug == 'thunder' else
                  '依核准概念實際調整頭盔、胸肩輪廓與貼圖，保留遊戲比例、原骨架與裝配。'),
        'captures': {}, 'metrics': [], 'tests': [], 'residuals': [], 'sources': [],
        'comparison_order': ['original', 'before', 'after'],
        'stage_labels': {
            'original': {'title': '真正原版 ' + name,
                         'caption': '同一擷取管線的原始模型與貼圖。'},
            'before': {'title': '3ed1c291 · 上一版遊戲素材' if slug == 'thunder' else
                               '3ed1c291 · 上一版改模',
                       'caption': '上一輪原版頭部基底的貼圖版；從凍結場景重新擷取。' if slug == 'thunder' else
                                  '上一輪已修改頭部與胸肩模型的素材，從凍結快照讀取。'},
            'after': {'title': '本輪 · 草稿再修版 v3',
                      'caption': '實際正式模型與貼圖；外觀待使用者評價。'},
        },
        'before_note': ('Thunder 的上一版為 3ed1c291 原版頭部基底交付；'
                        '本輪按目前圖集選定的 B 稿實際改形。三組畫面由同一次擷取產生，'
                        '身甲保持 3ed，不宣稱整套相對真正原版符合頭部的 20% 限制。'
                        if slug == 'thunder' else
                        '依序比較真正原版、3ed1c291 上一版改模、本輪草稿再修版。灰模可直接檢查形狀變化；f94323e4 僅貼圖版保留於歷史快照，不宣稱本輪與草稿完全一致。'),
        'art_acceptance': 'NOT RUN・等待使用者美術評價',
        'browser_interaction': 'NOT RUN',
        'visual_inspection': 'NOT RUN',
    }
    # The current gallery selection is Thunder's design authority; keep all
    # earlier image/history fields intact rather than changing that selection.
    legacy = ART / f'references/legacy/c{int(design_id[2:]):02}_front.png'
    art_path = (ART / metadata['user_review']['preferred_art']['path'] if slug == 'thunder'
                else ART / metadata['images']['concept'])
    result['reference'] = {**resource(art_path),
        'label': '本輪 Thunder 設計參考：目前圖集 B 稿' if slug == 'thunder' else '目前裝甲設計參考',
        'note': ('使用目前圖集保留的 B 新頭盔舊稿作形狀與配色目標；'
                 '真正原版模型與 atlas 提供 UV、拓撲及動作基底。身甲維持 3ed。'
                 if slug == 'thunder' else '概念圖只用來看設計，不是同相機遊戲擷取，也不是本輪生成的貼圖。')}
    result['legacy_reference'] = {**resource(legacy), 'label': '真正原遊戲造型參考'}
    if not manifest_path.is_file():
        return result
    manifest = load(manifest_path)
    result['sources'].append({**resource(manifest_path), 'label': '完整素材與工程 manifest'})
    scene = ROOT / scene_path
    scene_record = lookup_record(manifest.get('files', []), scene)
    if not scene_record:
        raise ValueError(f'{name}: manifest does not bind actual runtime scene')
    result['scene'] = resource(scene, scene_record['sha256'])
    capture_summary = manifest.get('capture_summary')
    if capture_summary:
        summary_path = ROOT / capture_summary['path']
        result['sources'].append({**resource(summary_path, capture_summary['sha256']),
                                  'label': '正常引擎擷取紀錄'})
        capture = load(summary_path)
        captured_scene = capture.get('runtime_scene_sha256', capture.get('current_scene_sha256'))
        if captured_scene != result['scene']['sha256']:
            raise ValueError(f'{name}: captures do not bind the current runtime scene')
        if capture.get('resource_mode') != 'normal_imported_resources' or not capture.get('save_unchanged'):
            raise ValueError(f'{name}: normal resources / unchanged-save capture evidence missing')
    available = {}
    for record in manifest.get('captures', []):
        path = ROOT / record['path']
        available[path.stem] = {**resource(path, record['sha256']),
                                'dimensions': record.get('dimensions')}
    baseline = collect_previous_refinement(work, scene)
    if baseline:
        result['baseline'] = {key: value for key, value in baseline.items() if key != 'captures'}
        for label, key in [('3ed1c291 上一版交付凍結清單', 'snapshot'),
                           ('3ed1c291 素材與工程 manifest', 'manifest'),
                           ('3ed1c291 引擎擷取紀錄', 'capture_summary')]:
            result['sources'].append({**baseline[key], 'label': label})
        if slug in REFINED_ARMORS:
            result['sources'].append({**resource(work / 'revisions/before_draft_refinement_v2/snapshot.json'),
                                      'label': 'f94323e4 僅貼圖版歷史快照（保留）'})
        else:
            result['sources'].append({**resource(ROOT / 'docs/art/thunder_original_v2/manifest.json'),
                                      'label': 'Thunder original_v2 歷史交付（保留）'})
            if capture.get('before_scene_sha256') != baseline['scene']['sha256']:
                raise ValueError('Thunder capture does not bind the frozen 3ed before scene')
    aliases = ({'diffuse_front': 'full_front', 'diffuse_quarter': 'full_quarter',
        'diffuse_side': 'full_side', 'diffuse_rear': 'full_rear', 'idle_rifle': 'idle',
        'run_rifle': 'run', 'reload_04': 'reload', 'level_01_gameplay': 'game_level_1',
        'level_08_gameplay': 'game_level_3'} if slug == 'thunder' else {})
    for suffix, label, scope in VIEWS:
        native_suffix = aliases.get(suffix, suffix)
        original = available.get('original_' + native_suffix)
        after = available.get('new_' + native_suffix)
        before = (available.get('before_' + native_suffix) if slug == 'thunder' else
                  baseline['captures'].get('new_' + native_suffix))
        if original or after:
            if slug == 'thunder' and suffix == 'level_08_gameplay':
                label = '區域 03・遊戲'
            result['captures'][suffix] = {'label': label, 'scope': scope,
                                          'original': original, 'after': after, 'before': before}
    result['metrics'] = format_metrics(manifest, runtime_id)
    if slug in PUBLISHED_ARMORS:
        parts = manifest.get('geometry', {}).get('parts', {})
        required_parts = ['ArmorHead'] if slug == 'thunder' else ['ArmorHead', 'ArmorBody']
        result['model_refinement_observed'] = all(
            parts.get(f'{part}_{runtime_id:02}', {}).get('max_rest_displacement', 0) > 0
            for part in required_parts)
        result['changed_since_previous_delivery'] = result['scene']['sha256'] != baseline['scene']['sha256']
    for label, record in manifest.get('tests', {}).items():
        entry = {'label': label, 'status': record.get('status', 'NOT RUN')}
        report = record.get('file')
        if isinstance(report, dict) and report.get('path'):
            report_path = ROOT / report['path']
            entry['evidence'] = resource(report_path, report.get('sha256'))
            if load(report_path).get('status') != entry['status']:
                raise ValueError(f'{name}: test status differs from actual report: {label}')
        result['tests'].append(entry)
    result['residuals'] = manifest.get('residuals', [])
    visual_path = next((path for path in (work / 'review/visual_review.json', work / 'visual_review.json')
                        if path.is_file()), None)
    if visual_path:
        visual = load(visual_path)
        visual_capture = visual.get('capture_summary', {})
        if not capture_summary or visual_capture.get('sha256') != capture_summary['sha256']:
            raise ValueError(f'{name}: visual review does not bind the current capture summary')
        result['visual_inspection'] = visual.get('status', 'NOT RUN')
        result['sources'].append({**resource(visual_path), 'label': '逐張實際目視紀錄'})
    visual_ready = result['visual_inspection'] in {
        'VISUALLY_REVIEWED_PENDING_USER_REVIEW', 'ENGINEERING_CANDIDATE_PENDING_USER_ART_REVIEW'}
    result['ready'] = bool(visual_ready and capture_summary and len(result['captures']) == len(VIEWS) and
        all(row['original'] and row['after'] for row in result['captures'].values()) and
        (not baseline or all(row['before'] for row in result['captures'].values())) and
        result['model_refinement_observed'] and result['changed_since_previous_delivery'] and
        all(row['status'] == 'PASS' and row.get('evidence') for row in result['tests']) and result['tests'])
    result['status'] = ('已套用正式素材・工程紀錄通過・待美術評價' if result['ready'] else
                       '已發現需修正的美術問題' if result['visual_inspection'] == 'NEEDS_ART_REVISION' else
                       '正式素材與部分證據已存在・其餘待完成')
    for label, filename in [('各套獨立比對頁', 'index.html'),
                            ('生成圖、實送 Prompt 與來源', 'generation_inputs.json'),
                            ('原版頭盔實送 Prompt', 'prompts/head_attempt_01.txt'),
                            ('原版來源凍結紀錄', 'revisions/original_source_v1/snapshot.json')]:
        path = work / filename
        if path.is_file():
            result['sources'].append({**resource(path), 'label': label})
    return result


def update_gallery(data: dict) -> dict:
    """Publish C07/C08/C09; preserve their selected art and all other rows."""
    publish = [armor for armor in data['armors'] if armor['key'] in PUBLISHED_ARMORS]
    pending = [armor['name'] for armor in publish if not armor['ready']]
    if pending:
        raise ValueError('Do not publish incomplete runtime gallery metadata: ' + ', '.join(pending))
    path = ART / 'index.html'
    text = path.read_text(encoding='utf-8')
    pattern = r'(<script id="catalog" type="application/json">)(.*?)(</script>)'
    match = re.search(pattern, text, re.DOTALL)
    if not match:
        raise ValueError('Gallery catalog not found')
    catalog = json.loads(match.group(2))
    untouched_before = [row for row in catalog if row['design_id'] not in {'C-07', 'C-08', 'C-09'}]
    updated = []
    for armor, spec in zip(data['armors'], ARMORS):
        if armor['key'] not in PUBLISHED_ARMORS:
            continue
        metadata_path = ART / spec[6]
        metadata = load(metadata_path)
        manifest = armor['sources'][0]
        delivery = {
            'status': 'runtime_integrated_pending_user_art_review',
            'scope': 'visual_assets_only_stats_and_abilities_remain_proposals',
            'runtime_id': armor['runtime_id'], 'date': data['date'],
            'scene': spec[5], 'scene_sha256': armor['scene']['sha256'],
            'comparison_page': '../armor_original_based_v2/index.html#' + armor['key'],
            'manifest': '../' + spec[4] + '/manifest.json',
            'manifest_sha256': manifest['sha256'],
            'original_based': True, 'art_acceptance': 'pending_user_review',
            'revision': DELIVERY_REVISION, 'note': armor['scope'],
        }
        history_key = ('previous_original_based_runtime' if armor['key'] == 'thunder' else
                       'previous_draft_refinement')
        history_directory = ('before_draft_v3' if armor['key'] == 'thunder' else
                             'before_draft_refinement_v3')
        delivery[history_key] = {
                'source_commit': armor['baseline']['source_commit'],
                'snapshot': '../' + spec[4] + '/revisions/' + history_directory + '/snapshot.json',
                'snapshot_sha256': armor['baseline']['snapshot']['sha256'],
                'scene_sha256': armor['baseline']['scene']['sha256'],
        }
        historical_texture = metadata.get('original_based_runtime', {}).get('previous_texture_only')
        if historical_texture:
            delivery['previous_texture_only'] = historical_texture
        metadata['original_based_runtime'] = delivery
        metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
        row = next(row for row in catalog if row['design_id'] == armor['design_id'])
        row['original_based_runtime'] = delivery
        updated.append(armor['design_id'])
    untouched_after = [row for row in catalog if row['design_id'] not in set(updated)]
    if untouched_after != untouched_before:
        raise ValueError('Unrelated gallery rows changed')
    embedded = json.dumps(catalog, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c')
    template = (ART / 'tools/gallery.template.html').read_text(encoding='utf-8')
    if template.count('__CATALOG_JSON__') != 1:
        raise ValueError('Invalid original gallery catalog slot')
    path.write_text(template.replace('__CATALOG_JSON__', embedded), encoding='utf-8', newline='\n')
    return {'updated_catalog_rows': updated, 'unrelated_catalog_rows_unchanged': len(untouched_after)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--update-gallery', action='store_true',
                        help='Publish C07/C08/C09 only after all three refinement deliveries are ready')
    args = parser.parse_args()
    data = {'schema_version': 3, 'date': date.today().isoformat(),
            'delivery_revision': DELIVERY_REVISION,
            'title': 'Thunder／Atom／Pegasus · 原版基底遊戲素材',
            'browser_interaction': 'NOT RUN', 'browser_limitation': BROWSER_LIMITATION,
            'armors': [collect_armor(spec) for spec in ARMORS]}
    encoded = json.dumps(data, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c')
    template = (WORK / 'review_template.html').read_text(encoding='utf-8')
    if template.count('__REVIEW_DATA__') != 1 or template.count('__REVIEW_DATE__') != 1:
        raise ValueError('Invalid review template data slot')
    rendered = template.replace('__REVIEW_DATA__', encoded).replace('__REVIEW_DATE__', data['date'])
    (WORK / 'index.html').write_text(rendered, encoding='utf-8', newline='\n')
    (WORK / 'review_data.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    report = {'status': 'PASS_STATIC_BROWSER_NOT_RUN', 'page': resource(WORK / 'index.html'),
              'data': resource(WORK / 'review_data.json'),
              'armors_ready': [row['key'] for row in data['armors'] if row['ready']],
              'browser_interaction': 'NOT RUN', 'browser_limitation': BROWSER_LIMITATION,
              'art_acceptance': 'NOT RUN'}
    if args.update_gallery:
        report['gallery'] = update_gallery(data)
    (WORK / 'page_validate.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()

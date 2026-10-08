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
BROWSER_LIMITATION = ('NOT RUN：本輪 CUA 預覽被安全政策拒絕，file:// 協定不受支援；'
                      '未以 HTTP 或其他介面繞過。已檢查 JavaScript 語法與本機資源 SHA。')
ARMORS = (
    ('thunder', 'Thunder', 'C-07', 6, 'thunder_original_v2',
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


def format_metrics(manifest: dict, runtime_id: int) -> list[dict]:
    geometry = manifest.get('geometry', {})
    part = geometry.get('parts', {}).get(f'ArmorHead_{runtime_id:02}', {})
    topology = manifest.get('topology', {})
    uv = manifest.get('uv_summary', {})
    rows = []
    if 'max_displacement_fraction_of_smallest_dimension' in part:
        value = part['max_displacement_fraction_of_smallest_dimension']
        rows.append({'label': '頭部相對原版最大位移', 'value': f'{value * 100:.3f}%',
                     'note': '按原頭部最小軸尺寸正規化；不是概念圖相似率。'})
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
        'scope': ('以真正原版 Thunder 頭部重新生成貼圖；修改前身甲保留。'
                  if slug == 'thunder' else '以真正原版四部件與 UV 為基底，轉譯既有裝甲概念。'),
        'captures': {}, 'metrics': [], 'tests': [], 'residuals': [], 'sources': [],
        'art_acceptance': 'NOT RUN・等待使用者美術評價',
        'browser_interaction': 'NOT RUN',
        'visual_inspection': 'NOT RUN',
    }
    # Thunder's rejected newer helmet is not a design authority for this pass.
    legacy = ART / f'references/legacy/c{int(design_id[2:]):02}_front.png'
    art_path = legacy if slug == 'thunder' else ART / metadata['images']['concept']
    result['reference'] = {**resource(art_path),
        'label': '本輪頭盔基底：真正原版 Thunder' if slug == 'thunder' else '目前裝甲設計參考',
        'note': ('新版頭部從原版模型、UV 與 atlas 直接製作。身甲保留修改前版本；其配色概念另列，概念中的低冠頭盔不作目標。'
                 if slug == 'thunder' else '概念圖只用來看設計，不是同相機遊戲擷取，也不是本輪生成的貼圖。')}
    if slug == 'thunder':
        result['body_reference'] = resource(ART / metadata['user_review']['preferred_art']['path'])
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
    aliases = ({'diffuse_front': 'full_front', 'diffuse_quarter': 'full_quarter',
        'diffuse_side': 'full_side', 'diffuse_rear': 'full_rear', 'idle_rifle': 'idle',
        'run_rifle': 'run', 'reload_04': 'reload', 'level_01_gameplay': 'game_level_1',
        'level_08_gameplay': 'game_level_3'} if slug == 'thunder' else {})
    for suffix, label, scope in VIEWS:
        native_suffix = aliases.get(suffix, suffix)
        original = available.get('original_' + native_suffix)
        after = available.get('new_' + native_suffix)
        before = available.get('before_' + native_suffix)
        if original or after:
            if slug == 'thunder' and suffix == 'level_08_gameplay':
                label = '區域 03・遊戲'
            result['captures'][suffix] = {'label': label, 'scope': scope,
                                          'original': original, 'after': after, 'before': before}
    result['metrics'] = format_metrics(manifest, runtime_id)
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
    """Patch only three catalog rows; keep all other embedded values identical."""
    pending = [armor['name'] for armor in data['armors'] if not armor['ready']]
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
            'note': armor['scope'],
        }
        metadata['original_based_runtime'] = delivery
        metadata_path.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
        row = next(row for row in catalog if row['design_id'] == armor['design_id'])
        row['original_based_runtime'] = delivery
        if armor['design_id'] == 'C-07':
            row['helmet_art'] = metadata['helmet_art']
        updated.append(armor['design_id'])
    untouched_after = [row for row in catalog if row['design_id'] not in set(updated)]
    if untouched_after != untouched_before:
        raise ValueError('Unrelated gallery rows changed')
    embedded = json.dumps(catalog, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c')
    path.write_text(text[:match.start(2)] + embedded + text[match.end(2):], encoding='utf-8', newline='\n')
    return {'updated_catalog_rows': updated, 'unrelated_catalog_rows_unchanged': len(untouched_after)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--update-gallery', action='store_true',
                        help='Publish only after all three runtime deliveries are ready')
    args = parser.parse_args()
    data = {'schema_version': 1, 'date': date.today().isoformat(),
            'title': 'Thunder／Atom／Pegasus · 原版基底遊戲素材',
            'browser_interaction': 'NOT RUN', 'browser_limitation': BROWSER_LIMITATION,
            'armors': [collect_armor(spec) for spec in ARMORS]}
    encoded = json.dumps(data, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c')
    template = (WORK / 'review_template.html').read_text(encoding='utf-8')
    if template.count('__REVIEW_DATA__') != 1 or template.count('__REVIEW_DATE__') != 1:
        raise ValueError('Invalid review template data slot')
    rendered = template.replace('__REVIEW_DATA__', encoded).replace('__REVIEW_DATE__', data['date'])
    (WORK / 'index.html').write_text(rendered, encoding='utf-8')
    (WORK / 'review_data.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    report = {'status': 'PASS_STATIC_BROWSER_NOT_RUN', 'page': resource(WORK / 'index.html'),
              'data': resource(WORK / 'review_data.json'),
              'armors_ready': [row['key'] for row in data['armors'] if row['ready']],
              'browser_interaction': 'NOT RUN', 'browser_limitation': BROWSER_LIMITATION,
              'art_acceptance': 'NOT RUN'}
    if args.update_gallery:
        report['gallery'] = update_gallery(data)
    (WORK / 'page_validate.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()

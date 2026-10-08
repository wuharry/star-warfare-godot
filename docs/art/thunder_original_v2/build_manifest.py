"""Bind Thunder's original-head delivery to real engine evidence; no rendering."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import shutil

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
GENERATOR_PATH = Path('C:/Users/whw88/.codex/generated_images/01a0d34a-7c78-72d0-b7ae-7c134c979b6f/exec-53ceea1b-de51-4fa9-b90d-c955fe8a9141.png')
VIEW_OBSERVATIONS = {
    'head_front': '新版保留原版高單冠、V 形壓眉、單片金橙面窗與短藍下框；玻璃無中央黑裂縫，明亮 V 形是反光而非兩個深色凹槽。修改前是低圓冠、細密側頰與中央通風插片。',
    'head_quarter': '原版與新版的冠頂、眉沿、耳盤和下框位置一致；新版陰影與亮邊更清楚。沒有成人 C07 低冠替換；側頰面窗邊界連續。',
    'head_side': '原版長後掠鰭冠與耳後金線保留；圓耳中心維持深色，無新增繁複齒輪／浮板。新版下顎與原版同樣短。',
    'head_rear': '後腦金色折線、冠背金三角、下方黑色開口位於原位置；未把玻璃或正臉誤畫到後側。',
    'full_front': '新版恢復原版高冠的短壯角色辨識；身甲沿用修改前較銳的藍金分片和磨損，與前版非頭部相同。',
    'full_quarter': '頭部與肩領比例可讀，高冠完整入鏡；原版與新版身甲精細程度不同，這輪沒有把 body 換回原版。',
    'full_side': '單冠和短下顎在全身側視清楚；頭下深色領區與原版一致，未看到新頭部脫落或相交肩板。',
    'full_rear': '高冠、金色後腦折線和黑頸區清楚；身甲與修改前相同，頭部不是舊低圓冠。',
    'clay_front': '去掉貼圖後可見新版頭部回到原版高冠輪廓；身甲仍保留修改前切面。',
    'clay_side': '頭部側面輪廓與原版吻合；目前 body 肩臂／靴子切面較多屬保留前版，不是本次頭部生成引入。',
    'idle': '持槍待機可辨識高冠、金橙面窗與圓耳，槍械遮住部分胸甲；未見頭殼斷開。',
    'run': '固定跑動姿勢中高冠與短下框維持，面窗沒有被拉開；四肢沿用前版。',
    'reload': '換彈低頭取樣中耳盤、冠側與面窗仍在原頭部位置；槍遮住部分面窗下緣，不能由這一張斷言完整動畫都無穿插。',
    'game_level_1': '區域 01 的第三人稱背視中高冠和金色後腦線清楚，與修改前低圓冠可區分。只看可讀性，非環境逐像素比較。',
    'game_level_3': '區域 03 冷色光下仍能辨認鋼藍高冠與金線；背包遮住左背，未見新頭部缺件或錯色。',
}
RESIDUALS = [
    '這輪保留真正原版的高鰭冠與 V 形壓眉，外形改動為 0；是原版頭盔的貼圖整理，不是新的低冠概念頭盔。',
    '新頭圖比原版更乾淨、藍色更明亮；局部亮邊磨損仍較銳，冠頂／下框的塗裝可再減淡。',
    '面窗是單片連續金橙色，亮 V 形反光較強；不是兩道深色凹槽，但玻璃反光強度仍待使用者評價。',
    '身甲保持 bef5b833 的切面、白邊磨損與黑褐軟衣；目前頭身整體不是對真正原版全套的 0% 或 20% 量測。',
    '這次只看固定待機／跑動／換彈取樣和兩關畫面；完整動畫影片、使用者美術接受與手機效能尚未驗證。',
]


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8-sig'))


def resolve(path: str) -> Path:
    return ROOT / path.removeprefix('res://')


def describe(path: Path, expected_sha: str | None = None) -> dict:
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if expected_sha and digest != expected_sha:
        raise ValueError(f'Stale evidence: {path}')
    result = {'path': path.relative_to(ROOT).as_posix(), 'sha256': digest, 'bytes': len(raw)}
    if path.suffix.lower() in ('.png', '.jpg', '.jpeg'):
        with Image.open(path) as image:
            image.load()
            result.update(dimensions=list(image.size), mode=image.mode)
    return result


def save(path: Path, value: dict | list) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main() -> None:
    config_path = WORK / 'runtime_config.json'
    config = load(config_path)
    compile_path = WORK / 'build/compile_report.json'
    runtime_path = WORK / 'review/runtime_test.json'
    capture_path = WORK / 'review/engine/capture.json'
    compile_report, runtime, capture = (load(path) for path in (compile_path, runtime_path, capture_path))
    if compile_report['status'] != 'PASS' or runtime['status'] != 'PASS':
        raise ValueError('Compile/runtime evidence must pass before a delivery manifest is emitted')
    scene = describe(resolve(config['output_scene']), compile_report['scene_sha256'])
    if runtime['default_scene_sha256'] != scene['sha256'] or capture['runtime_scene_sha256'] != scene['sha256']:
        raise ValueError('Runtime/capture reports do not bind current scene')
    if not capture['save_unchanged'] or capture['errors'] or capture['resource_mode'] != 'normal_imported_resources':
        raise ValueError('Capture resource/save/error guard failed')
    head = compile_report['true_original_head']
    if head != {'all_native_surface_buffers_unchanged': True, 'geometry_displacement_fraction': 0.0,
                'skin_binds': 28, 'triangles': 196, 'uv_changed_fraction': 0.0, 'uv_coordinates': 147}:
        raise ValueError('The true-original head contract changed')
    if not compile_report['body_baseline']['three_parts_native_buffers_materials_skin_transform_unchanged']:
        raise ValueError('Preserved body baseline differs')
    if not runtime['true_original_geometry_uv_topology_skin_transform_exact']:
        raise ValueError('Runtime original-head invariants failed')
    frames = capture['frames']
    if len(frames) != 45 or capture['paired_view_count'] != 15:
        raise ValueError('Expected 15 original/new/before views')
    expected_frames = {(version, view) for version in ('original', 'new', 'before') for view in VIEW_OBSERVATIONS}
    if {(frame['version'], frame['view']) for frame in frames} != expected_frames:
        raise ValueError('Capture view set is incomplete')
    captures = []
    for frame in frames:
        path = capture_path.parent / frame['file']
        row = describe(path, frame['sha256'])
        if row['dimensions'] != [frame['width'], frame['height']]:
            raise ValueError('Capture dimensions changed: ' + frame['file'])
        row.update(version=frame['version'], view=frame['view'],
                   controlled_pair=frame['controlled_pair'], observation=VIEW_OBSERVATIONS[frame['view']])
        captures.append(row)
    visual_path = WORK / 'visual_review.json'
    # A manifest builder cannot claim that a freshly changed image was viewed.
    # visual_review.json is authored only after actual view_image inspection.
    visual = load(visual_path)
    if visual['capture_summary']['sha256'] != describe(capture_path)['sha256']:
        raise ValueError('Captures changed after visual review; inspect them again before updating the review record')
    if {(row['path'], row['sha256']) for row in visual['images']} != {(row['path'], row['sha256']) for row in captures}:
        raise ValueError('Current capture pixels are not the visually reviewed files')
    if visual['viewed_image_count'] != 45 or visual['blocking_findings']:
        raise ValueError('Visual review missing or contains unresolved blockers')
    native = describe(resolve(config['native_generated_png']), compile_report['native_png_sha256'])
    archive = describe(WORK / 'generated/head_attempt_01.png', native['sha256'])
    available = GENERATOR_PATH.is_file()
    if available and hashlib.sha256(GENERATOR_PATH.read_bytes()).hexdigest() != native['sha256']:
        raise ValueError('Canonical/archive pixels differ from native built-in output')
    refs = []
    for name, original, role in (
        ('original_head_atlas.png', resolve(config['original_head_texture']), 'sole_layout_shape_and_original_helmet_authority'),
        ('body_palette_reference.png', ROOT / 'docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png',
         'body_palette_and_soft_painted_shading_only_no_helmet_shape_transfer'),
    ):
        snapshot = WORK / 'generation_references' / name
        snapshot.parent.mkdir(exist_ok=True)
        if not snapshot.exists():
            shutil.copyfile(original, snapshot)
        source = describe(original)
        if name == 'original_head_atlas.png' and source['sha256'] != config['original_head_texture_sha256']:
            raise ValueError('True-original atlas no longer matches config')
        refs.append({'input': source, 'snapshot': describe(snapshot, source['sha256']), 'role': role})
    prompt_path = WORK / 'prompts/head_attempt_01.txt'
    generation = {'label': 'head', 'attempt': 1, 'selected': True, 'date': '2026-10-08',
        'tool': 'built-in image_gen.imagegen', 'generated_file': str(GENERATOR_PATH),
        'native_generator_path_available': available,
        'archive': archive, 'canonical': native, 'prompt': describe(prompt_path),
        'full_prompt': prompt_path.read_bytes().decode('utf-8'), 'references': refs,
        'postprocessing': 'none; native output copied byte-for-byte to archive and canonical PNG',
        'visual_review': describe(visual_path),
        'scope': 'native opaque diffuse atlas mapped onto unchanged true-original Thunder head geometry/UV'}
    generation_path = WORK / 'generation_inputs.json'
    save(generation_path, [generation])
    files = [scene, native, describe(resolve(config['portable_texture']), compile_report['portable_texture_sha256']),
             describe(config_path), describe(WORK / 'head_source.json')]
    for field in ('source_scene', 'source_buffer', 'before_scene'):
        files.append(describe(resolve(config[field]), config[field + '_sha256']))
    for path, digest in config['inherited_body_resource_sha256'].items():
        files.append(describe(resolve(path), digest))
    for path, digest in config['protected_alternates'].items():
        files.append(describe(resolve(path), digest))
    manifest = {'schema_version': 1, 'date': '2026-10-08', 'design_id': 'C-07', 'runtime_id': 6,
        'name': 'Thunder', 'revision': config['revision'],
        'status': 'runtime_integrated_pending_user_art_review',
        'scope': config['constraint'], 'files': files, 'generation': describe(generation_path),
        'geometry': {'scope': 'true_original_head_only', 'parts': {'ArmorHead_06': {
            'max_displacement_fraction_of_smallest_dimension': 0.0,
            'dimension_delta_fraction': [0.0, 0.0, 0.0], 'triangles': 196,
            'uv_coordinates': 147, 'uv_changed_fraction': 0.0}}},
        'uv_summary': {'scope': 'head_only', 'original_coordinate_count': 147,
                       'changed_coordinate_count': 0, 'changed_coordinate_fraction': 0.0},
        'topology': {'triangles': compile_report['runtime_triangle_counts']['current_whole_suit'],
                     'head_triangles': 196, 'head_uv_coordinates': 147, 'original_bones': 28, 'parts': 4,
                     'note': '整套包含 bef5b833 身甲，不宣稱真正原版全套幾何改動為 0%。'},
        'body_baseline': compile_report['body_baseline'],
        'metric_scope': 'Head-only zero geometry/UV changes versus true original SW1. Body matches restored bef5b833, not true-original whole-suit geometry.',
        'tests': {'compile_original_head_and_preserved_body': {'status': 'PASS', 'file': describe(compile_path)},
                  'runtime_equips_skin_uv_store_and_animation': {'status': 'PASS', 'file': describe(runtime_path)}},
        'captures': [{key: value for key, value in row.items() if key != 'observation'} for row in captures],
        'capture_summary': describe(capture_path), 'visual_review': describe(visual_path),
        'residuals': RESIDUALS, 'art_acceptance': 'NOT RUN', 'browser_interaction': 'NOT RUN',
        'mobile_performance': 'NOT RUN', 'capture_log': {'status': 'NO_SEPARATE_LOG_FILE',
            'note': 'Normal ANGLE/Direct3D11 capture completed in the root console. The requested log path was unavailable at launch; no separate driver log is claimed. The 45 native PNGs and capture.json are independently SHA-bound.'}}
    save(WORK / 'manifest.json', manifest)
    print(json.dumps({'status': 'PASS', 'captures': len(captures), 'viewed': 45,
                      'scene_sha256': scene['sha256'], 'native_png_sha256': native['sha256'],
                      'manifest': describe(WORK / 'manifest.json')}, ensure_ascii=False))


if __name__ == '__main__':
    main()

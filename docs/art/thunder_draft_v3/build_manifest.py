"""Bind Thunder's B-draft head revision to native art and final engine evidence.

This assembler reads existing generation, geometry, runtime and visual reports.
It never changes a PNG, source snapshot, scene, target or generation record.
"""
from __future__ import annotations

from datetime import date
import hashlib
import importlib.util
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
BEFORE_SHA256 = '8ef68f9c7d9e67b32d01c1632bdf765debc527117f872e1a56c8ab00c02c09fb'
SOURCE_COMMIT = '3ed1c2911e1eea5162e30d0bab331fd41a1d29f9'
APPROVED_B_SHA256 = '11180e358451435942a1ef1749e9bbbb5e7d427744329d3377f5982a13e3bb9c'
VIEWS = {'head_front', 'head_quarter', 'head_side', 'head_rear',
         'full_front', 'full_quarter', 'full_side', 'full_rear',
         'clay_front', 'clay_side', 'idle', 'run', 'reload',
         'game_level_1', 'game_level_3'}
VISUAL_STATUSES = {'VISUALLY_REVIEWED_PENDING_USER_REVIEW',
                   'ENGINEERING_CANDIDATE_PENDING_USER_ART_REVIEW'}


def load(path: Path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def resolve(path: str) -> Path:
    value = Path(path.removeprefix('res://'))
    return value if value.is_absolute() else ROOT / value


def describe(path: Path, expected_sha: str | None = None) -> dict:
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if expected_sha and digest != expected_sha:
        raise ValueError(f'Stale evidence: {path}')
    result = {'path': path.relative_to(ROOT).as_posix(), 'sha256': digest, 'bytes': len(raw)}
    if path.suffix.lower() in {'.png', '.jpg', '.jpeg'}:
        with Image.open(path) as image:
            result.update(dimensions=list(image.size), mode=image.mode)
    return result


def verify_descriptor(record: dict) -> dict:
    actual = describe(resolve(record['path']), record['sha256'])
    for key in ['bytes', 'dimensions', 'mode']:
        if key in record and actual.get(key) != record[key]:
            raise ValueError(f'Stale descriptor {key}: {record["path"]}')
    return actual


def verify_history(config: dict) -> dict:
    path = resolve(config['before_snapshot'])
    record = describe(path, BEFORE_SHA256)
    if config['before_snapshot_sha256'] != BEFORE_SHA256:
        raise ValueError('Config does not pin the immutable Thunder history')
    snapshot = load(path)
    if (snapshot['source_commit'] != SOURCE_COMMIT or
            snapshot['status'] != 'FROZEN_ORIGINAL_BASED_THUNDER_V2_BASELINE' or
            len(snapshot['files']) != 126):
        raise ValueError('Unexpected Thunder history scope')
    originals = set()
    for row in snapshot['files']:
        target = resolve(row['snapshot_path'])
        if not target.resolve().is_relative_to(path.parent.resolve()):
            raise ValueError('History resource escapes its snapshot')
        if target != path.parent / row['original_path']:
            raise ValueError('History resource does not match its original path')
        verify_descriptor({'path': row['snapshot_path'], 'sha256': row['sha256'], 'bytes': row['bytes']})
        originals.add(row['original_path'])
    if len(originals) != 126:
        raise ValueError('Duplicate Thunder history resources')
    return {**record, 'source_commit': SOURCE_COMMIT, 'files_verified': 126}


def verify_generation(config: dict, native: dict) -> tuple[dict, dict]:
    path = WORK / 'generation_inputs.json'
    rows = load(path)
    selected = [row for row in rows if row.get('selected')]
    if len(selected) != 1 or selected[0].get('label') != 'head':
        raise ValueError('Exactly one selected native head attempt is required')
    for row in rows:
        archive = verify_descriptor(row['archive'])
        prompt = verify_descriptor(row['prompt'])
        exact_prompt = resolve(prompt['path']).read_bytes().decode('utf-8')
        if row['full_prompt'] != exact_prompt:
            raise ValueError('Generation full_prompt differs from actual submitted bytes')
        if 'base_prompt' in row:
            base = verify_descriptor(row['base_prompt'])
            if resolve(base['path']).read_bytes().decode('utf-8') not in exact_prompt:
                raise ValueError('Required integration prompt is missing')
        native_path = row.get('native_generated_path', row.get('generated_file'))
        if native_path and Path(native_path).is_file():
            if hashlib.sha256(Path(native_path).read_bytes()).hexdigest() != archive['sha256']:
                raise ValueError('Archived PNG differs from native imagegen output')
        for reference in row['references']:
            original = verify_descriptor(reference['input'])
            verify_descriptor(reference['snapshot'])
            if original['sha256'] != reference['snapshot']['sha256']:
                raise ValueError('Generation input snapshot changed')
    chosen = selected[0]
    canonical = verify_descriptor(chosen['canonical'])
    if chosen['archive']['sha256'] != canonical['sha256'] or canonical['sha256'] != native['sha256']:
        raise ValueError('Selected native/archive/canonical PNG bytes differ')
    if resolve(canonical['path']).resolve() != resolve(config['native_generated_png']).resolve():
        raise ValueError('Selected native PNG is not the configured runtime map')
    if not any(ref['input']['sha256'] == APPROVED_B_SHA256 for ref in chosen['references']):
        raise ValueError('Selected generation does not reference the current gallery B draft')
    return describe(path), chosen


def main() -> None:
    config_path = WORK / 'runtime_config.json'
    config = load(config_path)
    history = verify_history(config)
    compile_path = WORK / 'build/compile_report.json'
    runtime_path = WORK / 'review/runtime_test.json'
    capture_path = WORK / 'review/engine/capture.json'
    compile_report, runtime, capture = (load(path) for path in [compile_path, runtime_path, capture_path])
    if compile_report['status'] != 'PASS' or runtime['status'] != 'PASS':
        raise ValueError('Actual compile/runtime evidence must pass')
    scene = describe(resolve(config['output_scene']), compile_report['scene_sha256'])
    target = describe(resolve(config['head_target']), config['head_target_sha256'])
    target_data = load(resolve(config['head_target']))
    shape = describe(resolve(target_data['shape_file']), target_data['shape_sha256'])
    if target_data['design_authority_sha256'] != APPROVED_B_SHA256:
        raise ValueError('Head target does not bind the current B draft')
    design = describe(resolve(target_data['design_authority']), APPROVED_B_SHA256)
    if runtime['default_scene_sha256'] != scene['sha256'] or capture['runtime_scene_sha256'] != scene['sha256']:
        raise ValueError('Runtime/capture reports do not bind the current scene')
    if capture['target_sha256'] != target['sha256'] or capture['before_scene_sha256'] != config['before_scene_sha256']:
        raise ValueError('Capture target or frozen before scene changed')
    if not capture['save_unchanged'] or capture['errors'] or capture['resource_mode'] != 'normal_imported_resources':
        raise ValueError('Capture resource/save/error guard failed')
    head = compile_report['true_original_head']
    if not (0 < head['max_displacement_fraction_of_smallest_dimension'] <= .20 and
            head['max_dimension_change_fraction'] <= .20):
        raise ValueError('Head does not meet its cumulative original-source geometry budget')
    if not (compile_report['head_original_uv_topology_skin_transform_exact'] and
            compile_report['delivered_head_matches_target'] and
            runtime['head_original_uv_topology_skin_transform_exact'] and
            runtime['head_positions_match_pinned_target']):
        raise ValueError('Original immutable head channels or authored target differ')
    if compile_report['target_sha256'] != target['sha256'] or runtime['target_sha256'] != target['sha256']:
        raise ValueError('Compile/runtime evidence targets changed')
    if not runtime['body_buffers_materials_skin_transform_vs_3ed1c291_exact']:
        raise ValueError('Runtime body differs from the frozen 3ed baseline')
    body = compile_report['body_baseline']
    if not (body['three_parts_native_buffers_materials_skin_transform_unchanged'] and
            body['commit'] == SOURCE_COMMIT and body['scene_sha256'] == config['before_scene_sha256']):
        raise ValueError('Compiler did not preserve the frozen body')
    contract_path = ROOT / 'tools/thunder_draft_v3/head_contract.py'
    spec = importlib.util.spec_from_file_location('thunder_independent_head_contract', contract_path)
    contract = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(contract)
    independent = contract.validate_files(config_path)
    for key in ['max_rest_displacement', 'max_displacement_fraction_of_smallest_dimension',
                'max_dimension_change_fraction']:
        if abs(independent[key] - head[key]) > 1e-5:
            raise ValueError('Independent source/target metric differs from compiler: ' + key)
    frames = capture['frames']
    if (len(frames) != 45 or capture['paired_view_count'] != 15 or
            {(row['version'], row['view']) for row in frames} !=
            {(version, view) for version in ['original', 'before', 'new'] for view in VIEWS}):
        raise ValueError('Expected all 45 original/before/new captures')
    captures = []
    for frame in frames:
        path = capture_path.parent / frame['file']
        if path.name != frame['version'] + '_' + frame['view'] + '.png':
            raise ValueError('Unexpected capture filename')
        row = describe(path, frame['sha256'])
        if row['dimensions'] != [frame['width'], frame['height']]:
            raise ValueError('Capture dimensions changed')
        row.update(version=frame['version'], view=frame['view'], controlled_pair=frame['controlled_pair'])
        captures.append(row)
    visual_path = next((path for path in [WORK / 'review/visual_review.json', WORK / 'visual_review.json'] if path.is_file()),
                       WORK / 'review/visual_review.json')
    visual = load(visual_path)
    if visual['status'] not in VISUAL_STATUSES or visual['blocking_findings']:
        raise ValueError('Visual review is missing or contains unresolved blockers')
    if visual['capture_summary']['sha256'] != describe(capture_path)['sha256']:
        raise ValueError('Visual review does not bind the current captures')
    if (visual.get('actual_images_inspected', visual.get('viewed_image_count')) != 45 or
            len(visual['images']) != 45 or
            {(row['path'], row['sha256']) for row in visual['images']} !=
            {(row['path'], row['sha256']) for row in captures}):
        raise ValueError('Not all 45 current capture files were visually reviewed')
    if any(not row.get('visually_inspected') for row in visual['images']):
        raise ValueError('A capture has no actual visual inspection record')
    native = describe(resolve(config['native_generated_png']), compile_report['native_png_sha256'])
    if (capture['native_png_sha256'] != native['sha256'] or
            not compile_report['pixel_bytes_preserved'] or
            capture['portable_texture_sha256'] != compile_report['portable_texture_sha256']):
        raise ValueError('Compile/capture native and portable image evidence changed')
    generation, selected = verify_generation(config, native)
    files = [scene, native, describe(resolve(config['portable_texture']), compile_report['portable_texture_sha256']),
             describe(config_path), target, shape,
             describe(resolve(config['head_source_json']), config['head_source_json_sha256'])]
    for field in ['source_scene', 'source_buffer', 'before_scene']:
        files.append(describe(resolve(config[field]), config[field + '_sha256']))
    for key in ['inherited_body_resource_sha256', 'protected_alternates']:
        for path, expected in config[key].items():
            files.append(describe(resolve(path), expected))
    log_path = WORK / 'review/draft_v3_angle_capture.log'
    log = log_path.read_text(encoding='utf-8')
    banner = next(line for line in log.splitlines() if line.startswith('OpenGL API '))
    if not ('ANGLE' in banner and 'Direct3D11' in banner and 'THUNDER_DRAFT_V3_CAPTURE_PASS' in log):
        raise ValueError('Normal ANGLE capture driver log is missing')
    independent_path = WORK / 'review/independent_head_contract.json'
    independent_path.write_text(json.dumps({
        'status': 'PASS', 'scope': 'Pure Python source/target geometry and immutable native resource pins; no engine or art acceptance.',
        'source': describe(resolve(config['head_source_json'])), 'target': target,
        'validator': describe(contract_path), 'geometry': independent,
        'engine_run_by_validator': False, 'art_acceptance': 'NOT RUN'},
        ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    manifest = {
        'schema_version': 1, 'date': date.today().isoformat(), 'design_id': 'C-07', 'runtime_id': 6,
        'name': 'Thunder', 'revision': config['revision'], 'status': 'runtime_integrated_pending_user_art_review',
        'scope': config['constraint'], 'files': files, 'generation': generation,
        'selected_generation': selected,
        'design_authority': design,
        'previous_original_based_delivery': history,
        'geometry': {'scope': 'true_original_head_only', 'parts': {'ArmorHead_06': head}},
        'uv_summary': {'scope': 'head_only', 'original_coordinate_count': 147,
                       'changed_coordinate_count': 0, 'changed_coordinate_fraction': 0.0},
        'topology': {'triangles': compile_report['runtime_triangle_counts']['current_whole_suit'],
                     'head_triangles': 196, 'head_uv_coordinates': 147, 'original_bones': 28, 'parts': 4,
                     'note': '整套身甲沿用 3ed；20% 限制只衡量真正原版頭部的累積位移與軸尺寸。'},
        'body_baseline': body,
        'metric_scope': 'Head position/dimension budgets are cumulative from true-original SW1. All original head UV/index/skin/weights/transforms remain exact. Body/limbs match frozen 3ed; no original-whole-suit20% or concept-likeness percentage is claimed.',
        'tests': {'compile_bounded_head_and_preserved_body': {'status': 'PASS', 'file': describe(compile_path)},
                  'runtime_equips_skin_uv_store_and_animation': {'status': 'PASS', 'file': describe(runtime_path)},
                  'independent_original_source_target_contract': {'status': 'PASS', 'file': describe(independent_path)}},
        'captures': captures, 'capture_summary': describe(capture_path), 'visual_review': describe(visual_path),
        'residuals': visual['residuals'], 'art_acceptance': 'NOT RUN', 'browser_interaction': 'NOT RUN',
        'mobile_performance': 'NOT RUN',
        'capture_driver_evidence': {'driver': 'opengl3_angle', 'renderer_banner': banner, 'log': describe(log_path)},
    }
    path = WORK / 'manifest.json'
    path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps({'status': 'PASS', 'captures': 45, 'actual_images_inspected': 45,
                      'manifest': describe(path)}, ensure_ascii=False))


if __name__ == '__main__':
    main()

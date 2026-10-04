"""Validate fresh first-integration evidence and emit an armor delivery manifest."""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
LABELS = {'head', 'body', 'shoulder', 'hand', 'foot'}


def describe(path):
    path = Path(path)
    if not path.is_absolute():
        path = ROOT / path
    data = path.read_bytes()
    record = {'path': path.relative_to(ROOT).as_posix() if path.is_relative_to(ROOT) else str(path),
              'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}
    if path.suffix.lower() in ['.png', '.jpg', '.jpeg']:
        with Image.open(path) as image:
            record.update(dimensions=list(image.size), mode=image.mode)
    return record


def load(path):
    return json.loads(path.read_text(encoding='utf-8'))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--armor', choices=['hydra', 'strike', 'titan'], required=True)
    slug = parser.parse_args().armor
    work = ROOT / f'docs/art/{slug}_runtime_v1'
    config = load(work / 'runtime_config.json')
    assets = ROOT / config['asset']
    source_path, target_path = work / 'build/source.json', work / 'build/target.json'
    scene, glb, master = assets / f'{slug}.scn', assets / f'{slug}.glb', work / f'build/{slug}_master.blend'
    geometry_path = work / 'build/geometry.json'
    hashes = {'source_sha256': describe(source_path)['sha256'], 'target_sha256': describe(target_path)['sha256'],
              'geometry_sha256': describe(geometry_path)['sha256'], 'current_scene_sha256': describe(scene)['sha256'],
              'glb_sha256': describe(glb)['sha256'], 'master_sha256': describe(master)['sha256']}
    frozen_path = ROOT / config['original_source_snapshot']
    frozen = load(frozen_path)
    assert len(frozen['files']) == 13
    for name, record in frozen['files'].items():
        assert describe(frozen_path.parent / name)['sha256'] == record['sha256'], 'Frozen original changed: ' + name
    assert source_path.read_bytes() == (frozen_path.parent / 'source.json').read_bytes()
    assert describe(ROOT / config['source_node_index'])['sha256'] == config['source_node_index_sha256']
    assert describe(ROOT / frozen['original_scene'].removeprefix('res://'))['sha256'] == frozen['original_scene_sha256']
    inputs = load(work / 'generation_inputs.json')
    chosen = [row for row in inputs if row['selected']]
    assert len(chosen) == 5 and {row['label'] for row in chosen} == LABELS
    maps = {row['label']: describe(ROOT / row['output'])['sha256'] for row in chosen}
    generation = []
    for row in inputs:
        archive = describe(row['archive'])
        assert archive['sha256'] == row['archive_sha256'] == describe(row['generated_file'])['sha256']
        assert archive['dimensions'] == row['output_size']
        assert describe(row['prompt'])['sha256'] == row['prompt_sha256']
        assert describe(row['base_prompt'])['sha256'] == row['base_prompt_sha256']
        assert (ROOT / row['base_prompt']).read_text() in (ROOT / row['prompt']).read_text()
        refs = []
        for reference in row['references']:
            saved = describe(reference['snapshot'])
            assert saved['sha256'] == reference['sha256']
            refs.append({**reference, 'immutable_file': saved})
        entry = {**row, 'archive': archive, 'prompt': describe(row['prompt']), 'references': refs}
        if row['selected']:
            assert maps[row['label']] == archive['sha256']
            entry['canonical'] = describe(row['output'])
            entry['runtime_label'] = row['label']
        generation.append(entry)
    tests = {}
    reports = {}
    for name in ['runtime_test', 'roundtrip_test', 'proportion_test', 'delivery_validate', 'original_scene_invariants', 'glb_images_test']:
        path = work / f'review/{name}.json'
        report = load(path)
        assert report['status'] == 'PASS', name + ' failed'
        reports[name] = report
        tests[name] = {'file': describe(path), 'status': 'PASS'}
    for name in ['runtime_test', 'roundtrip_test']:
        report = reports[name]
        assert report['runtime_scene_sha256'] == hashes['current_scene_sha256']
        assert report['target_sha256'] == hashes['target_sha256'] and report['save_unchanged']
        assert len(report['poses']) == (15 if name == 'runtime_test' else 9)
    roundtrip = reports['roundtrip_test']
    assert roundtrip['glb_sha256'] == hashes['glb_sha256'] and roundtrip['original_bones'] == 28 and roundtrip['bind_aliases'] == 0
    assert roundtrip['head_atlas_pixels']['canonical_sha256'] == maps['head']
    assert len(roundtrip['head_atlas_pixels']['samples']) == 30 and roundtrip['head_atlas_pixels']['max_rgb_error'] <= .05
    delivery, actual_scene, images = (reports[n] for n in ['delivery_validate', 'original_scene_invariants', 'glb_images_test'])
    for key in ['master_sha256', 'source_sha256', 'target_sha256', 'geometry_sha256']:
        assert delivery[key] == hashes[key]
    assert delivery['mesh_count'] == 4 and delivery['surface_count'] == 5 and delivery['bone_count'] == 28
    assert delivery['triangle_count'] == config['original_triangles'] and delivery['packed_diffuse_count'] == 5
    assert delivery['changed_uv_coordinate_count'] == 0 and delivery['original_topology_indices_weights_rig_verified']
    for key in ['current_scene_sha256', 'source_sha256', 'target_sha256', 'geometry_sha256']:
        assert actual_scene[key] == hashes[key]
    assert actual_scene['original_bones'] == 28 and actual_scene['original_node_ids'] == config['original_node_ids']
    for record in actual_scene['records']:
        assert record['indices_skin_weights_bones_topology_exact'] and record['rest_position_uv_verified_against_target']
    for key in ['glb_sha256', 'source_sha256', 'target_sha256']:
        assert images[key] == hashes[key]
    assert images['original_topology_skin_weights_verified'] and set(images['images']) == LABELS
    for label in LABELS:
        assert images['images'][label]['canonical_sha256'] == delivery['images'][label]['canonical_sha256'] == maps[label]
        assert images['images'][label]['pixels_equal'] and images['images'][label]['max_channel_error_8bit'] == 0
        assert delivery['images'][label]['byte_identical']
    capture_path = work / 'review/engine/capture.json'
    capture = load(capture_path)
    assert capture['save_unchanged'] and capture['resource_mode'] == 'normal_imported_resources' and len(capture['files']) == 64
    assert capture['real_save_sha256_at_start'] == capture['real_save_sha256_at_end']
    assert capture['isolated_save_path_at_end'] == f'user://{slug}_v1_capture_profile.json'
    assert capture['runtime_scene_sha256'] == capture['scene_sha256_at_start'] == hashes['current_scene_sha256']
    assert capture['target_sha256'] == capture['target_sha256_at_start'] == hashes['target_sha256']
    assert capture['canonical_diffuse_sha256_at_start'] == maps
    captures = []
    for resource in capture['files']:
        record = describe(resource.removeprefix('res://'))
        assert capture['capture_sha256'][resource] == record['sha256']
        captures.append(record)
    log_path = work / 'review/original_integration_angle_capture.log'
    log = log_path.read_text(encoding='utf-8')
    banner = next(line for line in log.splitlines() if line.startswith('OpenGL API '))
    assert 'ANGLE' in banner and 'Direct3D11' in banner and 'ARMOR_CAPTURE_PASS files=64 save_unchanged=true' in log
    head_input = next(row for row in chosen if row['label'] == 'head')
    design_ref = next(r['snapshot'] for r in head_input['references'] if 'design_authority' in r['role'])
    body_ref = next(r['snapshot'] for row in chosen if row['label'] == 'body'
                    for r in row['references'] if r['role'] in ['approved_design', 'approved_body_design'])
    geometry = load(geometry_path)
    manifest = {'schema_version': 1, 'design_id': config['design_id'], 'runtime_id': config['runtime_id'], 'name': config['name'],
                'revision': slug + '_runtime_v1', 'texture_surface_revision': head_input['variant'],
                'status': 'runtime_integrated_pending_user_art_review', 'checked_at_utc': datetime.now(timezone.utc).isoformat(),
                'design_authority': describe(body_ref), 'helmet_design_authority': describe(design_ref),
                'original_source_snapshot': describe(frozen_path), 'source_node_index': describe(config['source_node_index']),
                'original_node_ids': config['original_node_ids'], 'geometry': geometry,
                'limits': {'local_geometry_displacement': .20, 'dimension_change': .20, 'silhouette_change': .20, 'uv_changed_fraction_per_material': .20, 'uv_coordinate_and_chart_counts_preserved': True},
                'topology': {'triangles': config['original_triangles'], 'original_bones': 28, 'parts': 4, 'surfaces': 5, 'diffuse_maps': 5},
                'files': [describe(p) for p in [scene, glb, master]] + [describe(assets / f'{label}_diffuse.png') for label in sorted(LABELS)],
                'generation': generation, 'tests': tests, 'captures': captures, 'capture_summary': describe(capture_path),
                'capture_driver_evidence': {'driver': 'opengl3_angle', 'renderer_banner': banner, 'log': describe(log_path)},
                'uv_summary': {'original_coordinate_count': delivery['original_uv_coordinate_count'], 'changed_coordinate_count': 0, 'changed_coordinate_fraction': 0, 'per_material': reports['runtime_test']['uv_edits']},
                'inherited_out_of_range_uv': reports['runtime_test'].get('legacy_out_of_range_uv', []),
                'metric_scope': 'True original source totals, head-only geometry deformation and unchanged original UV. Body/limb actual SCN raw mesh buffers exact; skin/indices/weights preserved. GLB exporter normalizes exchange weights, per-triangle identity independently verified. Artistic similarity is not measured by20%; pending user review.',
                'residuals': config.get('art_residuals', ['Original low-poly facets and some bright hand-painted contact edges remain.'])}
    (work / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    print(slug.upper() + '_PROVENANCE_PASS 5 native maps / original-source20% / actual15+9 / fresh64 normal ANGLE')


if __name__ == '__main__':
    main()

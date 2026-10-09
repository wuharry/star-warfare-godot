"""Validate the delivered local comparison pages without launching a browser.

Run after build_review.py --update-gallery. This checks file bytes, JSON and
JavaScript syntax; it never edits images, engine reports or runtime resources.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
ART = ROOT / 'docs/art/original_armors_v1'
BASELINE_COMMIT = '3ed1c2911e1eea5162e30d0bab331fd41a1d29f9'
PAGES = (
    WORK / 'index.html',
    ART / 'index.html',
    ROOT / 'docs/art/atom_runtime_v1/index.html',
    ROOT / 'docs/art/pegasus_runtime_v1/index.html',
)
BROWSER_LIMITATION = ('NOT RUN: CUA rejected the file:// preview protocol. '
                      'No browser, network request or alternate-surface bypass was attempted by this validator.')


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def record(path: Path) -> dict:
    return {'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(path),
            'bytes': path.stat().st_size}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


class Scripts(HTMLParser):
    """Keep inline JSON and JavaScript separate using their actual HTML attrs."""
    def __init__(self) -> None:
        super().__init__(convert_charrefs=False)
        self.scripts = []
        self.active = None

    def handle_starttag(self, tag, attrs):
        if tag == 'script':
            self.active = {'attrs': dict(attrs), 'text': ''}

    def handle_data(self, data):
        if self.active is not None:
            self.active['text'] += data

    def handle_endtag(self, tag):
        if tag == 'script' and self.active is not None:
            self.scripts.append(self.active)
            self.active = None


def scripts(text: str) -> list[dict]:
    parser = Scripts()
    parser.feed(text)
    return parser.scripts


def embedded(text: str, identifier: str):
    matches = [row for row in scripts(text) if row['attrs'].get('id') == identifier]
    require(len(matches) == 1, f'Expected exactly one embedded JSON block: {identifier}')
    require(matches[0]['attrs'].get('type') == 'application/json',
            f'Embedded block is not JSON: {identifier}')
    return json.loads(matches[0]['text'])


def validate_javascript() -> dict:
    node = shutil.which('node')
    require(bool(node), 'Node CLI unavailable; JavaScript syntax checks were NOT RUN')
    version = subprocess.run([node, '--version'], capture_output=True, check=True).stdout.decode().strip()
    checked = []
    for path in PAGES:
        blocks = []
        for ordinal, row in enumerate(scripts(path.read_text(encoding='utf-8')), 1):
            attrs = row['attrs']
            script_type = attrs.get('type', '').lower()
            require(not attrs.get('src'), f'External script not covered by inline syntax check: {path}')
            if script_type == 'application/json':
                json.loads(row['text'])
                continue
            require(script_type in {'', 'text/javascript', 'application/javascript', 'module'},
                    f'Unsupported script type in {path}: {script_type}')
            command = [node, '--check']
            if script_type == 'module':
                command += ['--input-type=module']
            result = subprocess.run(command, input=row['text'].encode('utf-8'), capture_output=True)
            require(result.returncode == 0,
                    f'JavaScript syntax failure in {path.name}, script {ordinal}: '
                    + result.stderr.decode('utf-8', errors='replace'))
            blocks.append({'script_ordinal': ordinal, 'command': command,
                           'stdin_sha256': hashlib.sha256(row['text'].encode('utf-8')).hexdigest(),
                           'exit_code': result.returncode})
        require(bool(blocks), f'No JavaScript was checked: {path}')
        checked.append({**record(path), 'status': 'PASS', 'inline_scripts': blocks})
    return {'node_version': version, 'pages': checked,
            'limitation': 'node --check verifies syntax only; no DOM, rendering or user interaction was run.'}


def validate_embedded_data() -> dict:
    data = load(WORK / 'review_data.json')
    actual = embedded((WORK / 'index.html').read_text(encoding='utf-8'), 'review-data')
    require(actual == data, 'Aggregate embedded JSON differs from review_data.json')
    require(data.get('schema_version') == 3 and data.get('delivery_revision') == 'draft_refinement_v3',
            'Aggregate is not the current v3 comparison schema')
    require([armor['key'] for armor in data['armors']] == ['thunder', 'atom', 'pegasus'],
            'Aggregate armor mappings are missing or out of order')
    for armor in data['armors']:
        require(armor.get('ready') and armor.get('model_refinement_observed') and
                armor.get('changed_since_previous_delivery'),
                f"Refinement not ready or no required shape change: {armor['key']}")
        require(armor['comparison_order'] == ['original', 'before', 'after'],
                f"Incorrect three-stage comparison order: {armor['key']}")
        require('3ed1c291' in armor['stage_labels']['before']['title'], 'Incorrect baseline label')
        require(armor['baseline']['source_commit'] == BASELINE_COMMIT, 'Incorrect baseline commit')
        require(len(armor['captures']) == 15 and all(
            row.get('original') and row.get('before') and row.get('after')
            for row in armor['captures'].values()), f"Missing three-stage views: {armor['key']}")
    require(data.get('browser_interaction') == 'NOT RUN', 'Browser state must remain NOT RUN')
    return {'page': record(WORK / 'index.html'), 'data': record(WORK / 'review_data.json'),
            'three_stage_design_ids': ['C-07', 'C-08', 'C-09']}


def validate_resources() -> dict:
    resources = []

    def visit(value):
        if isinstance(value, dict):
            if 'path' in value and 'sha256' in value:
                resources.append(value)
            for child in value.values():
                visit(child)
        elif isinstance(value, list):
            for child in value:
                visit(child)

    visit(load(WORK / 'review_data.json'))
    require(bool(resources), 'No local resource SHA records were found')
    unique = set()
    for row in resources:
        require(isinstance(row['path'], str) and '://' not in row['path'], 'Nonlocal resource path')
        path = (WORK / row['path']).resolve()
        require(path.is_relative_to(ROOT), f'Resource escapes the repository: {path}')
        require(path.is_file(), f'Missing resource: {path}')
        require(re.fullmatch(r'[0-9a-f]{64}', row['sha256']) is not None,
                f'Invalid SHA256: {path}')
        require(sha(path) == row['sha256'], f'Stale SHA256: {path}')
        if 'bytes' in row:
            require(path.stat().st_size == row['bytes'], f'Stale byte count: {path}')
        unique.add(path)
    return {'resource_records_verified': len(resources), 'unique_local_files_verified': len(unique),
            'scope': 'Every recursive path/SHA record in review_data.json, including the frozen before images.'}


def validate_delivery_evidence() -> dict:
    """Check the manifests' nested local evidence and every current QA image."""
    deliveries = [
        ('thunder', 'thunder_draft_v3', 'assets/armors/thunder/thunder.scn', 45),
        ('atom', 'atom_runtime_v1', 'assets/armors/atom_v1/atom.scn', 64),
        ('pegasus', 'pegasus_runtime_v1', 'assets/armors/pegasus_v1/pegasus.scn', 64),
    ]
    results = []
    verified = set()

    def inspect_records(value):
        count = 0
        if isinstance(value, dict):
            if 'path' in value and 'sha256' in value:
                path = (ROOT / value['path'].removeprefix('res://')).resolve()
                require(path.is_relative_to(ROOT) and path.is_file(), f'Missing nonlocal evidence: {path}')
                require(sha(path) == value['sha256'], f'Stale nested evidence: {path}')
                if 'bytes' in value:
                    require(path.stat().st_size == value['bytes'], f'Stale nested byte count: {path}')
                verified.add(path)
                count += 1
            count += sum(inspect_records(child) for child in value.values())
        elif isinstance(value, list):
            count += sum(inspect_records(child) for child in value)
        return count

    for slug, directory, scene_path, expected_images in deliveries:
        work = ROOT / 'docs/art' / directory
        manifest_path = work / 'manifest.json'
        manifest = load(manifest_path)
        require(manifest['status'] == 'runtime_integrated_pending_user_art_review',
                f'Incorrect runtime delivery status: {slug}')
        visual_path = work / 'review/visual_review.json'
        if not visual_path.is_file():
            visual_path = work / 'visual_review.json'
        visual = load(visual_path)
        require(visual['status'] in {'VISUALLY_REVIEWED_PENDING_USER_REVIEW',
                                    'ENGINEERING_CANDIDATE_PENDING_USER_ART_REVIEW'} and
                not visual['blocking_findings'], f'Unresolved visual review: {slug}')
        scene_sha = sha(ROOT / scene_path)
        require(visual['runtime_scene']['sha256'] == scene_sha, f'Visual scene is stale: {slug}')
        require(visual['capture_summary']['sha256'] == manifest['capture_summary']['sha256'],
                f'Visual capture summary is stale: {slug}')
        images = visual['images']
        require(len(images) == expected_images and all(row.get('visually_inspected') for row in images),
                f'Incomplete actual image review: {slug}')
        require({(row['path'], row['sha256']) for row in images} ==
                {(row['path'], row['sha256']) for row in manifest['captures']},
                f'Manifest and reviewed capture files differ: {slug}')
        for name, test in manifest['tests'].items():
            require(test['status'] == 'PASS' and load(ROOT / test['file']['path'])['status'] == 'PASS',
                    f'Actual engineering report failed: {slug}/{name}')
        records = inspect_records(manifest) + inspect_records(visual)
        results.append({'armor': slug, 'manifest': record(manifest_path),
                        'visual_review': record(visual_path), 'actual_images_inspected': expected_images,
                        'engineering_reports_passed': len(manifest['tests']),
                        'nested_resource_records_verified': records})
    return {'deliveries': results, 'unique_local_files_verified': len(verified),
            'scope': 'Nested manifest and current visual-review path/SHA/byte records; all 173 actual capture images and engineering report statuses.'}


def validate_catalog() -> dict:
    current = embedded((ART / 'index.html').read_text(encoding='utf-8'), 'catalog')
    command = ['git', 'show', BASELINE_COMMIT + ':docs/art/original_armors_v1/index.html']
    result = subprocess.run(command, cwd=ROOT, capture_output=True)
    require(result.returncode == 0, 'Could not read the pinned 3ed1c291 gallery from Git')
    baseline = embedded(result.stdout.decode('utf-8'), 'catalog')
    require(len(current) == 46 and len({r['design_id'] for r in current}) == 46,
            'Gallery rows are missing or duplicated')
    changed_ids = {'C-07', 'C-08', 'C-09'}
    untouched = [row for row in current if row['design_id'] not in changed_ids]
    frozen = [row for row in baseline if row['design_id'] not in changed_ids]
    require(len(untouched) == 43 and untouched == frozen,
            'One or more of the other 43 gallery rows differs from 3ed1c291')
    data = load(WORK / 'review_data.json')
    mapping = [('C-07', 'thunder', 'c07_redline.json'), ('C-08', 'atom', 'c08_prism.json'),
               ('C-09', 'pegasus', 'c09_bulwark.json')]
    for design_id, slug, filename in mapping:
        metadata = load(ART / filename)
        catalog_row = next(row for row in current if row['design_id'] == design_id)
        original_row = next(row for row in baseline if row['design_id'] == design_id)
        without_delivery = lambda row: {key: value for key, value in row.items()
                                        if key != 'original_based_runtime'}
        require(without_delivery(catalog_row) == without_delivery(original_row),
                f'Selected art, user review or other non-delivery catalog fields changed: {design_id}')
        old_metadata = subprocess.run(
            ['git', 'show', BASELINE_COMMIT + ':docs/art/original_armors_v1/' + filename],
            cwd=ROOT, capture_output=True, check=True)
        require(without_delivery(metadata) == without_delivery(json.loads(old_metadata.stdout.decode('utf-8'))),
                f'Non-delivery metadata changed: {design_id}')
        delivery = metadata['original_based_runtime']
        require(catalog_row['original_based_runtime'] == delivery,
                f'Metadata / CATALOG delivery mismatch: {design_id}')
        require(delivery.get('revision') == 'draft_refinement_v3', f'Old delivery revision: {design_id}')
        armor = next(row for row in data['armors'] if row['key'] == slug)
        require(delivery['scene_sha256'] == armor['scene']['sha256'], f'Scene SHA mismatch: {design_id}')
        require(delivery['manifest_sha256'] == armor['sources'][0]['sha256'],
                f'Manifest SHA mismatch: {design_id}')
        history_key = ('previous_original_based_runtime' if slug == 'thunder' else
                       'previous_draft_refinement')
        require(delivery[history_key]['snapshot_sha256'] == armor['baseline']['snapshot']['sha256'],
                f'Historical snapshot SHA mismatch: {design_id}')
        require((ART / delivery['comparison_page'].split('#')[0]).resolve() == WORK / 'index.html',
                f'Incorrect comparison page: {design_id}')
    return {'metadata_catalog_design_ids': sorted(changed_ids), 'unrelated_rows_deep_equal': 43,
            'selected_art_user_review_and_other_metadata_unchanged': sorted(changed_ids),
            'baseline_commit': BASELINE_COMMIT,
            'baseline_git_command': command, 'catalog_rows': len(current)}


def validate_page_report() -> dict:
    path = WORK / 'page_validate.json'
    report = load(path)
    require(report.get('status') == 'PASS_STATIC_BROWSER_NOT_RUN', 'Page generation report is not ready')
    for key, filename in [('page', 'index.html'), ('data', 'review_data.json')]:
        bound = report[key]
        actual = WORK / filename
        require((WORK / bound['path']).resolve() == actual, f'Wrong {key} report path')
        require(bound['sha256'] == sha(actual) and bound['bytes'] == actual.stat().st_size,
                f'page_validate.json has stale {key} bytes / SHA')
    require(report.get('browser_interaction') == 'NOT RUN', 'False browser acceptance in page report')
    require(report.get('art_acceptance') == 'NOT RUN', 'Static report must not certify user art acceptance')
    require(report.get('gallery', {}).get('updated_catalog_rows') == ['C-07', 'C-08', 'C-09'],
            'Page report does not record C07/C08/C09-only publication')
    return {'generation_report': record(path), 'page_and_data_sha_fresh': True}


def main() -> None:
    checks = {}
    for name, check in [('javascript_syntax', validate_javascript),
                        ('aggregate_embedded_data', validate_embedded_data),
                        ('local_resource_sha', validate_resources),
                        ('delivery_manifest_and_visual_evidence', validate_delivery_evidence),
                        ('metadata_catalog_consistency', validate_catalog),
                        ('page_generation_report', validate_page_report)]:
        try:
            checks[name] = {'status': 'PASS', **check()}
        except (ValueError, KeyError, OSError, StopIteration, subprocess.SubprocessError) as error:
            checks[name] = {'status': 'FAIL', 'error': str(error) or type(error).__name__}
    passed = all(row['status'] == 'PASS' for row in checks.values())
    report = {'status': 'PASS_STATIC_BROWSER_NOT_RUN' if passed else 'FAIL_STATIC_BROWSER_NOT_RUN',
              'executed_at_utc': datetime.now(timezone.utc).isoformat(),
              'validator': record(Path(__file__).resolve()), 'checks': checks,
              'browser_interaction': 'NOT RUN', 'browser_limitation': BROWSER_LIMITATION,
              'art_acceptance': 'NOT RUN', 'mobile_performance': 'NOT RUN'}
    (WORK / 'static_validation.json').write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(report, ensure_ascii=False))
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()

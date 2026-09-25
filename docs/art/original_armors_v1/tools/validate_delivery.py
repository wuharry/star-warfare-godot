"""Validate the portable art delivery without modifying artwork or metadata.

Run from any directory: python <this-file> [--report test_output/art_delivery.json]
Only Python's standard library is required. Exit 0 means artifact consistency,
not user art approval, visual correctness, runtime integration or legal clearance.
Absolute generated_filename values are historical provenance; they are not opened.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import struct
import sys
import zlib

ART = Path(__file__).resolve().parents[1]
ROOT = ART.parents[2]
REVIEWED = 'visually_reviewed_pending_user_selection'
PRODUCTION_REVIEWED = 'generated_and_visually_checked_pending_user_review'
ARMOR_KINDS = ('concept', 'turnaround', 'construction')
ROOT_FIELDS = {
    'schema_version', 'design_id', 'runtime_id', 'working_name_zh', 'working_name_en',
    'status', 'runtime_implemented', 'proposed_role_replacement', 'lore', 'role',
    'palette', 'visual_identity', 'proposed_stats', 'proposed_abilities',
    'production_status', 'images', 'modeling_authority', 'license_status', 'generation',
}
RECORD_FIELDS = ('design_id', 'kind', 'path', 'prompt', 'reference_images',
                 'status', 'postprocessing', 'visual_review', 'generated_filename')


class CatalogParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.active = False
        self.parts = []
        self.count = 0

    def handle_starttag(self, tag, attrs):
        if tag == 'script' and dict(attrs).get('id') == 'catalog':
            self.active = True
            self.count += 1

    def handle_endtag(self, tag):
        if tag == 'script':
            self.active = False

    def handle_data(self, data):
        if self.active:
            self.parts.append(data)


def required_assets():
    return {(f'C-{i:02d}', kind): f'images/c{i:02d}_{kind}.png'
            for i in range(1, 22) for kind in ARMOR_KINDS} | {
        (f'B-{i:02d}', 'design_sheet'): f'images/b{i:02d}_design_sheet.png'
        for i in range(1, 26)}


def png_dimensions(raw):
    """Verify PNG chunk framing/CRC and image-data zlib integrity, not aesthetics."""
    if raw.startswith(b'version https://git-lfs.github.com/spec/'):
        raise ValueError('Git LFS pointer: run git lfs pull before validation')
    if not raw.startswith(b'\x89PNG\r\n\x1a\n'):
        raise ValueError('not a PNG')
    pos, dimensions, data, ended = 8, None, [], False
    while pos + 12 <= len(raw):
        size = struct.unpack('>I', raw[pos:pos + 4])[0]
        end = pos + 12 + size
        if end > len(raw):
            raise ValueError('truncated PNG chunk')
        tag, payload = raw[pos + 4:pos + 8], raw[pos + 8:pos + 8 + size]
        crc = struct.unpack('>I', raw[pos + 8 + size:end])[0]
        if zlib.crc32(tag + payload) & 0xffffffff != crc:
            raise ValueError(f'PNG CRC mismatch: {tag!r}')
        if tag == b'IHDR':
            if pos != 8 or size != 13:
                raise ValueError('invalid PNG header')
            dimensions = struct.unpack('>II', payload[:8])
        elif tag == b'IDAT':
            data.append(payload)
        elif tag == b'IEND':
            ended = True
            if size or end != len(raw):
                raise ValueError('invalid PNG end')
            break
        pos = end
    if not dimensions or not ended or not data:
        raise ValueError('incomplete PNG')
    inflater = zlib.decompressobj()
    inflater.decompress(b''.join(data))
    inflater.flush()
    if not inflater.eof:
        raise ValueError('incomplete PNG compressed data')
    return list(dimensions)


class Validator:
    def __init__(self):
        self.errors = []
        self.hashes = {}
        self.expected = required_assets()
        self.designs = {}
        self.assets = {}
        self.mapping = {}

    def check(self, condition, code, location, message):
        if not condition:
            self.errors.append({'code': code, 'location': str(location), 'message': message})
        return bool(condition)

    def load(self, path):
        try:
            return json.loads(path.read_text(encoding='utf-8-sig'))
        except (OSError, ValueError) as exc:
            self.check(False, 'unreadable_json', path.relative_to(ROOT), str(exc))
            return {}

    def local(self, relative, location, base=ART):
        if not isinstance(relative, str) or not relative:
            self.check(False, 'invalid_local_path', location, 'Expected a nonempty portable relative path')
            return None
        candidate = (base / relative).resolve()
        safe = not Path(relative).is_absolute() and candidate.is_relative_to(base.resolve())
        if not self.check(safe, 'nonportable_path', location, relative):
            return None
        if not self.check(candidate.is_file(), 'missing_file', location, relative):
            return None
        return candidate

    def digest(self, path):
        if path not in self.hashes:
            self.hashes[path] = hashlib.sha256(path.read_bytes()).hexdigest()
        return self.hashes[path]

    def source_mapping(self):
        self.mapping = self.load(ART / 'runtime_mapping.json')
        m = self.mapping
        self.check(m.get('runtime_changed') is False, 'runtime_changed', 'runtime_mapping', 'Must remain false')
        armors, bags = m.get('armor_mappings', []), m.get('backpack_mappings', [])
        self.check(len(armors) == 21 and len(bags) == 25, 'mapping_count', 'runtime_mapping', 'Expected 21 armor and 25 bag mappings')
        self.check([x.get('legacy_visual_id') for x in armors] == list(range(21)), 'armor_ids', 'runtime_mapping', 'Expected unique ordered armor IDs 0–20')
        self.check([x.get('legacy_item_id') for x in bags] == list(range(25)), 'bag_ids', 'runtime_mapping', 'Expected unique ordered bag IDs 0–24')
        self.check(m.get('callofmini', {}).get('legacy_ids') == list(range(21, 29)), 'com_ids', 'runtime_mapping', 'CoM IDs 21–28 must remain unchanged')
        catalog = (ROOT / 'scripts/core/armor_catalog.gd').read_text(encoding='utf-8')
        source = (ROOT / 'scripts/core/recovered_game_data.gd').read_text(encoding='utf-8')
        names = ast.literal_eval(re.search(r'const SET_NAMES\s*:?=\s*(\[.*?\n\])', catalog, re.S).group(1))
        rows = ast.literal_eval(re.search(r'const ARMOR_ROWS\s*:?=\s*(\[.*?\n\])', source, re.S).group(1))
        for i, entry in enumerate(armors):
            loc = entry.get('design_id')
            self.check(loc == f'C-{i + 1:02d}' and entry.get('legacy_set_name') == names[i], 'armor_name', loc, 'Design or game name differs from ArmorCatalog')
            for j, key in enumerate(('head', 'body', 'arms', 'legs')):
                part = entry.get('parts', {}).get(key, {})
                row = rows[i * 4 + j]
                expected = (f'armor_{key}_{i:02d}', i * 4 + j, row[0], row[1], j)
                actual = tuple(part.get(k) for k in ('item_key', 'source_row', 'source_name', 'source_authored_type', 'runtime_part'))
                self.check(actual == expected, 'armor_part', f'{loc}/{key}', f'Expected source row {i * 4 + j}, item armor_{key}_{i:02d}')
        for i, entry in enumerate(bags):
            loc, row = entry.get('design_id'), rows[84 + i]
            expected = (f'B-{i + 1:02d}', f'armor_bag_{i:02d}', 84 + i, row[0], row[13], 'fly_bag')
            actual = tuple(entry.get(k) for k in ('design_id', 'item_key', 'source_row', 'legacy_name', 'current_bag_slots', 'attachment_bone'))
            self.check(actual == expected, 'bag_source', loc, f'Bag mapping differs from ARMOR_ROWS[{84 + i}]')
        for entry in armors + bags:
            did = entry.get('design_id')
            path = self.local(entry.get('data_file'), f'{did}/data_file')
            if path:
                d = self.load(path)
                self.check(d.get('design_id') == did, 'design_id', path.name, str(did))
                self.check(did not in self.designs, 'duplicate_design', did, 'Duplicate mapping')
                self.designs[did] = d
                self.design(d, entry)
        declared = {e.get('data_file') for e in armors + bags}
        actual = {p.name for pattern in ('c[0-9][0-9]_*.json', 'b[0-9][0-9]_*.json') for p in ART.glob(pattern)}
        self.check(declared == actual and len(actual) == 46, 'design_files', 'art root', 'Exactly the 46 mapped design JSON files are required')
        for evidence in m.get('source_evidence', []):
            path = self.local(evidence.get('path'), 'runtime source evidence', ROOT)
            if path and evidence.get('sha256'):
                normalization = evidence.get('hash_normalization', 'raw')
                self.check(normalization in ('raw', 'lf'), 'source_hash_format', evidence['path'], 'Unknown source hash normalization')
                digest = hashlib.sha256(path.read_bytes().replace(b'\r\n', b'\n')).hexdigest() if normalization == 'lf' else self.digest(path)
                self.check(digest == evidence['sha256'], 'source_hash', evidence['path'], 'Game source changed after mapping audit')

    def design(self, d, mapping):
        did = d.get('design_id', '?')
        self.check(ROOT_FIELDS.issubset(d), 'design_schema', did, f'Missing C01 root fields: {sorted(ROOT_FIELDS - set(d))}')
        self.check(d.get('proposal_only') is True and d.get('runtime_implemented') is False and d.get('runtime_id') is None,
                   'proposal_boundary', did, 'Must remain proposal_only=true, runtime_implemented=false, runtime_id=null')
        self.check(d.get('production_status', {}).get('abilities') == 'proposal_only', 'ability_status', did, 'Abilities are proposals')
        self.check(str(d.get('proposed_stats', {}).get('status', '')).startswith('proposal_'), 'stats_status', did, 'Stats must remain explicitly proposed, not implemented')
        self.check(all(a.get('implemented') is False for a in d.get('proposed_abilities', [])), 'implemented_ability', did, 'No proposed ability may claim implementation')
        self.check(d.get('proposed_role_replacement', {}).get('legacy_visual_id') == mapping.get('legacy_visual_id'), 'replacement_target', did, 'Design and mapping disagree')
        self.check(d.get('status') == 'concept_ready_for_user_review', 'design_not_ready', did, 'All required sheets must be reviewed before delivery')
        kinds = ARMOR_KINDS if did.startswith('C-') else ('design_sheet',)
        if did.startswith('B-'):
            self.check(d.get('proposed_abilities') == [] and d.get('runtime_target', {}).get('inherits_armor_abilities') is False,
                       'bag_ability_dependency', did, 'Independent bags must not inherit armor abilities')
            self.check(d.get('runtime_target', {}).get('current_bag_slots') == mapping.get('current_bag_slots'), 'bag_capacity', did, 'Capacity differs from game source')
        for kind in kinds:
            path = self.expected[(did, kind)]
            self.check(d.get('images', {}).get(kind) == path, 'design_image', f'{did}/{kind}', f'Expected {path}')
            self.check(d.get('production_status', {}).get(kind) == PRODUCTION_REVIEWED, 'unreviewed_design_image', f'{did}/{kind}', 'Missing reviewed production status')

    def manifest(self):
        manifest = self.load(ART / 'manifest.json')
        self.check(manifest.get('runtime_changed') is False, 'manifest_runtime', 'manifest', 'Runtime must remain unchanged')
        scope = manifest.get('scope', {})
        self.check(all(scope.get(k) == v for k, v in {'armors': 21, 'backpacks': 25, 'expected_selected_images': 88}.items()), 'manifest_scope', 'manifest', 'Expected 21 / 25 / 88 scope')
        for asset in manifest.get('assets', []):
            key = (asset.get('design_id'), asset.get('kind'))
            self.check(key not in self.assets, 'duplicate_asset', key, 'Duplicate selected image')
            self.assets[key] = asset
        missing = sorted(set(self.expected) - set(self.assets))
        extras = sorted(set(self.assets) - set(self.expected))
        self.check(len(self.assets) == 88 and not missing and not extras, 'selected_asset_count', 'manifest', f'Expected 88; found {len(self.assets)}; missing={missing}; extra={extras}')
        for key, expected in self.expected.items():
            did, kind = key
            path = self.local(expected, f'{did}/{kind}')
            a = self.assets.get(key)
            if not a:
                self.check(False, 'missing_selected_asset', f'{did}/{kind}', expected)
                continue
            self.check(a.get('path') == expected, 'selected_path', key, expected)
            self.check(a.get('status') == REVIEWED and bool(a.get('visual_review')), 'selected_review', key, 'Selected asset must have an actual visual review')
            self.check(a.get('postprocessing') == 'none', 'postprocessing', key, 'Delivery records promise no postprocessing')
            if path:
                raw = path.read_bytes()
                try:
                    dimensions = png_dimensions(raw)
                except (ValueError, zlib.error) as exc:
                    dimensions = None
                    self.check(False, 'invalid_png', expected, str(exc))
                wanted = [1024, 1536] if kind == 'concept' else [1536, 1024]
                self.check(dimensions == wanted == a.get('dimensions'), 'image_dimensions', expected, f'Expected {wanted}; PNG={dimensions}; manifest={a.get("dimensions")}')
                self.check(self.digest(path) == a.get('sha256'), 'image_hash', expected, 'Selected PNG differs from manifest')
                self.check(len(raw) == a.get('bytes'), 'image_bytes', expected, 'File length differs from manifest')
            prompt = self.local(a.get('prompt'), f'{did}/{kind}/prompt')
            if prompt:
                self.check(self.digest(prompt) == a.get('prompt_sha256'), 'prompt_hash', prompt.name, 'Prompt differs from manifest')
            refs = a.get('reference_images', [])
            self.check(set(refs) == set(a.get('reference_sha256', {})), 'reference_hash_keys', key, 'Every actual local image input needs a hash')
            for ref in refs:
                rp = self.local(ref, f'{did}/{kind}/reference')
                if rp:
                    self.check(self.digest(rp) == a['reference_sha256'].get(ref), 'reference_hash', ref, f'{did}/{kind}: input differs from manifest')
            self.generation_record(did, kind, a)
        for ref in manifest.get('reference_assets', []):
            path = self.local(ref.get('path'), 'manifest reference asset')
            if path:
                self.check(self.digest(path) == ref.get('sha256'), 'source_reference_hash', ref['path'], 'Reference asset differs from manifest')

    def generation_record(self, did, kind, asset):
        relative = f'generation_records/{did.lower().replace("-", "")}_{kind}.json'
        path = self.local(relative, f'{did}/{kind}/portable record')
        if not path:
            return
        record = self.load(path)
        embedded = self.designs.get(did, {}).get('generation', {}).get('records', {}).get(kind, {})
        expected_record_file = f'docs/art/original_armors_v1/{relative}'
        self.check(embedded.get('record_file') == expected_record_file, 'portable_record_link', f'{did}/{kind}', expected_record_file)
        for field in RECORD_FIELDS:
            self.check(record.get(field) == asset.get(field) == embedded.get(field), 'record_mismatch', f'{did}/{kind}/{field}', 'Formal record, design JSON and manifest differ')
        for reference in record.get('textual_source_references', []):
            self.local(reference, f'{did}/{kind}/textual source')
        if did == 'C-06' and kind == 'concept':
            self.check(record.get('reference_images') == [] and len(record.get('conversation_reference_images', [])) == 2,
                       'titan_actual_inputs', did, 'Concept input was two user attachments; Titan and EVA local images were not sent')

    def gallery(self):
        parser = CatalogParser()
        parser.feed((ART / 'index.html').read_text(encoding='utf-8'))
        self.check(parser.count == 1, 'catalog_block', 'index.html', 'Expected one embedded JSON catalog')
        try:
            catalog = json.loads(''.join(parser.parts))
        except ValueError as exc:
            self.check(False, 'catalog_json', 'index.html', str(exc))
            return
        ids = [entry.get('design_id') for entry in catalog]
        self.check(len(ids) == 46 and set(ids) == set(self.designs), 'catalog_designs', 'index.html', 'Catalog must contain every mapped design once')
        mapping = {m['design_id']: m for k in ('armor_mappings', 'backpack_mappings') for m in self.mapping.get(k, [])}
        for entry in catalog:
            did = entry.get('design_id')
            d, m = self.designs.get(did, {}), mapping.get(did, {})
            self.check(entry.get('source_file') == m.get('data_file'), 'catalog_source', did, 'Data file differs from mapping')
            self.check(entry.get('legacy_id') == m.get('legacy_visual_id'), 'catalog_game_id', did, 'Game ID differs from mapping')
            for field in ('status', 'working_name_zh', 'working_name_en'):
                self.check(entry.get(field) == d.get(field), 'catalog_metadata', f'{did}/{field}', 'Catalog is stale')
            kinds = ARMOR_KINDS if str(did).startswith('C-') else ('design_sheet',)
            expected_images = {k: self.expected.get((did, k)) for k in kinds}
            self.check(entry.get('images') == expected_images, 'catalog_images', did, 'Catalog image set differs from selected delivery')
            embedded = {(a.get('design_id'), a.get('kind')): a for a in entry.get('_assets', [])}
            self.check(set(embedded) == {(did, k) for k in kinds}, 'catalog_asset_set', did, 'Catalog must include the exact selected assets')
            for key, a in embedded.items():
                for field in ('path', 'sha256', 'dimensions', 'prompt', 'prompt_sha256', 'reference_images', 'reference_sha256', 'status'):
                    self.check(a.get(field) == self.assets.get(key, {}).get(field), 'catalog_asset', f'{key}/{field}', 'Catalog asset differs from manifest')
            for ref in entry.get('legacy_refs', []) + entry.get('halo', {}).get('reference_images', []):
                self.local(ref.get('path'), f'{did}/gallery reference')

    def user_helmet_overrides(self):
        for did in ('C-14', 'C-17'):
            d = self.designs.get(did, {})
            source = d.get('source_references', {})
            override = source.get('user_helmet_direction', {})
            self.check(override.get('priority') == 'highest' and bool(override.get('instruction')), 'user_helmet_priority', did, 'Latest user original-helmet direction must override Halo helmet')
            self.check(source.get('halo', {}).get('role') == 'body_and_attachment_only_original_helmet_priority', 'halo_helmet_scope', did, 'Halo must be limited to body/attachment structure')
            self.check('helmet' not in d.get('fusion_recipe', {}).get('borrowed', {}), 'stale_borrowed_helmet', did, 'Discarded Halo helmet must not remain the active recipe')
            head = d.get('visual_identity', {}).get('head', '')
            terms = ('封閉', '中央折面', '分叉', '橘') if did == 'C-14' else ('Knight', '外翻', '帽沿', '尖冠', '短角')
            self.check(all(term in head for term in terms), 'helmet_description', did, f'Active head description must include {terms}')
            if did == 'C-14':
                self.check(bool(re.search(r'(沒有|禁止|無).*護目鏡', head)), 'closed_helmet_rule', did, 'Must explicitly prohibit goggles')
            stem = did.lower().replace('-', '')
            for kind in ARMOR_KINDS:
                relative = f'revisions/{stem}_previous_fusion/generation_records/{stem}_{kind}.json'
                path = self.local(relative, f'{did}/superseded {kind}')
                if path:
                    old = self.load(path)
                    self.check(str(old.get('status', '')).startswith('superseded_by_user_'), 'archive_status', relative, 'Previous direction must be marked superseded')
                    old_image = self.local(old.get('path'), relative)
                    self.local(old.get('prompt'), relative)
                    self.check(old.get('path') not in {a.get('path') for a in self.assets.values()}, 'archive_selected', relative, 'Superseded image cannot count toward 88 selected outputs')
                    current = self.assets.get((did, kind), {})
                    self.check(current.get('supersedes') == relative, 'helmet_revision_record', f'{did}/{kind}', 'Current image must explicitly replace the superseded helmet direction')
                    if old_image:
                        self.check(current.get('sha256') != self.digest(old_image), 'unchanged_helmet_revision', f'{did}/{kind}', 'Old helmet image cannot be relabeled as the new revision')

    def run(self):
        self.source_mapping()
        self.manifest()
        self.gallery()
        self.user_helmet_overrides()
        missing = [{'design_id': did, 'kind': kind, 'path': path}
                   for (did, kind), path in self.expected.items() if not (ART / path).is_file()]
        return {'result': 'FAIL' if self.errors else 'PASS', 'expected_designs': 46,
                'mapped_designs': len(self.designs), 'expected_selected_images': 88,
                'manifest_selected_images': len(self.assets), 'missing_pngs': missing,
                'missing_manifest_entries': [f'{did}/{kind}' for did, kind in sorted(set(self.expected) - set(self.assets))],
                'error_count': len(self.errors), 'errors': self.errors,
                'limits': 'Artifact consistency only; visual review is recorded by humans/agents. No runtime test, asset integration or legal clearance.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', help='Optional report path under repository test_output/; artwork is never written')
    args = parser.parse_args()
    report_path = None
    if args.report:
        report_path = (ROOT / args.report).resolve()
        if not report_path.is_relative_to((ROOT / 'test_output').resolve()):
            parser.error('--report must stay under the repository test_output directory')
    validator = Validator()
    try:
        report = validator.run()
    except (OSError, ValueError, KeyError, TypeError, AttributeError, IndexError) as exc:
        validator.check(False, 'validation_could_not_complete', 'delivery', f'{type(exc).__name__}: {exc}')
        report = {'result': 'FAIL', 'error_count': len(validator.errors), 'errors': validator.errors}
    if report_path:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    summary = {k: v for k, v in report.items() if k != 'errors'}
    summary['first_errors'] = report['errors'][:20]
    if report_path:
        summary['full_report'] = report_path.relative_to(ROOT).as_posix()
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if report['result'] == 'PASS' else 1


if __name__ == '__main__':
    sys.exit(main())

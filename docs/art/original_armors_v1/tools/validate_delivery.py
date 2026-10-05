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
import importlib.util
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
SOURCE_AUDIT_SHA256 = '5e40d557237172f1e3354c940f623b337fafa3e407b5dead335006431c28b17c'
APPROVED_CURRENT_SOURCES = {
    'scripts/core/game_state.gd': 'b1b36ce8073c9a47b4cc8e469b67520f2ad4066af3d65445448f31fbb53a60f0',
    'scripts/game/player.gd': '6b68ee86ffb5c407ea78e196598c6ddd7390170c69bd3619503f42769f7d3d49',
    'scripts/game/armor_visuals.gd': 'a8419a603e0e0018f359a0f830b91f994ef0e85d500bd6db359274b39186ae00',
}
HISTORICAL_MAPPING_SOURCES = {
    'scripts/core/armor_catalog.gd': '010e2f4104f14138154f1587c822bf7fce5c9ba536b70206a7b1f98187e70884',
    'scripts/core/recovered_game_data.gd': 'e7c82bcc7df0320aa316d05a8718939a5f579ad6f3aaf8e657d9b7881151b626',
    'scripts/core/game_state.gd': '5d3bbc2a1c8fba212ef8b7c3c0c395b3dae7afba85d57658321e4e1da369c1ce',
    'scripts/game/player.gd': '98aaebe3ad4d668da68c54c34758378c201ec16366e4ab5230b53852692f26fe',
    'scripts/game/armor_visuals.gd': '257cc3cb38491a2db477a43cf74cda19322ac3a952d19033032d421ce7b46e11',
}
RUNTIME_SPECS = {
    'C-01': ('viper', 'viper_runtime_v2', 'viper_v2', 'visual_id'),
    'C-02': ('fortune', 'fortune_runtime_v1', 'fortune_v1', 'game_visual_id'),
    'C-03': ('tank', 'tank_runtime_v1', 'tank_v1', 'runtime_id'),
    'C-04': ('hydra', 'hydra_runtime_v1', 'hydra_v1', 'runtime_id'),
    'C-05': ('strike', 'strike_runtime_v1', 'strike_v1', 'runtime_id'),
    'C-06': ('titan', 'titan_runtime_v1', 'titan_v1', 'runtime_id'),
}
DESIGN_REVIEW_STATES = {
    'helmet_direction_adopted': 'helmet_direction_adopted',
    'helmet_color_corrected_pending_user_review': 'helmet_color_corrected',
    'helmet_revision_pending_user_review': 'helmet_revision_pending_user_review',
}
PRODUCTION_STATES = {
    'concept_ready_for_user_review': {PRODUCTION_REVIEWED},
    'helmet_direction_adopted': {'generated_and_visually_checked_from_adopted_helmet_direction',
                                 'user_selected_concept_adopted', 'visually_checked_supporting_sheet_for_adopted_direction'},
    'helmet_color_corrected_pending_user_review': {'color_corrected_and_visually_checked_pending_user_review'},
    'helmet_revision_pending_user_review': {PRODUCTION_REVIEWED},
}
SELECTED_STATES = {
    'concept_ready_for_user_review': {REVIEWED},
    'helmet_direction_adopted': {'visually_checked_from_adopted_helmet_direction',
                                 'user_selected_concept_adopted', 'visually_checked_supporting_sheet_for_adopted_direction'},
    'helmet_color_corrected_pending_user_review': {'visually_checked_color_correction_pending_user_review'},
    'helmet_revision_pending_user_review': {REVIEWED},
}
LEGACY_CRLF_PROMPTS = {
    'prompts/c02_turnaround.txt', 'prompts/c02_construction.txt',
    *(f'prompts/c{number:02d}_{kind}.txt' for number in (3, 4) for kind in ('concept', 'turnaround', 'construction')),
}
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


def portable_runtime_proof(proof):
    # The archive SHA is mandatory in the fresh helper. A generator's original
    # absolute local path may be absent after cloning; that diagnostic boolean
    # must not invalidate otherwise identical portable artifact evidence.
    return {**proof, 'images': [
        {key: value for key, value in image.items() if key != 'native_generator_path_available'}
        for image in proof.get('images', [])
    ]}


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
        self.runtime_rows = None
        self.runtime_evidence = []
        self.prompt_hash_evidence = []
        self.source_hash_evidence = []

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

    def current_source_audit(self):
        path = ART / 'mapping_current_source_audit.json'
        audit = self.load(path)
        if not self.check(path.is_file() and self.digest(path) == SOURCE_AUDIT_SHA256,
                          'current_source_audit_hash', path.relative_to(ROOT), 'Audited sidecar changed'):
            return {}
        rows = audit.get('sources', [])
        self.check(len(rows) == 3 and {row.get('path') for row in rows} == set(APPROVED_CURRENT_SOURCES),
                   'current_source_audit_set', path.name, 'Only the three explicitly audited scripts are allowed')
        historical = {row['path']: row for row in self.mapping.get('source_evidence', [])}
        self.check(len(self.mapping.get('source_evidence', [])) == 5
                   and {relative: row.get('sha256') for relative, row in historical.items()} == HISTORICAL_MAPPING_SOURCES,
                   'historical_mapping_sources', 'runtime_mapping', 'All five historical source SHA records must remain unchanged')
        for row in rows:
            relative = row.get('path')
            source = self.local(relative, 'current source audit', ROOT)
            self.check(row.get('current_sha256') == APPROVED_CURRENT_SOURCES.get(relative)
                       and row.get('hash_normalization') == 'lf'
                       and row.get('historical_mapping_sha256') == historical.get(relative, {}).get('sha256')
                       and row.get('mapping_evidence_symbols') == historical.get(relative, {}).get('symbols'),
                       'current_source_audit_version', relative, 'Historical mapping and approved current version must both remain exact')
            if source:
                text = source.read_bytes().replace(b'\r\n', b'\n').decode('utf-8')
                for symbol, expected in row.get('audited_functions_sha256', {}).items():
                    match = re.search(rf'(?ms)^(?:static )?func {re.escape(symbol)}\([^\n]*\n.*?(?=^(?:static )?func |\Z)', text)
                    self.check(match is not None and hashlib.sha256(match.group(0).encode()).hexdigest() == expected,
                               'current_mapping_function', f'{relative}/{symbol}', 'Equipment/mapping function differs from the reviewed version')
        visuals = (ROOT / 'scripts/game/armor_visuals.gd').read_text(encoding='utf-8')
        match = re.search(r'const REWORKED_SCENES\s*:?=\s*(\{.*?\n\})', visuals, re.S)
        routes = ast.literal_eval(match.group(1)) if match else {}
        self.check({str(key): value for key, value in routes.items()} == audit.get('runtime_scene_overrides'),
                   'current_runtime_routes', 'ArmorVisuals', 'IDs0–5, existing Thunder6 and Cygni11 routes must remain exact')
        snippets = {
            'scripts/core/game_state.gd': ['not ARMOR_ITEMS.has(armor_key) or not is_armor_owned(armor_key)',
                'str(ARMOR_ITEMS[armor_key].part_key)', 'ArmorCatalogData.item_key(part, set_id)',
                'var bag_key := get_equipped_armor_key("bag")', 'clampi(int(ARMOR_ITEMS[bag_key].bag_slots), 1, LOADOUT_MAX_SLOTS)'],
            'scripts/game/player.gd': ['GameState.get_equipped_armor_key("bag")',
                'backpack_socket.bone_name = "fly_bag"', 'GameState.get_equipped_armor_key("head")',
                'GameState.get_equipped_armor_key("body")', 'GameState.get_equipped_armor_key("arms")',
                'GameState.get_equipped_armor_key("legs")', '.ensure_parts(recovered_avatar, equipped_ids)'],
            'scripts/game/armor_visuals.gd': ['_ensure_reworked_parts(avatar, skeleton, visual_ids)',
                'reworked_scene_path(visual_id)', 'existing.skin = replacement.skin', 'existing.transform = replacement.transform'],
        }
        for relative, required in snippets.items():
            text = (ROOT / relative).read_text(encoding='utf-8')
            self.check(all(fragment in text for fragment in required), 'current_equipment_mapping', relative,
                       'Reviewed catalog IDs, independent bag and original node/Skin routes are required')
        return {row['path']: row for row in rows}

    def runtime_contracts(self):
        """Read current six-armor proofs; never start an engine or rewrite them."""
        if self.runtime_rows is not None:
            return self.runtime_rows
        self.runtime_rows = {}
        shared = ROOT / 'docs/art/armor_style_unification_v1'
        combined = self.load(shared / 'validate.json')
        rows = combined.get('armors', [])
        names = {spec[0] for spec in RUNTIME_SPECS.values()}
        if not self.check(combined.get('status') == 'PASS' and len(rows) == 6
                          and {row.get('name') for row in rows} == names,
                          'current_runtime_six', 'runtime delivery', 'A historical/PENDING/partial PASS cannot certify current six armors'):
            return self.runtime_rows
        module_path = ROOT / 'tools/armor_style_unification_v1/validate.py'
        spec = importlib.util.spec_from_file_location('current_armor_runtime_contract', module_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for row in rows:
            name = row['name']
            try:
                if name == 'tank':
                    fresh = module.verify_tank_delivery(True)
                    assert portable_runtime_proof(fresh) == portable_runtime_proof(row)
                elif name in module.FIRST_INTEGRATIONS:
                    fresh = module.verify_first_integration(name)
                    assert portable_runtime_proof(fresh) == portable_runtime_proof(row)
                else:
                    folder = 'viper_runtime_v2' if name == 'viper' else 'fortune_runtime_v1'
                    asset_folder = 'viper_v2' if name == 'viper' else 'fortune_v1'
                    runtime, assets = ROOT / 'docs/art' / folder, ROOT / 'assets/armors' / asset_folder
                    images = module.verify_generation(name, runtime, assets, (shared / 'base_prompt.txt').read_text(encoding='utf-8'))
                    assert portable_runtime_proof({'images': images}) == portable_runtime_proof({'images': row['images']})
                    target = module.read(runtime / 'build/target.json')
                    if name == 'fortune':
                        scope = module.verify_fortune_refinement(runtime, target)
                        assert all(row[key] == value for key, value in scope.items())
                    else:
                        assert module.read(shared / 'before/viper/delivery/target.json')['parts'] == target['parts']
                    invariant = module.read(ROOT / row['scene_invariants'])
                    assert invariant['status'] == 'PASS' and invariant['current_scene_sha256'] == self.digest(assets / f'{name}.scn')
                for label in ['runtime', 'roundtrip', 'master', 'proportion']:
                    report = self.load(ROOT / row['reports'][label])
                    assert report['status'] == 'PASS' and not report.get('errors', report.get('failures', []))
                self.runtime_rows[name] = row
            except (AssertionError, KeyError, OSError, ValueError, TypeError) as exc:
                self.check(False, 'current_runtime_stale', name, f'Current runtime proof failed: {type(exc).__name__}: {exc}')
        return self.runtime_rows

    def implemented_visual(self, d, mapping):
        did = d['design_id']
        if not self.check(did in RUNTIME_SPECS, 'runtime_design_scope', did, 'Only the six verified visual integrations are allowed'):
            return
        name, folder, asset_folder, id_key = RUNTIME_SPECS[did]
        delivery = d.get('runtime_delivery', {})
        expected_manifest = ROOT / 'docs/art' / folder / 'manifest.json'
        manifest_path = (ART / delivery.get('manifest', '')).resolve()
        if not self.check(manifest_path == expected_manifest.resolve() and manifest_path.is_file(),
                          'runtime_manifest_path', did, 'Expected the corresponding current runtime manifest'):
            return
        manifest = self.load(manifest_path)
        ids = [d.get('runtime_id'), delivery.get('runtime_id'), manifest.get(id_key), mapping.get('legacy_visual_id')]
        self.check(all(type(value) is int for value in ids) and len(set(ids)) == 1,
                   'runtime_visual_ids', did, 'Design, delivery, manifest and unchanged game mapping IDs must all agree')
        self.check(delivery.get('status') == manifest.get('status') == 'runtime_integrated_pending_user_art_review'
                   and delivery.get('scope') == 'visual_assets_only_stats_and_abilities_remain_proposals',
                   'runtime_visual_scope', did, 'Implemented assets cannot claim implemented proposal stats/abilities or user art acceptance')
        scene_relative = f'assets/armors/{asset_folder}/{name}.scn'
        self.check(delivery.get('scene') == scene_relative, 'runtime_scene_path', did, 'Scene must match the original visual ID route')
        records = manifest.get('outputs', manifest.get('files', []))
        files = {record.get('path'): record for record in records}
        if name == 'fortune':
            files = {path: {'path': path, 'sha256': sha} for path, sha in manifest.get('asset_sha256', {}).items()}
            files.update({record['path']: record for record in manifest.get('diffuse_maps', {}).values()})
        row = self.runtime_contracts().get(name)
        if not self.check(row is not None, 'runtime_current_proof', did, 'Corresponding current six-armor proof is required'):
            return
        master_path = f'docs/art/{folder}/build/{name}_master.blend'
        required = {scene_relative, f'assets/armors/{asset_folder}/{name}.glb', master_path,
                    *(f'assets/armors/{asset_folder}/{label}_diffuse.png' for label in ('head', 'body', 'shoulder', 'hand', 'foot'))}
        self.check(required.issubset(files), 'runtime_manifest_files', did, 'Manifest must fingerprint current SCN/GLB/master and five maps')
        for relative in sorted(required):
            path = self.local(relative, f'{did}/runtime artifact', ROOT)
            record = files.get(relative, {})
            if path:
                self.check(self.digest(path) == record.get('sha256'), 'runtime_manifest_hash', relative, 'Current asset differs from latest runtime manifest')
                if 'bytes' in record:
                    self.check(path.stat().st_size == record['bytes'], 'runtime_manifest_bytes', relative, 'Current runtime file length differs')
        master = self.load(ROOT / row['reports']['master'])
        runtime_test = self.load(ROOT / row['reports']['runtime'])
        source_path, target_path = ROOT / f'docs/art/{folder}/build/source.json', ROOT / f'docs/art/{folder}/build/target.json'
        self.check(master.get('source_sha256') == self.digest(source_path)
                   and master.get('target_sha256') == runtime_test.get('target_sha256') == self.digest(target_path)
                   and master.get('master_sha256') == self.digest(ROOT / master_path)
                   and runtime_test.get('runtime_scene_sha256') == self.digest(ROOT / scene_relative),
                   'runtime_source_sha', did, 'Fresh source/target/master/scene SHA must agree with actual files')
        for image in row['images']:
            relative = f'assets/armors/{asset_folder}/{image["label"]}_diffuse.png'
            self.check(files.get(relative, {}).get('sha256') == image['canonical_sha256'],
                       'runtime_native_selected', relative, 'Latest manifest and verified selected native atlas differ')
        for image in row['captures']:
            path = ROOT / f'docs/art/armor_style_unification_v1/after/{name}/review/{image["view"]}.png'
            self.check(self.digest(path) == image['sha256'], 'runtime_shared_capture', did, 'Current comparison capture changed')
        self.runtime_evidence.append({'design_id': did, 'runtime_id': ids[0],
            'manifest': manifest_path.relative_to(ROOT).as_posix(), 'manifest_sha256': self.digest(manifest_path),
            'source_sha256': self.digest(source_path), 'scene_sha256': self.digest(ROOT / scene_relative),
            'combined_current_report': 'docs/art/armor_style_unification_v1/validate.json',
            'combined_current_report_sha256': self.digest(ROOT / 'docs/art/armor_style_unification_v1/validate.json')})

    def reviewed_state(self, d, kind, status, selected=False):
        allowed = (SELECTED_STATES if selected else PRODUCTION_STATES).get(d.get('status'), set())
        if status not in allowed:
            return False
        if status == 'user_selected_concept_adopted':
            return kind == 'concept' and bool(d.get('user_review', {}).get('selected_concept'))
        if status == 'visually_checked_supporting_sheet_for_adopted_direction':
            return kind in ('turnaround', 'construction')
        return True

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
        current_audit = self.current_source_audit()
        for evidence in m.get('source_evidence', []):
            path = self.local(evidence.get('path'), 'runtime source evidence', ROOT)
            if path and evidence.get('sha256'):
                normalization = evidence.get('hash_normalization', 'raw')
                self.check(normalization in ('raw', 'lf'), 'source_hash_format', evidence['path'], 'Unknown source hash normalization')
                digest = hashlib.sha256(path.read_bytes().replace(b'\r\n', b'\n')).hexdigest() if normalization == 'lf' else self.digest(path)
                approved = current_audit.get(evidence['path'], {})
                audited_match = (normalization == 'lf' and approved.get('historical_mapping_sha256') == evidence['sha256']
                                 and digest == approved.get('current_sha256') == APPROVED_CURRENT_SOURCES.get(evidence['path']))
                self.check(digest == evidence['sha256'] or audited_match, 'source_hash', evidence['path'],
                           'Source must match the historical mapping SHA or this explicitly audited current version')
                self.source_hash_evidence.append({'path': evidence['path'], 'historical_sha256': evidence['sha256'],
                    'current_sha256': digest, 'hash_normalization': normalization,
                    'match': 'historical' if digest == evidence['sha256'] else ('audited_current' if audited_match else 'FAIL')})

    def design(self, d, mapping):
        did = d.get('design_id', '?')
        self.check(ROOT_FIELDS.issubset(d), 'design_schema', did, f'Missing C01 root fields: {sorted(ROOT_FIELDS - set(d))}')
        self.check(d.get('proposal_only') is True, 'proposal_boundary', did, 'Stats and abilities remain proposal_only=true')
        if d.get('runtime_implemented') is True:
            self.implemented_visual(d, mapping)
        else:
            self.check(d.get('runtime_implemented') is False and d.get('runtime_id') is None,
                       'proposal_boundary', did, 'Unintegrated proposals require runtime_implemented=false and runtime_id=null')
        self.check(d.get('production_status', {}).get('abilities') == 'proposal_only', 'ability_status', did, 'Abilities are proposals')
        self.check(str(d.get('proposed_stats', {}).get('status', '')).startswith('proposal_'), 'stats_status', did, 'Stats must remain explicitly proposed, not implemented')
        self.check(all(a.get('implemented') is False for a in d.get('proposed_abilities', [])), 'implemented_ability', did, 'No proposed ability may claim implementation')
        self.check(d.get('proposed_role_replacement', {}).get('legacy_visual_id') == mapping.get('legacy_visual_id'), 'replacement_target', did, 'Design and mapping disagree')
        state = d.get('status')
        self.check(state in PRODUCTION_STATES, 'design_not_ready', did, 'Expected an explicitly supported reviewed concept/revision state')
        if state in DESIGN_REVIEW_STATES:
            review = d.get('user_review', {})
            self.check(review.get('status') == DESIGN_REVIEW_STATES[state]
                       and all(isinstance(review.get(key), str) and review[key].strip()
                               for key in ('feedback', 'action', 'acceptance_basis')),
                       'design_review_evidence', did, 'Adopted/corrected/pending direction requires its actual user request and bounded acceptance basis')
            if state == 'helmet_direction_adopted':
                self.local(review.get('selected_concept', review.get('selected_reference')), f'{did}/adopted direction source')
        kinds = ARMOR_KINDS if did.startswith('C-') else ('design_sheet',)
        if did.startswith('B-'):
            self.check(d.get('proposed_abilities') == [] and d.get('runtime_target', {}).get('inherits_armor_abilities') is False,
                       'bag_ability_dependency', did, 'Independent bags must not inherit armor abilities')
            self.check(d.get('runtime_target', {}).get('current_bag_slots') == mapping.get('current_bag_slots'), 'bag_capacity', did, 'Capacity differs from game source')
        for kind in kinds:
            path = self.expected[(did, kind)]
            self.check(d.get('images', {}).get(kind) == path, 'design_image', f'{did}/{kind}', f'Expected {path}')
            self.check(self.reviewed_state(d, kind, d.get('production_status', {}).get(kind)),
                       'unreviewed_design_image', f'{did}/{kind}', 'Production status must match this explicitly reviewed direction and sheet kind')
        if 'helmet_art' in d:
            self.helmet_art(did, d['helmet_art'])

    def helmet_art(self, did, art):
        """Check an imported helmet reference separately from generated delivery sheets."""
        if not self.check(isinstance(art, dict), 'helmet_art_schema', did, 'Helmet art must be an object'):
            return
        self.check(str(did).startswith('C-') and art.get('scope') == 'helmet_only',
                   'helmet_art_scope', did, 'Helmet reference must target an armor and remain helmet_only')
        commit = art.get('source_commit')
        if art.get('reference_source') == 'user_attachment':
            generation = art.get('generation', {})
            self.check(commit is None and generation.get('tool') is None
                       and generation.get('status') == 'user_reference_not_a_new_generation',
                       'helmet_art_attachment', did, 'User references must not claim a source commit or a new generation')
        else:
            self.check(isinstance(commit, str) and re.fullmatch(r'[0-9a-fA-F]{40}', commit) is not None,
                       'helmet_art_commit', did, 'Expected a full 40-character source commit hash')
        dimensions = art.get('dimensions')
        self.check(isinstance(dimensions, list) and len(dimensions) == 2
                   and all(type(value) is int and value > 0 for value in dimensions),
                   'helmet_art_dimensions', did, 'Expected two positive pixel dimensions; JPEG dimensions are not decoded here')
        relative = art.get('path')
        path = None
        if self.check(isinstance(relative, str) and bool(relative), 'invalid_local_path',
                      f'{did}/helmet_art/path', 'Expected a nonempty portable relative path'):
            candidate = (ART / relative).resolve()
            safe = not Path(relative).is_absolute() and candidate.is_relative_to(ROOT.resolve())
            if self.check(safe, 'nonportable_path', f'{did}/helmet_art/path', relative):
                path = self.local(candidate.relative_to(ROOT.resolve()).as_posix(), f'{did}/helmet_art/path', ROOT)
        source = None
        if art.get('reference_source') != 'user_attachment' or art.get('source_repo_path') is not None:
            source = self.local(art.get('source_repo_path'), f'{did}/helmet_art/source_repo_path', ROOT)
        if path:
            self.check(self.digest(path) == art.get('sha256'), 'helmet_art_hash', did, 'Helmet reference differs from its recorded hash')
            self.check(path.stat().st_size == art.get('bytes'), 'helmet_art_bytes', did, 'Helmet reference length differs from metadata')
            if art.get('reference_source') == 'user_attachment':
                try:
                    self.check(png_dimensions(path.read_bytes()) == dimensions,
                               'helmet_art_attachment_png', did, 'User reference PNG dimensions differ from metadata')
                except (ValueError, zlib.error) as exc:
                    self.check(False, 'helmet_art_attachment_png', did, str(exc))
        if path and source:
            self.check(path == source, 'helmet_art_source_path', did, 'Gallery path and repository source path must identify the same file')
        if art.get('previous_reference'):
            self.helmet_art(did, art['previous_reference'])

    def manifest(self):
        manifest = self.load(ART / 'manifest.json')
        self.check(manifest.get('runtime_changed') is False, 'manifest_runtime', 'manifest', 'Runtime must remain unchanged')
        helmet_art = {did: d['helmet_art'] for did, d in self.designs.items() if 'helmet_art' in d}
        self.check(manifest.get('helmet_art', {}) == helmet_art, 'manifest_helmet_art', 'manifest',
                   'Helmet references must match the design metadata and stay separate from selected delivery sheets')
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
            self.check(self.reviewed_state(self.designs.get(did, {}), kind, a.get('status'), selected=True)
                       and isinstance(a.get('visual_review'), str) and bool(a['visual_review'].strip()),
                       'selected_review', key, 'Selected asset requires its supported direction status and a nonempty actual visual review')
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
                raw_sha = self.digest(prompt)
                expected_sha = a.get('prompt_sha256')
                reconstructed_sha = hashlib.sha256(prompt.read_bytes().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')).hexdigest()
                legacy_match = a.get('prompt') in LEGACY_CRLF_PROMPTS and reconstructed_sha == expected_sha
                self.check(raw_sha == expected_sha or legacy_match, 'prompt_hash', prompt.name,
                           'Prompt must match raw SHA or the exact known legacy CRLF bytes; no trimming/content changes')
                if raw_sha != expected_sha and legacy_match:
                    self.prompt_hash_evidence.append({'path': a['prompt'], 'raw_sha256': raw_sha,
                        'recorded_sha256': expected_sha, 'exact_reconstructed_crlf_sha256': reconstructed_sha,
                        'match': 'legacy_CRLF_reconstruction_only', 'content_and_trailing_whitespace_unchanged': True})
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
            review = d.get('user_review')
            self.check(entry.get('user_review') == review, 'catalog_user_review', did, 'Gallery must preserve user selection')
            self.check(entry.get('helmet_art') == d.get('helmet_art'), 'catalog_helmet_art', did,
                       'Gallery helmet reference must match the design metadata')
            if review and review.get('previous_revision'):
                before = review['previous_revision']
                self.check(set(before.get('images', {})) == set(before.get('prompts', {})), 'previous_art_pairs', did, 'Every previous image needs its actual prompt')
                for kind, relative in before.get('images', {}).items():
                    self.local(relative, f'{did}/{kind}/previous image')
                    self.local(before.get('prompts', {}).get(kind), f'{did}/{kind}/previous prompt')
                    self.check(relative != d.get('images', {}).get(kind), 'previous_art_overwritten', did, 'Previous and current art must remain separate files')
            if review and review.get('preferred_art'):
                preferred = review['preferred_art']
                for key in ('path', 'prompt', 'provenance'):
                    path = (ART / preferred[key]).resolve()
                    valid = path.is_relative_to(ROOT.resolve()) and path.is_file()
                    self.check(valid, 'preferred_art_source', f'{did}/{key}', 'Selected historical reference must exist within the repository')
                    if valid and key == 'path':
                        self.check(self.digest(path) == preferred.get('sha256'), 'preferred_art_hash', did, 'Selected historical artwork changed')
                preview = (ART / review.get('runtime_preview', '')).resolve()
                self.check(preview.is_relative_to(ROOT.resolve()) and preview.is_file(), 'review_runtime_preview', did, 'Runtime comparison link is missing')
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
                'runtime_evidence': self.runtime_evidence, 'source_hash_evidence': self.source_hash_evidence,
                'legacy_prompt_hash_evidence': self.prompt_hash_evidence,
                'mapping_current_source_audit': 'docs/art/original_armors_v1/mapping_current_source_audit.json',
                'mapping_current_source_audit_sha256': SOURCE_AUDIT_SHA256,
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

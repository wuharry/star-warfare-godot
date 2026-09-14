"""Extract paired Thunder meshes/materials from a locally supplied SW2 OBB.

Read-only with respect to the input archive and game assets. Diagnostics are
written beneath --output (test_output/thunder_v4_source_audit by default).
Requires the existing UnityPy package; never downloads or installs anything.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path
import zipfile

import UnityPy
from UnityPy.helpers.MeshHelper import MeshHandler

ROOT = Path(__file__).resolve().parents[2]


def open_obb(path: Path) -> zipfile.ZipFile:
    archive = zipfile.ZipFile(path)
    if any(name.startswith('assets/bin/Data/') for name in archive.namelist()):
        return archive
    member = next((name for name in archive.namelist() if name.endswith('.obb')), None)
    if member is None:
        raise ValueError(f'{path.name} contains no Unity game data or OBB. An Uptodown downloader APK is not the game APK.')
    return zipfile.ZipFile(io.BytesIO(archive.read(member)))


def extract_dependencies(archive: zipfile.ZipFile, output: Path):
    raw = output / 'raw'
    raw.mkdir(parents=True, exist_ok=True)
    material_guids = []
    candidates = []
    for info in archive.infolist():
        if info.is_dir() or info.filename.endswith('.resource'):
            continue
        data = archive.read(info.filename)
        if b'Avatar06' in data:
            name = Path(info.filename).name
            (raw / name).write_bytes(data)
            candidates.append({'file': name, 'sha256': hashlib.sha256(data).hexdigest()})
            if len(data) < 10000:
                material_guids.append(name.encode())
    for info in archive.infolist():
        if info.is_dir() or info.filename.endswith('.resource'):
            continue
        data = archive.read(info.filename)
        if any(guid in data for guid in material_guids):
            (raw / Path(info.filename).name).write_bytes(data)
    members = set(archive.namelist())
    for _ in range(8):
        env = UnityPy.load(str(raw))
        missing = set()
        for file in env.assets:
            for external in file.externals:
                name = Path(external.path).name
                if not (raw / name).exists() and 'assets/bin/Data/' + name in members:
                    missing.add(name)
        if not missing:
            return env, candidates
        for name in missing:
            (raw / name).write_bytes(archive.read('assets/bin/Data/' + name))
    raise RuntimeError('Unity dependency resolution did not converge')


def vector(v):
    return [v.x, v.y, v.z]


def quaternion(q):
    return [q.x, q.y, q.z, q.w]


def unity_position(v):
    return [v[0], v[2], -v[1]]


def game_position(v):
    return [-v[0], v[2], v[1]]


def export_renderers(env, output: Path):
    extracted = output / 'extracted'
    extracted.mkdir(exist_ok=True)
    report = []
    for obj in env.objects:
        if obj.type.name != 'SkinnedMeshRenderer':
            continue
        renderer = obj.read()
        mesh = renderer.m_Mesh.read()
        handler = MeshHandler(mesh)
        handler.process()
        modern = 'Material #' in renderer.m_Materials[0].read().m_Name
        version = 'modern' if modern else 'legacy'
        materials = []
        for pointer in renderer.m_Materials:
            material = pointer.read()
            textures = {}
            for key, value in material.m_SavedProperties.m_TexEnvs:
                if not value.m_Texture.path_id or value.m_Texture.type.name != 'Texture2D':
                    continue
                texture = value.m_Texture.read()
                destination = extracted / (texture.m_Name + '.png')
                if not destination.exists():
                    texture.image.save(destination)
                textures[key] = {
                    'name': texture.m_Name, 'path': destination.name,
                    'size': [texture.m_Width, texture.m_Height],
                    'scale': [value.m_Scale.x, value.m_Scale.y],
                    'offset': [value.m_Offset.x, value.m_Offset.y],
                }
            materials.append({
                'name': material.m_Name, 'textures': textures,
                'floats': list(material.m_SavedProperties.m_Floats),
                'colors': [(key, [value.r, value.g, value.b, value.a]) for key, value in material.m_SavedProperties.m_Colors],
            })
        transforms = []
        for item in obj.assets_file.objects.values():
            if item.type.name != 'Transform':
                continue
            transform = item.read()
            transforms.append({
                'id': item.path_id, 'name': transform.m_GameObject.read().m_Name,
                'parent': transform.m_Father.path_id, 'position': vector(transform.m_LocalPosition),
                'rotation': quaternion(transform.m_LocalRotation), 'scale': vector(transform.m_LocalScale),
            })
        bone_names = [pointer.read().m_GameObject.read().m_Name for pointer in renderer.m_Bones]
        triangles = handler.get_triangles()
        data = {
            'name': mesh.m_Name, 'version': version,
            'renderer_file': obj.assets_file.name, 'mesh_file': renderer.m_Mesh.deref().assets_file.name,
            'positions_raw': handler.m_Vertices,
            'positions': [unity_position(v) for v in handler.m_Vertices],
            'normals': [unity_position(v) for v in handler.m_Normals],
            'positions_game': [game_position(v) for v in handler.m_Vertices],
            'normals_game': [game_position(v) for v in handler.m_Normals],
            'uv': handler.m_UV0, 'submeshes': triangles, 'bone_names': bone_names,
            'bone_indices': handler.m_BoneIndices, 'bone_weights': handler.m_BoneWeights,
            'bind_poses_raw': [[[getattr(matrix, f'e{row}{col}') for col in range(4)] for row in range(4)] for matrix in mesh.m_BindPose],
            'transforms': transforms, 'materials': materials,
        }
        name = version + '_' + mesh.m_Name
        (extracted / (name + '.json')).write_text(json.dumps(data))
        lines = ['mtllib ' + name + '.mtl', 'o ' + name]
        lines += ['v ' + ' '.join(str(x) for x in v) for v in data['positions']]
        lines += ['vt ' + ' '.join(str(x) for x in v[:2]) for v in data['uv']]
        lines += ['vn ' + ' '.join(str(x) for x in v) for v in data['normals']]
        for index, submesh in enumerate(triangles):
            lines.append('usemtl mat_' + str(index))
            for triangle in submesh:
                lines.append('f ' + ' '.join(f'{i + 1}/{i + 1}/{i + 1}' for i in triangle))
        (extracted / (name + '.obj')).write_text('\n'.join(lines))
        mtl = []
        for index, material in enumerate(materials):
            mtl += ['newmtl mat_' + str(index), 'Kd 1 1 1', 'map_Kd ' + material['textures']['_RGBA']['path']]
        (extracted / (name + '.mtl')).write_text('\n'.join(mtl))
        report.append({
            'name': name, 'vertices': len(handler.m_Vertices), 'triangles': [len(submesh) for submesh in triangles],
            'renderer_file': obj.assets_file.name, 'mesh_file': data['mesh_file'],
            'bones': bone_names, 'materials': materials,
        })
    (extracted / 'report.json').write_text(json.dumps(report, indent=2))
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True, help='Existing local .obb, .zip containing an OBB, or .xapk')
    parser.add_argument('--output', type=Path, default=ROOT / 'test_output/thunder_v4_source_audit')
    arguments = parser.parse_args()
    output = arguments.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    (output / '.gdignore').write_text('')
    archive = open_obb(arguments.source)
    env, candidates = extract_dependencies(archive, output)
    report = export_renderers(env, output)
    provenance = {'source': str(arguments.source.resolve()), 'source_sha256': hashlib.sha256(arguments.source.read_bytes()).hexdigest(), 'material_candidates': candidates}
    (output / 'provenance.json').write_text(json.dumps(provenance, indent=2))
    for item in report:
        print(item['name'], 'vertices=' + str(item['vertices']), 'triangles=' + str(sum(item['triangles'])))
    print('SW2_THUNDER_SOURCE_AUDIT_PASS')


if __name__ == '__main__':
    main()

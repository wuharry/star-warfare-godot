"""Bake exact region masks from the reshaped head; these are not diffuse art."""
import json
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / 'docs/art/cygni_runtime_v2'


def main():
    bpy.ops.wm.open_mainfile(filepath=str(WORK / 'CH_Cygni_master.blend'))
    ob = bpy.data.objects['ArmorHead_11']
    mesh = ob.data
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 1
    scene.render.bake.margin = 4
    mesh.uv_layers.active = mesh.uv_layers['TargetUV']
    mesh.uv_layers.active.active_render = True
    mat = bpy.data.materials.new('Cygni_head_region_mask')
    nt = mat.node_tree
    nt.nodes.clear()
    output = nt.nodes.new('ShaderNodeOutputMaterial')
    emission = nt.nodes.new('ShaderNodeEmission')
    nt.links.new(emission.outputs[0], output.inputs[0])
    pos = nt.nodes.new('ShaderNodeNewGeometry')
    xyz = nt.nodes.new('ShaderNodeSeparateXYZ')
    nt.links.new(pos.outputs['Position'], xyz.inputs[0])

    def math_node(operation, a, b=None):
        node = nt.nodes.new('ShaderNodeMath')
        node.operation = operation
        for i, value in enumerate([a] if b is None else [a, b]):
            if isinstance(value, (int, float)):
                node.inputs[i].default_value = value
            else:
                nt.links.new(value, node.inputs[i])
        return node.outputs[0]

    x = math_node('ABSOLUTE', xyz.outputs['X'])
    height = xyz.outputs['Z']  # Authoring frame is Z-up, front -Y.
    front = math_node('LESS_THAN', xyz.outputs['Y'], -.22)
    top = math_node('SUBTRACT', 1.735, math_node('MULTIPLY', x, .15))
    bottom = math_node('ADD', 1.595, math_node('MULTIPLY', x, .20))
    band = math_node('MULTIPLY', math_node('GREATER_THAN', height, bottom), math_node('LESS_THAN', height, top))
    band = math_node('MULTIPLY', band, math_node('LESS_THAN', x, .22))
    stem = math_node('MULTIPLY', math_node('LESS_THAN', x, .057), math_node('GREATER_THAN', height, 1.42))
    stem = math_node('MULTIPLY', stem, math_node('LESS_THAN', height, 1.64))
    gold = math_node('MULTIPLY', front, math_node('MAXIMUM', band, stem))
    neck = math_node('MULTIPLY', math_node('LESS_THAN', height, 1.40), math_node('GREATER_THAN', xyz.outputs['Y'], -.13))
    mix = nt.nodes.new('ShaderNodeMixRGB')
    mix.inputs[1].default_value = (.70, .70, .70, 1)
    mix.inputs[2].default_value = (.65, .30, .025, 1)
    nt.links.new(gold, mix.inputs[0])
    joint = nt.nodes.new('ShaderNodeMixRGB')
    nt.links.new(mix.outputs[0], joint.inputs[1])
    joint.inputs[2].default_value = (.012, .024, .017, 1)
    nt.links.new(neck, joint.inputs[0])
    nt.links.new(joint.outputs[0], emission.inputs[0])
    mesh.materials.clear()
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.material_index = 0
    image = bpy.data.images.new('Cygni_head_regions', 512, 512, alpha=False)
    image.generated_color = (.018, .026, .021, 1)
    image.filepath_raw = str(WORK / 'build/head_material_regions.png')
    image.file_format = 'PNG'
    node = nt.nodes.new('ShaderNodeTexImage')
    node.image = image
    nt.nodes.active = node
    bpy.ops.object.select_all(action='DESELECT')
    ob.hide_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.bake(type='EMIT', use_clear=False)
    image.save()
    # Save a review-only copy, never the editable master.
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'test_output/cygni_runtime_v2/head_region_review.blend'))
    (WORK / 'build/head_region_contract.json').write_text(json.dumps({
        'type': 'technical material-region bake, NOT generated diffuse',
        'coordinates': 'Blender Z-up/-Y-front; copied exact TargetUV from OriginalUV',
        'gold': 'eye band with narrow central stem; mirrored surfaces reuse the same pixels',
        'white': 'continuous shell and inward-swept cheeks; source copper accents are secondary painting reference',
        'dark': 'lower rear neck joint',
        'inferred': 'T boundaries adapted to the approved perspective concept at game scale',
    }, indent=2) + '\n')
    print('CYGNI_HEAD_REGION_BAKE_PASS')


if __name__ == '__main__':
    main()

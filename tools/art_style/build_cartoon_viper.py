"""Author the starter suit in Blender, bake new UV textures, retain the game rig.

Blender --background --python-exit-code 1 --python tools/art_style/build_cartoon_viper.py
godot --headless --path . --script tools/art_style/compile_cartoon_viper.gd
"""
from __future__ import annotations

import colorsys
import hashlib
import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets/armors/cartoon_viper"
WORK = ROOT / "test_output/cartoon_viper"
NATIVE = ROOT / "docs/art/armor_rework/cartoon_viper.blend"
ASSETS.mkdir(parents=True, exist_ok=True)
WORK.mkdir(parents=True, exist_ok=True)
(WORK / ".gdignore").write_text("")

# Open the editable source. Its coordinate system and 28 named binds already
# match compile_viper.gd; the source file itself is never saved over.
bpy.ops.wm.open_mainfile(filepath=str(ROOT / "docs/art/armor_rework/viper.blend"))
rig = next(obj for obj in bpy.data.objects if obj.type == "ARMATURE")
rig.animation_data_clear()
rig.data.pose_position = "REST"
gloves = bpy.data.objects["ArmorHand_00"]
source_helmet = bpy.data.objects["ArmorHead_00"]
for obj in list(bpy.data.objects):
    if obj.type == "MESH" and obj not in (gloves, source_helmet):
        bpy.data.objects.remove(obj, do_unlink=True)
for modifier in list(gloves.modifiers):
    gloves.modifiers.remove(modifier)

PALETTE = {
    "ink": "19222f", "rubber": "30343b", "blue": "517c99",
    "blue_light": "8eb1be", "blue_dark": "2b455d", "cream": "ddd5b6",
    "purple": "70669b", "purple_light": "c1b7de", "gold": "c8aa70",
    "sole": "202631",
}

def linear(value: float) -> float:
    return value / 12.92 if value <= .04045 else ((value + .055) / 1.055) ** 2.4

materials = {}
for key, hex_color in PALETTE.items():
    mat = bpy.data.materials.new("CartoonViper_" + key)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    emit = nodes.new("ShaderNodeEmission")
    rgba = tuple(linear(int(hex_color[i:i + 2], 16) / 255) for i in (0, 2, 4)) + (1.0,)
    emit.inputs["Color"].default_value = rgba
    mat.diffuse_color = rgba
    output = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(emit.outputs[0], output.inputs["Surface"])
    materials[key] = mat

parts: dict[str, list] = {key: [] for key in ("Head", "Body", "Hand", "Foot", "Bag")}

def finish(obj, part: str, material: str, bone, smooth=True):
    obj.data.materials.clear()
    obj.data.materials.append(materials[material])
    obj.vertex_groups.clear()
    for vertex in obj.data.vertices:
        weights = bone(vertex.co) if callable(bone) else {bone: 1.0}
        total = sum(weights.values())
        for name, weight in weights.items():
            if weight <= 0:
                continue
            group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
            group.add([vertex.index], weight / total, "REPLACE")
    for face in obj.data.polygons:
        face.use_smooth = smooth
    parts[part].append(obj)
    return obj

def activate(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.hide_set(False)
    obj.hide_render = False
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

def mesh_object(name, verts, faces):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return obj

def blob(name, center, radius, part, material, bone, exponent=.8, rotation=0.0):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=16)
    obj = bpy.context.object
    obj.name = name
    cosine, sine = math.cos(rotation), math.sin(rotation)
    for vertex in obj.data.vertices:
        p = vertex.co
        x, y, z = [math.copysign(abs(p[i]) ** exponent, p[i]) * radius[i] for i in range(3)]
        vertex.co = Vector(center) + Vector((x * cosine - z * sine, y, x * sine + z * cosine))
    obj.data.update()
    return finish(obj, part, material, bone)

def plate(name, outline, depth, thickness, part, material, bone, bevel=.008):
    verts = [(x, y, depth) for x, y in outline] + [(x, y, depth + thickness) for x, y in outline]
    size = len(outline)
    faces = [tuple(range(size - 1, -1, -1)), tuple(range(size, size * 2))]
    faces += [(i, (i + 1) % size, (i + 1) % size + size, i + size) for i in range(size)]
    obj = mesh_object(name, verts, faces)
    activate(obj)
    modifier = obj.modifiers.new("Soft manufactured edge", "BEVEL")
    modifier.width = bevel
    modifier.segments = 3
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    return finish(obj, part, material, bone)

def loft(name, rows, part, material, bone):
    sides = 32
    verts = [(rx * math.cos(i * math.tau / sides), y, z + rz * math.sin(i * math.tau / sides))
             for y, rx, rz, z in rows for i in range(sides)]
    faces = []
    for row in range(len(rows) - 1):
        for i in range(sides):
            a, b = row * sides + i, row * sides + (i + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    faces += [tuple(range(sides - 1, -1, -1)), tuple(range((len(rows) - 1) * sides, len(rows) * sides))]
    return finish(mesh_object(name, verts, faces), part, material, bone)

def smoothstep(a, b, value):
    t = max(0.0, min(1.0, (value - a) / (b - a)))
    return t * t * (3 - 2 * t)

def torso_weights(point):
    lower = smoothstep(.83, 1.0, point.y)
    upper = smoothstep(.98, 1.16, point.y)
    return {"Bip01 Pelvis": 1 - lower, "Bip01 Spine": lower * (1 - upper), "Bip01 Spine1": lower * upper}

def hose(name, centers, radii, part, bones):
    vertices, faces, weight_rows = [], [], []
    steps, sides = 24, 20
    for row in range(steps + 1):
        t = row / steps
        segment = 0 if t < .5 else 1
        fraction = t * 2 - segment
        p0, p1 = Vector(centers[segment]), Vector(centers[segment + 1])
        center = p0.lerp(p1, fraction)
        axis = (p1 - p0).normalized()
        side = axis.cross(Vector((0, 0, 1))).normalized()
        front = axis.cross(side).normalized()
        radius = radii[segment] * (1 - fraction) + radii[segment + 1] * fraction
        blend = smoothstep(.30, .70, t)
        for index in range(sides):
            theta = index * math.tau / sides
            vertices.append(center + radius * (side * math.cos(theta) + front * math.sin(theta)))
            weight_rows.append({bones[0]: 1 - blend, bones[1]: blend})
    for row in range(steps):
        for index in range(sides):
            a, b = row * sides + index, row * sides + (index + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    faces += [tuple(range(sides - 1, -1, -1)), tuple(range(steps * sides, (steps + 1) * sides))]
    obj = mesh_object(name, vertices, faces)
    finish(obj, part, "rubber", bones[0])
    obj.vertex_groups.clear()
    for vertex, weights in zip(obj.data.vertices, weight_rows):
        for name, weight in weights.items():
            if weight > 0:
                group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                group.add([vertex.index], weight, "REPLACE")
    return obj

def armor_shell(name, rows, x, part, material, bone, bevel=.008):
    """Chamfered cross sections keep broad planes and a rigid outer silhouette."""
    verts, faces = [], []
    for y, width, front, back, cut in rows:
        verts += [(x + dx, y, z) for dx, z in [
            (-width + cut, front), (width - cut, front), (width, front + cut),
            (width, back - cut), (width - cut, back), (-width + cut, back),
            (-width, back - cut), (-width, front + cut)]]
    for row in range(len(rows) - 1):
        for index in range(8):
            a, b = row * 8 + index, row * 8 + (index + 1) % 8
            faces.append((a, b, b + 8, a + 8))
    faces += [tuple(range(7, -1, -1)), tuple(range((len(rows) - 1) * 8, len(rows) * 8))]
    obj = mesh_object(name, verts, faces)
    activate(obj)
    edge = obj.modifiers.new("Manufactured bevel", "BEVEL")
    edge.width, edge.segments = bevel, 2
    bpy.ops.object.modifier_apply(modifier=edge.name)
    return finish(obj, part, material, bone, smooth=False)

def paired_plate(name, side, points, depth, thickness, part, material, bone, bevel=.008):
    return plate(name, [(side * x, y) for x, y in points], depth, thickness, part, material, bone, bevel)

def detail_mesh(name, vertices, faces, part, material, bone, smooth=True):
    obj = finish(mesh_object(name, vertices, faces), part, material, bone, smooth)
    obj["anatomical_detail"] = True
    return obj

def digit(name, centers, radii, bone):
    points = [Vector(point) for point in centers]
    vertices, faces = [], []
    sides = 12
    for index, center in enumerate(points):
        tangent = (points[min(index + 1, len(points) - 1)] - points[max(0, index - 1)]).normalized()
        axis = Vector((1, 0, 0)) if abs(tangent.x) < .8 else Vector((0, 0, 1))
        lateral = (axis - tangent * axis.dot(tangent)).normalized()
        dorsal = tangent.cross(lateral).normalized()
        for step in range(sides):
            angle = step * math.tau / sides
            vertices.append(center + radii[index] * (lateral * math.cos(angle) + dorsal * math.sin(angle) * .85))
    for row in range(len(points) - 1):
        for step in range(sides):
            a, b = row * sides + step, row * sides + (step + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    faces += [tuple(range(sides - 1, -1, -1)), tuple(range((len(points) - 1) * sides, len(points) * sides))]
    return detail_mesh(name, vertices, faces, "Hand", "rubber", bone)

def articulated_glove(side, label, bone):
    for obj in [blob(label + " anatomical palm", (side * .494, .687, .016), (.059, .059, .035), "Hand", "rubber", bone, .72),
                blob(label + " flexible wrist cuff", (side * .494, .741, .017), (.055, .025, .040), "Hand", "ink", bone, .7)]:
        obj["anatomical_detail"] = True
    # Separate digits retain real gaps; do not voxel-union them into a mitten.
    for name, x, length, radius in [("index", .451, .073, .013), ("middle", .482, .084, .014),
                                  ("ring", .513, .077, .013), ("little", .542, .061, .0115)]:
        points = [(side * x, .646, .014), (side * x, .630, .014),
                  (side * x, .646 - length * .52, .021),
                  (side * x, .646 - length * .82, .037),
                  (side * x, .646 - length, .052), (side * x, .649 - length, .062)]
        digit(label + " " + name + " finger", points, [radius, radius, radius * .93, radius * .86, radius * .75, .004], bone)
        for y, z, size in [(.634, -.002, .010), (.646 - length * .52, .007, .008)]:
            pad = paired_plate(label + " " + name + " knuckle pad", side,
                [(x - size, y + .010), (x + size, y + .010), (x + size, y - .006), (x - size, y - .006)],
                z - .004, .005, "Hand", "blue_dark", bone, .003)
            pad["anatomical_detail"] = True
    digit(label + " opposing thumb", [(side * .445, .700, .012), (side * .424, .677, .015),
          (side * .414, .650, .031), (side * .421, .630, .047), (side * .426, .628, .054)],
          [.022, .021, .018, .014, .004], bone)
    back = paired_plate(label + " dorsal hand armor", side,
        [(.449, .716), (.534, .716), (.539, .674), (.527, .655), (.458, .655), (.445, .675)],
        -.025, .012, "Hand", "blue", bone, .005)
    back["anatomical_detail"] = True
    for x in (.466, .493, .520):
        mark = paired_plate(label + " dorsal flex channel", side,
            [(x - .002, .706), (x + .002, .706), (x + .002, .666), (x - .002, .666)],
            -.030, .003, "Hand", "ink", bone, .0008)
        mark["anatomical_detail"] = True

def human_boot(side, label, bone):
    def point(u, y, z):
        angle = .16
        return Vector((side * (.186 + u * math.cos(angle) - z * math.sin(angle)), y,
                       u * math.sin(angle) + z * math.cos(angle)))

    # Narrow heel, medial arch, broad metatarsals and an asymmetric rounded toe.
    outline = [(-.052, .104), (.057, .105), (.075, .068), (.070, -.020),
               (.094, -.12), (.089, -.217), (.060, -.258), (-.034, -.270),
               (-.075, -.244), (-.089, -.181), (-.067, -.087), (-.048, -.005)]
    vertices = [point(u * scale, y, z) for y, scale in [(.038, 1.0), (.053, 1.03), (.067, .98)] for u, z in outline]
    count = len(outline)
    faces = [(r * count + i, r * count + (i + 1) % count,
              (r + 1) * count + (i + 1) % count, (r + 1) * count + i) for r in range(2) for i in range(count)]
    faces += [tuple(range(count - 1, -1, -1)), tuple(range(2 * count, 3 * count))]
    detail_mesh(label + " contoured midsole", vertices, faces, "Foot", "sole", bone, False)

    # Two contact patches leave a visible arch between heel and forefoot.
    for name, polygon in [("heel", [(-.050, .10), (.055, .10), (.069, .042), (-.045, .027)]),
                          ("forefoot", [(-.065, -.10), (.083, -.10), (.084, -.215),
                                        (.055, -.256), (-.032, -.265), (-.073, -.237), (-.083, -.18)])]:
        n = len(polygon)
        verts = [point(u, y, z) for y in (.017, .043) for u, z in polygon]
        faces = [tuple(range(n - 1, -1, -1)), tuple(range(n, 2 * n))]
        faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
        detail_mesh(label + " rubber " + name, verts, faces, "Foot", "ink", bone, False)

    rows = [(-.270, .026, .076), (-.247, .071, .105), (-.19, .087, .125),
            (-.125, .083, .151), (-.055, .067, .184), (.012, .060, .211),
            (.075, .061, .175), (.104, .039, .13)]
    vertices, faces = [], []
    segments = 12
    for z, width, top in rows:
        vertices.append(point(width, .060, z))
        for index in range(segments + 1):
            theta = index * math.pi / segments
            vertices.append(point(width * math.cos(theta), .077 + (top + .012 - .077) * math.sin(theta) ** .72, z))
        vertices.append(point(-width, .060, z))
    n = segments + 3
    for row in range(len(rows) - 1):
        for index in range(n):
            a, b = row * n + index, row * n + (index + 1) % n
            faces.append((a, b, b + n, a + n))
    faces += [tuple(range(n - 1, -1, -1)), tuple(range((len(rows) - 1) * n, len(rows) * n))]
    upper = detail_mesh(label + " shaped boot upper", vertices, faces, "Foot", "rubber", bone)
    upper.data.materials.append(materials["blue"])
    for index, polygon in enumerate(upper.data.polygons):
        if index < 3 * n or index == len(faces) - 2:
            polygon.material_index = 1
        if index >= len(faces) - 2 or index % n == n - 1:
            polygon.use_smooth = False
    collar = armor_shell(label + " padded ankle collar", [(.136, .062, -.043, .098, .022),
        (.212, .070, -.043, .092, .022), (.263, .067, -.04, .083, .021)],
        0, "Foot", "rubber", bone, .01)
    for vertex in collar.data.vertices:
        vertex.co = point(vertex.co.x, vertex.co.y, vertex.co.z)
    collar.data.update()
    collar["anatomical_detail"] = True

    def instep(z, theta, lift=.003):
        for (z0, w0, h0), (z1, w1, h1) in zip(rows, rows[1:]):
            if z0 <= z <= z1:
                t = (z - z0) / (z1 - z0)
                width, top = w0 * (1 - t) + w1 * t, h0 * (1 - t) + h1 * t
                return point((width + lift) * math.cos(theta),
                    .077 + (top + .012 - .077) * math.sin(theta) ** .72 + lift, z)
        raise ValueError("Instep detail outside boot")

    # Straps follow the boot curvature instead of intersecting it as flat bars.
    for name, start, end, material in [("toe cap welt", -.231, -.223, "blue_light"),
            ("lower instep strap", -.130, -.103, "blue_dark"),
            ("upper instep strap", -.060, -.033, "blue_dark")]:
        verts = [instep(z, .08 + index * (math.pi - .16) / 16) for z in (start, end) for index in range(17)]
        faces = [(i, i + 1, i + 18, i + 17) for i in range(16)]
        detail_mesh(label + " " + name, verts, faces if side > 0 else [face[::-1] for face in faces], "Foot", material, bone, False)

    # A thin raised welt follows the actual sole perimeter, including the arch.
    verts = [point(u * scale, y, z) for y, scale in [(.054, 1.034), (.059, 1.018)] for u, z in outline]
    faces = [(i, (i + 1) % count, (i + 1) % count + count, i + count) for i in range(count)]
    detail_mesh(label + " sole welt", verts, faces if side > 0 else [face[::-1] for face in faces], "Foot", "blue_dark", bone, False)

# Preserve the authored helmet's panel boundaries and visor artwork. A native
# material remaps its broad tones; nine UV taps soften the old micro-scratches.
for modifier in list(source_helmet.modifiers):
    source_helmet.modifiers.remove(modifier)
source_image = next(node.image for node in source_helmet.data.materials[0].node_tree.nodes if node.type == "TEX_IMAGE")
source_helmet.data.uv_layers.active.name = "SourceUV"
source_helmet.data.uv_layers.new(name="BakedUV").active_render = True
source_helmet.data.uv_layers.active_index = 1
head_paint = bpy.data.materials.new("Viper authored panels in cartoon palette")
head_paint.use_nodes = True
nodes, links = head_paint.node_tree.nodes, head_paint.node_tree.links
nodes.clear()
uv = nodes.new("ShaderNodeUVMap")
uv.uv_map = "SourceUV"
average = None
for x in (-.003, 0, .003):
    for y in (-.003, 0, .003):
        offset = nodes.new("ShaderNodeVectorMath")
        offset.operation = "ADD"
        links.new(uv.outputs[0], offset.inputs[0])
        offset.inputs[1].default_value = (x, y, 0)
        texture = nodes.new("ShaderNodeTexImage")
        texture.image, texture.interpolation = source_image, "Cubic"
        links.new(offset.outputs[0], texture.inputs[0])
        scale = nodes.new("ShaderNodeVectorMath")
        scale.operation = "SCALE"
        links.new(texture.outputs[0], scale.inputs[0])
        scale.inputs[3].default_value = 1 / 9
        if average is None:
            average = scale.outputs[0]
        else:
            add = nodes.new("ShaderNodeVectorMath")
            add.operation = "ADD"
            links.new(average, add.inputs[0])
            links.new(scale.outputs[0], add.inputs[1])
            average = add.outputs[0]
value = nodes.new("ShaderNodeRGBToBW")
links.new(average, value.inputs[0])
def paint_ramp(stops):
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "EASE"
    for element in list(ramp.color_ramp.elements)[1:]:
        ramp.color_ramp.elements.remove(element)
    for index, (position, color) in enumerate(stops):
        entry = ramp.color_ramp.elements[0] if index == 0 else ramp.color_ramp.elements.new(position)
        entry.position = position
        entry.color = materials[color].diffuse_color
    links.new(value.outputs[0], ramp.inputs[0])
    return ramp.outputs[0]
blue_paint = paint_ramp([(0, "ink"), (.015, "blue_dark"), (.035, "blue_dark"),
    (.048, "blue"), (.16, "blue"), (.19, "blue_light"), (1.0, "blue_light")])
violet_paint = paint_ramp([(0, "ink"), (.025, "purple"), (1.0, "purple")])
emit, output = nodes.new("ShaderNodeEmission"), nodes.new("ShaderNodeOutputMaterial")
links.new(blue_paint, emit.inputs[0])
links.new(emit.outputs[0], output.inputs[0])
visor_paint = head_paint.copy()
visor_paint.name = "Viper violet visor without baked photographic glare"
visor_paint.node_tree.links.new(visor_paint.node_tree.nodes[violet_paint.node.name].outputs[0],
    visor_paint.node_tree.nodes[emit.name].inputs[0])
source_helmet.data.materials.clear()
source_helmet.data.materials.append(head_paint)
source_helmet.data.materials.append(visor_paint)
# Select the original violet polygon regions using their authored UV colors.
# Per-pixel hue selection wrongly turns the white painted glare blue.
source_pixels = list(source_image.pixels)
source_width, source_height = source_image.size
source_uv = source_helmet.data.uv_layers["SourceUV"].data
for polygon in source_helmet.data.polygons:
    u = sum(source_uv[index].uv.x for index in polygon.loop_indices) / len(polygon.loop_indices)
    v = sum(source_uv[index].uv.y for index in polygon.loop_indices) / len(polygon.loop_indices)
    pixel = (min(source_height - 1, int(v * source_height)) * source_width + min(source_width - 1, int(u * source_width))) * 4
    hue, saturation, brightness = colorsys.rgb_to_hsv(*source_pixels[pixel:pixel + 3])
    violet_region = .69 < hue < .92 and saturation > .15 and polygon.center.z < -.10 and 1.36 < polygon.center.y < 1.62
    visor_center = abs(polygon.center.x) < .13 and polygon.center.z < -.28 and 1.4 < polygon.center.y < 1.61
    polygon.material_index = int(violet_region or visor_center)
del source_pixels
parts["Head"].append(source_helmet)

loft("Flexible armored undersuit", [(.77, .15, .12, .01), (.84, .18, .13, .01),
     (.99, .185, .133, .015), (1.15, .22, .15, .02), (1.30, .17, .12, .03),
     (1.38, .09, .08, .045)], "Body", "rubber", torso_weights)
armor_shell("Sealed flexible neck", [(1.32, .105, -.075, .14, .025),
    (1.49, .10, -.065, .135, .025)], 0, "Body", "rubber", "Bip01 Neck", .006)
armor_shell("Torso armored chassis", [(1.02, .18, -.14, .15, .04),
    (1.26, .26, -.16, .18, .06), (1.34, .18, -.11, .14, .04)], 0, "Body", "blue_dark", "Bip01 Spine1")
for side in (-1, 1):
    paired_plate("Split pectoral armor", side, [(.012, 1.29), (.17, 1.33), (.266, 1.26),
        (.224, 1.09), (.08, 1.04), (.016, 1.11)], -.204, .065, "Body", "blue", "Bip01 Spine1", .010)
    paired_plate("Chest ivory insignia", side, [(.035, 1.263), (.15, 1.29), (.19, 1.27),
        (.046, 1.239)], -.216, .009, "Body", "cream", "Bip01 Spine1", .003)
    paired_plate("Chest vent", side, [(.15, 1.18), (.196, 1.21), (.186, 1.132),
        (.143, 1.107)], -.217, .012, "Body", "ink", "Bip01 Spine1", .003)
plate("Abdominal armor", [(-.145, 1.025), (0, 1.055), (.145, 1.025), (.11, .95),
      (0, .928), (-.11, .95)], -.159, .04, "Body", "blue", "Bip01 Spine")
armor_shell("Utility belt", [(.818, .18, -.13, .14, .035), (.88, .195, -.145, .15, .035)],
            0, "Body", "ink", "Bip01 Pelvis", .004)
plate("Belt clasp", [(-.041, .874), (.041, .874), (.047, .835), (-.047, .835)],
      -.157, .018, "Body", "blue_light", "Bip01 Pelvis", .004)
plate("Pelvic armor", [(-.12, .818), (.12, .818), (.09, .75), (0, .716), (-.09, .75)],
      -.137, .05, "Body", "blue_dark", "Bip01 Pelvis")

for side, label in [(-1, "L"), (1, "R")]:
    upper, fore, hand = [f"Bip01 {label} {part}" for part in ("UpperArm", "Forearm", "Hand")]
    thigh, calf, foot = [f"Bip01 {label} {part}" for part in ("Thigh", "Calf", "Foot")]
    hose(f"{label} continuous arm", [(side * .372, 1.313, .068), (side * .448, .963, .058),
         (side * .494, .736, .017)], [.071, .066, .057], "Body", [upper, fore])
    armor_shell(f"{label} angular shoulder", [(1.165, .10, -.07, .17, .04),
        (1.25, .151, -.11, .21, .045), (1.39, .14, -.08, .19, .045),
        (1.425, .095, -.04, .15, .035)], side * .372, "Body", "blue", upper)
    paired_plate(label + " shoulder marking", side, [(.31, 1.36), (.40, 1.36), (.40, 1.342),
        (.31, 1.342)], -.097, .008, "Body", "cream", upper, .002)
    armor_shell(label + " upper arm guard", [(1.028, .075, -.015, .125, .025),
        (1.17, .088, -.02, .14, .03)], side * .416, "Body", "blue_dark", upper)
    armor_shell(label + " forearm bracer", [(.772, .073, -.074, .09, .025),
        (.88, .094, -.095, .123, .03), (.966, .08, -.07, .11, .027)],
        side * .475, "Hand", "blue", fore, .007)
    paired_plate(label + " forearm inset", side, [(.43, .911), (.51, .911), (.515, .82),
        (.445, .802)], -.103, .015, "Hand", "blue_dark", fore, .004)
    hose(f"{label} continuous trouser", [(side * .141, .779, 0), (side * .169, .387, -.019),
         (side * .186, .137, .016)], [.089, .076, .063], "Body", [thigh, calf])
    armor_shell(label + " thigh shell", [(.473, .077, -.09, .08, .028),
        (.65, .104, -.12, .10, .032), (.745, .089, -.105, .09, .027)],
        side * .168, "Body", "blue", thigh, .008)
    paired_plate(label + " knee shield", side, [(.085, .433), (.17, .46), (.258, .433),
        (.24, .367), (.17, .341), (.104, .367)], -.135, .072, "Foot", "blue_dark", calf)
    armor_shell(label + " shin plate", [(.158, .079, -.08, .07, .025),
        (.26, .093, -.106, .08, .03), (.357, .084, -.09, .075, .025)],
        side * .186, "Foot", "blue", calf, .007)
    human_boot(side, label, foot)
    articulated_glove(side, label, hand)

bpy.data.objects.remove(gloves, do_unlink=True)

armor_shell("Compact armored backpack", [(1.0, .15, .16, .29, .035),
    (1.25, .18, .17, .32, .04), (1.31, .13, .17, .28, .03)], 0, "Bag", "blue_dark", "fly_bag")
for side in (-1, 1):
    armor_shell("Backpack side radiator", [(1.04, .04, .23, .325, .012),
        (1.24, .046, .23, .335, .012)], side * .12, "Bag", "blue", "fly_bag", .004)
    for y in (1.09, 1.14, 1.19):
        paired_plate("Backpack radiator vent", side, [(.087, y), (.152, y), (.152, y + .014),
            (.087, y + .014)], .334, .006, "Bag", "ink", "fly_bag", .002)

def seam(name, points, part, material, bone, width=.004, target=None):
    vertices, faces = [], []
    path = []
    for start, end in zip(points, points[1:]):
        for step in range(9):
            point = Vector(start).lerp(Vector(end), step / 8)
            if not path or (point - path[-1]).length > .00001:
                path.append(point)
    bpy.context.view_layer.update()
    for index, point in enumerate(path):
        tangent = path[min(index + 1, len(path) - 1)] - path[max(0, index - 1)]
        across = Vector((-tangent.y, tangent.x, 0)).normalized() * width
        for edge in (-1, 1):
            position = point + across * edge
            if target is not None:
                hit, location, normal, face_index = target.ray_cast(Vector((position.x, position.y, -2)), Vector((0, 0, 1)))
                if not hit:
                    raise ValueError("Panel detail misses " + target.name + ": " + name)
                position = location + Vector((0, 0, -.003))
            vertices.append(position)
    for index in range(len(path) - 1):
        a = index * 2
        faces.append((a, a + 1, a + 3, a + 2))
    obj = finish(mesh_object(name, vertices, faces), part, material, bone, smooth=False)
    # Front-facing flat engraving strips do not produce inflated tube outlines.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.reverse_faces(bm, faces=[face for face in bm.faces if face.normal.z > 0])
    bm.to_mesh(obj.data)
    bm.free()
    if target is not None:
        obj["surface_target"] = target.name
    return obj

def bolt(name, position, part, bone, radius=.01):
    for size, depth, material in [(radius * 1.45, 0, "ink"), (radius, -.002, "blue_light")]:
        bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=size, depth=.003,
            location=Vector(position) + Vector((0, 0, depth)))
        obj = bpy.context.object
        obj.name = name
        activate(obj)
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        finish(obj, part, material, bone, smooth=False)

for side, label in [(-1, "L"), (1, "R")]:
    upper, fore, hand = [f"Bip01 {label} {part}" for part in ("UpperArm", "Forearm", "Hand")]
    thigh, calf, foot = [f"Bip01 {label} {part}" for part in ("Thigh", "Calf", "Foot")]
    paired_plate(label + " chest recessed panel", side, [(.038, 1.231), (.15, 1.257),
        (.207, 1.229), (.183, 1.199), (.045, 1.192)], -.224, .012, "Body", "blue_dark", "Bip01 Spine1", .004)
    paired_plate(label + " chest inset bevel highlight", side, [(.054, 1.226), (.151, 1.248),
        (.168, 1.239), (.058, 1.214)], -.24, .004, "Body", "blue_light", "Bip01 Spine1", .002)
    seam(label + " chest lower panel seam", [(side * .055, 1.129, -.218),
        (side * .085, 1.078, -.218), (side * .202, 1.121, -.218)], "Body", "blue_dark", "Bip01 Spine1")
    bolt(label + " chest upper fastener", (side * .223, 1.243, -.218), "Body", "Bip01 Spine1")
    bolt(label + " chest lower fastener", (side * .103, 1.102, -.218), "Body", "Bip01 Spine1", .005)
    shoulder = bpy.data.objects[label + " angular shoulder"]
    seam(label + " shoulder panel seam", [(side * x, y, 0) for x, y in
        [(.294, 1.38), (.442, 1.38), (.48, 1.30), (.442, 1.205), (.30, 1.205), (.265, 1.27), (.294, 1.38)]],
        "Body", "blue_dark", upper, .0035, shoulder)
    seam(label + " shoulder engraved edge", [(side * x, y, 0) for x, y in
        [(.298, 1.37), (.438, 1.37), (.470, 1.30)]], "Body", "blue_light", upper, .002, shoulder)
    paired_plate(label + " rear shoulder inset", side, [(.285, 1.365), (.452, 1.365),
        (.48, 1.30), (.435, 1.265), (.30, 1.265)], .205, .009, "Body", "blue_dark", upper, .006)
    paired_plate(label + " rear shoulder identification", side, [(.306, 1.345), (.433, 1.345),
        (.442, 1.318), (.314, 1.318)], .218, .004, "Body", "blue_light", upper, .002)
    for y in (.837, .865, .893):
        paired_plate(label + " bracer cooling slit", side, [(.454, y), (.50, y),
            (.50, y + .013), (.454, y + .013)], -.122, .007, "Hand", "ink", fore, .002)
    bolt(label + " bracer fastener", (side * .477, .933, -.097), "Hand", fore, .005)
    thigh_shell = bpy.data.objects[label + " thigh shell"]
    seam(label + " thigh panel seam", [(side * x, y, 0) for x, y in
        [(.143, .712), (.206, .712), (.238, .65), (.218, .515), (.172, .492), (.143, .525), (.143, .712)]],
        "Body", "blue_dark", thigh, .0035, thigh_shell)
    seam(label + " thigh engraved edge", [(side * x, y, 0) for x, y in
        [(.153, .703), (.201, .703), (.229, .65), (.211, .53)]],
        "Body", "blue_light", thigh, .0018, thigh_shell)
    paired_plate(label + " thigh unit stripe", side, [(.102, .702), (.126, .711),
        (.126, .64), (.102, .635)], -.128, .005, "Body", "blue_light", thigh, .002)
    shin = bpy.data.objects[label + " shin plate"]
    seam(label + " shin central channel", [(side * x, y, 0) for x, y in
        [(.154, .335), (.213, .335), (.24, .285), (.222, .19), (.181, .178), (.154, .218), (.154, .335)]],
        "Foot", "blue_dark", calf, .0035, shin)
    seam(label + " shin engraved edge", [(side * x, y, 0) for x, y in
        [(.162, .325), (.209, .325), (.231, .283), (.216, .207)]],
        "Foot", "blue_light", calf, .0018, shin)
    paired_plate(label + " knee armor inset", side, [(.126, .418), (.17, .434), (.214, .418),
        (.205, .397), (.135, .397)], -.148, .008, "Foot", "blue_light", calf, .003)
    bolt(label + " knee fastener", (side * .17, .377, -.146), "Foot", calf, .007)

# Small identification stencil, authored as editable font geometry before bake.
font = bpy.data.curves.new("Viper shoulder identification", "FONT")
font.body, font.size, font.align_x, font.align_y = "01", .064, "CENTER", "CENTER"
font.extrude = .0008
stencil = bpy.data.objects.new("Viper shoulder identification", font)
bpy.context.collection.objects.link(stencil)
stencil.location = Vector((.372, 1.302, -.113))
stencil.rotation_euler.y = math.pi
activate(stencil)
bpy.ops.object.convert(target="MESH")
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
finish(bpy.context.object, "Body", "cream", "Bip01 R UpperArm", smooth=False)
plate("Backpack access hatch", [(-.061, 1.235), (.061, 1.235), (.061, 1.07),
      (.042, 1.046), (-.042, 1.046), (-.061, 1.07)], .322, .012, "Bag", "blue", "fly_bag", .004)
plate("Backpack violet status lamp", [(-.018, 1.197), (.018, 1.197), (.018, 1.157),
      (-.018, 1.157)], .337, .004, "Bag", "purple_light", "fly_bag", .002)
for y in (1.09, 1.14, 1.19):
    for side in (-1, 1):
        paired_plate("Backpack cooling slot highlight", side, [(.085, y + .019), (.155, y + .019),
            (.155, y + .03), (.085, y + .03)], .342, .004, "Bag", "blue_light", "fly_bag", .002)

# Give the undersuit a continuous human pelvis, then carry fuller anatomical
# volumes through each armor piece and its markings without moving the rig.
blob("Continuous padded hips", (0, .797, .025), (.184, .105, .137), "Body", "rubber", "Bip01 Pelvis", .85)
for side in (-1, 1):
    paired_plate("Overlapping lateral abdominal plate", side, [(.118, .967), (.205, .995),
        (.211, .913), (.133, .884)], -.161, .036, "Body", "blue_dark", "Bip01 Spine", .007)

def fill_human_proportions(obj):
    if obj.get("anatomical_detail", False):
        return
    for vertex in obj.data.vertices:
        strongest = max(vertex.groups, key=lambda group: group.weight)
        bone = obj.vertex_groups[strongest.group].name
        point = vertex.co.copy()
        side = -1 if " L " in bone else 1
        if "UpperArm" in bone or "Forearm" in bone:
            if point.y >= .963:
                t = max(0, min(1, (1.313 - point.y) / .35))
                center = Vector((side * .372, 1.313, .068)).lerp(Vector((side * .448, .963, .058)), t)
                width = 1.12 + .22 * math.sin(math.pi * t)
            else:
                t = max(0, min(1, (.963 - point.y) / .227))
                center = Vector((side * .448, .963, .058)).lerp(Vector((side * .494, .736, .017)), t)
                width = 1.08 + .16 * math.sin(math.pi * t)
            point.x = center.x + (point.x - center.x) * width
            point.z = center.z + (point.z - center.z) * width
        elif "Thigh" in bone or "Calf" in bone:
            if point.y >= .387:
                t = max(0, min(1, (.779 - point.y) / .392))
                center = Vector((side * .141, .779, 0)).lerp(Vector((side * .169, .387, -.019)), t)
                width = 1.18 + .15 * math.sin(math.pi * t)
            else:
                t = max(0, min(1, (.387 - point.y) / .25))
                center = Vector((side * .169, .387, -.019)).lerp(Vector((side * .186, .137, .016)), t)
                width = 1.10 + .14 * math.sin(math.pi * t)
            point.x = center.x + (point.x - center.x) * width
            point.z = center.z + (point.z - center.z) * width
        elif bone in ("Bip01 Pelvis", "Bip01 Spine", "Bip01 Spine1"):
            point.x *= 1.20
            point.z = .02 + (point.z - .02) * 1.15
        elif " Hand" in bone:
            point.x = side * .494 + (point.x - side * .494) * 1.08
            point.z = .017 + (point.z - .017) * 1.08
        elif " Foot" in bone:
            point.x = side * .186 + (point.x - side * .186) * 1.07
        vertex.co = point
    obj.data.update()

for part in ("Body", "Hand", "Foot"):
    for obj in parts[part]:
        fill_human_proportions(obj)

# Reproject after the nonlinear limb widening. A densely sampled stripe and a
# broad planar plate otherwise deform differently and the line sinks inside.
bpy.context.view_layer.update()
for objects in parts.values():
    for obj in objects:
        if "surface_target" not in obj:
            continue
        target = bpy.data.objects[obj["surface_target"]]
        for vertex in obj.data.vertices:
            hit, location, normal, face_index = target.ray_cast(Vector((vertex.co.x, vertex.co.y, -2)), Vector((0, 0, 1)))
            if not hit:
                raise ValueError("Deformed panel detail misses " + target.name)
            vertex.co = location + Vector((0, 0, -.004))
        obj.data.update()

scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = 1
scene.render.bake.margin = 6
scene.render.bake.use_clear = True
outputs, report = [], []
for part, objects in parts.items():
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    obj = bpy.context.object
    obj.name = "Armor%s_00" % part
    # Preserve SourceUV only for the helmet's authored patterns; runtime uses
    # the new atlas UVs. Fractional padding keeps unlike islands from bleeding.
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=.012, margin_method="FRACTION")
    bpy.ops.object.mode_set(mode="OBJECT")
    image = bpy.data.images.new("CartoonViper_" + part, width=2048, height=2048, alpha=False)
    image.colorspace_settings.name = "sRGB"
    for mat in obj.data.materials:
        node = mat.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        mat.node_tree.nodes.active = node
    bpy.ops.object.bake(type="EMIT")
    image.filepath_raw = str(ASSETS / (part.lower() + "_albedo.png"))
    image.file_format = "PNG"
    image.save()
    obj.data.calc_loop_triangles()
    attrs = {"name": obj.name, "texture": part.lower() + "_albedo.png", "positions": [], "normals": [], "uv": [], "bones": [], "weights": []}
    for triangle in obj.data.loop_triangles:
        for loop_index in triangle.loops:
            vertex = obj.data.vertices[obj.data.loops[loop_index].vertex_index]
            attrs["positions"].extend(vertex.co)
            attrs["normals"].extend(obj.data.corner_normals[loop_index].vector.normalized())
            attrs["uv"].extend(obj.data.uv_layers.active.data[loop_index].uv)
            groups = sorted((g for g in vertex.groups if g.weight > 0), key=lambda g: -g.weight)[:4]
            total = sum(g.weight for g in groups)
            if total <= 0:
                raise ValueError(f"Unweighted vertex {obj.name}/{vertex.index}")
            attrs["bones"].append([obj.vertex_groups[g.group].name for g in groups])
            attrs["weights"].append([g.weight / total for g in groups])
    outputs.append(attrs)
    report.append({"part": obj.name, "triangles": len(obj.data.loop_triangles), "texture": attrs["texture"]})
    # Save editable textured meshes with the original armature modifier.
    mat = bpy.data.materials.new(obj.name + "_BakedPaint")
    mat.use_nodes = True
    mat.node_tree.nodes.clear()
    principled = mat.node_tree.nodes.new("ShaderNodeBsdfPrincipled")
    output_node = mat.node_tree.nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(principled.outputs["BSDF"], output_node.inputs["Surface"])
    principled.inputs["Roughness"].default_value = .9
    principled.inputs["Metallic"].default_value = 0
    texture = mat.node_tree.nodes.new("ShaderNodeTexImage")
    texture.image = image
    mat.node_tree.links.new(texture.outputs["Color"], principled.inputs["Base Color"])
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
    armature = obj.modifiers.new("Original Star Warfare skeleton", "ARMATURE")
    armature.object = rig
    image.filepath = "//../../../assets/armors/cartoon_viper/" + attrs["texture"]

(WORK / "meshes.json").write_text(json.dumps(outputs, separators=(",", ":")))
summary = {
    "design": "faceted combat armor; fuller human proportions, flexible weighted joints, bold assembly details and flat-color UV atlases",
    "preserved": "Original Viper helmet silhouette, authored panel artwork and 28-bone rig; body, five-digit gloves, anatomical boots and backpack rebuilt",
    "source": "docs/art/armor_rework/viper.blend",
    "source_sha256": hashlib.sha256((ROOT / "docs/art/armor_rework/viper.blend").read_bytes()).hexdigest(),
    "rig_bones": len(rig.data.bones),
    "parts": report,
    "palette": PALETTE,
}
(ASSETS / "build_report.json").write_text(json.dumps(summary, indent=2) + "\n")
for action in list(bpy.data.actions):
    bpy.data.actions.remove(action)
bpy.data.orphans_purge(do_recursive=True)
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(NATIVE), compress=True)
print("CARTOON_VIPER_BUILD_PASS parts=%d triangles=%d" % (len(report), sum(p["triangles"] for p in report)))

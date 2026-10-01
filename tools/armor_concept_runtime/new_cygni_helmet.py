"""New concept helmet + new UV layout; original game rig is scale authority.

No old helmet geometry or UV atlas is used. The temporary colored UV diagram
is a technical layout for imagegen, not the delivered painted texture.
"""
from __future__ import annotations

import json
import math
import runpy
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent))
from build import Part, color, export_json

WORK = ROOT / "test_output/armor_concept_runtime"
NATIVE = ROOT / "docs/art/armor_runtime_v1/armor_11/new_helmet"
PAINT = color("#D8DCDA")
GREEN = color("#263C33")
GLASS = color("#BE984A", .72)
CLOTH = color("#17221C", .08)
BONE = "Bip01 Head"
PAINTED_UV = "--painted-uv" in sys.argv
# Approximate island bounds measured on the generated atlas, normalized.
# AI shifted several islands; fit UVs to the new paint rather than quietly
# claiming the image obeyed the technical guide pixel for pixel.
PAINTED_REGIONS = {
    "NewCrown": (.026, .554, .522, .973),
    "NewGoldTVisor": (.556, .553, .975, .899),
    "VisorSeal": (.551, .938, .892, .976),
    "NewCrest": (.030, .385, .261, .521),
    "NewBrow": (.284, .386, .523, .521),
    "NewShortChin": (.770, .061, .967, .313),
    "NeckSeal": (.930, .940, .983, .980),
}


def make_material(name, tint):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*tint[:3], 1)
    return material


def project_uv(obj, rect, axes=(0, 1), mirrored=False, cylindrical=False):
    mesh = obj.data
    layer = mesh.uv_layers.active
    lo = [min(v.co[a] if not (mirrored and a == 0) else abs(v.co[a]) for v in mesh.vertices) for a in axes]
    hi = [max(v.co[a] if not (mirrored and a == 0) else abs(v.co[a]) for v in mesh.vertices) for a in axes]
    for polygon in mesh.polygons:
        raw = []
        for index in polygon.loop_indices:
            point = mesh.vertices[mesh.loops[index].vertex_index].co
            if cylindrical:
                # Rear seam; visible brow is at the centre of the large island.
                u = (math.atan2(point.x, point.z + .050) / math.tau) % 1
                v = (point.y - lo[1]) / (hi[1] - lo[1])
            else:
                values = [abs(point[a]) if mirrored and a == 0 else point[a] for a in axes]
                u, v = [(q - a) / (b - a) for q, a, b in zip(values, lo, hi)]
            raw.append((index, u, v))
        seam = cylindrical and max(u for _, u, _ in raw) - min(u for _, u, _ in raw) > .5
        for index, u, v in raw:
            if seam and u < .5:
                u += 1
            layer.data[index].uv = (rect[0] + u * (rect[2] - rect[0]), rect[1] + v * (rect[3] - rect[1]))


def main() -> None:
    scope = runpy.run_path(str(ROOT / "tools/armor_rework/inspect_source.py"))
    rig = scope["rig"]
    for obj in list(bpy.data.objects):
        if obj != rig:
            bpy.data.objects.remove(obj, do_unlink=True)
    low = bpy.data.collections.new("LOW")
    bpy.context.scene.collection.children.link(low)
    components = []

    def component(name, tint, rect, build, **uv):
        part = Part(name)
        build(part)
        obj = part.object(rig, low)
        obj.data.materials.append(make_material(name + "_guide", tint))
        if PAINTED_UV:
            if name.startswith("NewSweptCheek"):
                rect = (.545, .070, .738, .538)
            elif name.startswith("CheekVent"):
                rect = (.775, .359, .971, .530)
            elif name.startswith("Ear"):
                rect = (.022, .072, .266, .318)
            elif name.startswith("Wing"):
                rect = (.285, .075, .523, .316)
            else:
                rect = PAINTED_REGIONS.get(name, rect)
        project_uv(obj, rect, **uv)
        # Broad shell normals are smooth; the authored seams and bevels retain
        # actual geometry instead of a flat slab across the entire face.
        if name == "NewCrown":
            for face in obj.data.polygons:
                face.use_smooth = True
        components.append(obj)
        return obj

    # Original Cygni game envelope: Y 1.1964..1.9784, wings X ±.3416,
    # front Z -.4447. Internal shapes below follow the concept; depths inferred.
    component("NewCrown", PAINT, (.025, .525, .52, .975), lambda p: p.loft("segmented rounded crown",
        [(0, 1.350, -.030, .167, .205), (0, 1.460, -.050, .228, .262),
         (0, 1.640, -.050, .265, .297), (0, 1.785, -.042, .248, .278),
         (0, 1.888, -.028, .218, .235), (0, 1.955, -.009, .155, .161),
         (0, 1.9784, .015, .078, .082)], PAINT, BONE, 32), cylindrical=True)
    component("NeckSeal", CLOTH, (.925, .935, .985, .985), lambda p: p.loft("flexible neck",
        [(0, 1.1964, .020, .102, .102), (0, 1.435, .025, .112, .112)], CLOTH,
        {"Bip01 Neck": .65, BONE: .35}, 20))

    def curved_plate(name, outline, z, depth, tint, rect, bevel=.005, mirrored=False):
        def make(part):
            part.plate(name, outline, z, depth, tint, BONE, bevel=bevel)
            # Visor and cheeks wrap around the face. Main surface remains
            # forward at the centre, returns toward the ear on both sides.
            part.vertices = [(x, y, zz + .92 * x * x + .06 * abs(x)) for x, y, zz in part.vertices]
            if name == "NewCrest":
                # Follow the new dome at the top rather than a vertical slab.
                part.vertices = [(x, y, zz + max(0.0, y - 1.85) * 1.20) for x, y, zz in part.vertices]
        return component(name, tint, rect, make, mirrored=mirrored)

    visor = [(-.231, 1.718), (-.134, 1.739), (0, 1.706), (.134, 1.739), (.231, 1.718),
             (.218, 1.603), (.077, 1.562), (.055, 1.407), (0, 1.337),
             (-.055, 1.407), (-.077, 1.562), (-.218, 1.603)]
    curved_plate("VisorSeal", [(x * 1.045, 1.55 + (y - 1.55) * 1.045) for x, y in visor], -.432, .067, GREEN, (.545, .925, .890, .975), bevel=.004)
    curved_plate("NewGoldTVisor", visor, -.4447, .024, GLASS, (.550, .535, .975, .900), bevel=.003)
    curved_plate("NewBrow", [(-.252, 1.752), (-.156, 1.797), (0, 1.772), (.156, 1.797),
                              (.252, 1.752), (.236, 1.710), (.136, 1.731), (0, 1.700),
                              (-.136, 1.731), (-.236, 1.710)], -.437, .079, PAINT, (.285, .325, .525, .495), bevel=.006)
    curved_plate("NewCrest", [(-.123, 1.933), (.123, 1.933), (.153, 1.854), (.114, 1.803),
                               (0, 1.782), (-.114, 1.803), (-.153, 1.854)], -.321, .045, PAINT, (.025, .325, .265, .495), bevel=.006)
    for side in (-1, 1):
        outline = [(side * x, y) for x, y in [(.247, 1.684), (.206, 1.582), (.100, 1.536),
                     (.076, 1.410), (.049, 1.320), (.105, 1.301), (.195, 1.450), (.257, 1.585)]]
        curved_plate(f"NewSweptCheek{side}", outline, -.428, .059, PAINT, (.550, .035, .745, .510), bevel=.005, mirrored=True)
        curved_plate(f"CheekVent{side}", [(side * x, y) for x, y in [(.164, 1.548), (.203, 1.566),
                       (.213, 1.538), (.170, 1.505)]], -.436, .010, GREEN, (.775, .330, .970, .495), bevel=.002, mirrored=True)
        component(f"EarRing{side}", GREEN, (.025, .035, .255, .275), lambda p, s=side: p.disc("ear connector",
            (s * .264, 1.652, -.030), .082, GREEN, BONE, axis=0), axes=(2, 1))
        component(f"EarFace{side}", PAINT, (.025, .035, .255, .275), lambda p, s=side: p.disc("ear plate",
            (s * .272, 1.652, -.030), .060, PAINT, BONE, axis=0), axes=(2, 1))
        for row, y in enumerate([1.625, 1.736]):
            component(f"Wing{side}_{row}", PAINT, (.285, .035, .525, .275), lambda p, s=side, yy=y: p.plate("short swept side fin",
                [(s * .252, yy), (s * .3416, yy + .046), (s * .323, yy + .124),
                 (s * .249, yy + .049)], .162, .018, PAINT, BONE, bevel=.004), mirrored=True)
    curved_plate("NewShortChin", [(-.046, 1.349), (0, 1.338), (.046, 1.349), (.042, 1.292),
                                  (0, 1.278), (-.042, 1.292)], -.390, .045, PAINT, (.775, .035, .970, .275), bevel=.004)
    payload = [export_json(obj) for obj in components]
    WORK.mkdir(parents=True, exist_ok=True)
    NATIVE.mkdir(parents=True, exist_ok=True)
    (WORK / "new_helmet_components.json").write_text(json.dumps(payload, separators=(",", ":")))
    sources = json.loads((ROOT / "test_output/armor_facets/sources.json").read_text())
    original_head = next(e for e in sources["entries"] if e["id"] == 11)["parts"][0]
    bind_map = {b["name"]: b["index"] for b in original_head["binds"]}
    arrays = {k: [] for k in ("0", "1", "3", "4", "10", "11", "12")}
    for data in payload:
        for triangle in range(len(data["positions"]) // 9):
            for corner in (2, 1, 0):
                i = triangle * 3 + corner
                x, y, z = data["positions"][i * 3:i * 3 + 3]
                nx, ny, nz = data["normals"][i * 3:i * 3 + 3]
                arrays["0"].append([x, z, -y])
                arrays["1"].append([nx, nz, -ny])
                arrays["3"].append(data["colors"][i * 4:i * 4 + 4])
                u, v = data["uv"][i * 2:i * 2 + 2]
                arrays["4"].append([u, 1 - v])
                bones = [bind_map[b] for b in data["bones"][i]]
                weights = data["weights"][i]
                arrays["10"].extend(bones + [0] * (4 - len(bones)))
                arrays["11"].extend(weights + [0.0] * (4 - len(weights)))
    arrays["12"] = list(range(len(arrays["0"])))
    (WORK / "new_helmet_arrays.json").write_text(json.dumps(arrays, separators=(",", ":")))
    bpy.context.preferences.filepaths.save_version = 0
    bpy.data.orphans_purge(do_recursive=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(NATIVE / "blockout.blend"), compress=True)
    if PAINTED_UV:
        image = bpy.data.images.load(str(ROOT / "assets/armors/concept_runtime/textures/new_cygni_helmet.png"), check_existing=True)
        image.colorspace_settings.name = "sRGB"
        image.pack()
        material = bpy.data.materials.new("NewCygni_PaintedAtlas")
        material.use_nodes = True
        nodes = material.node_tree.nodes
        shader = nodes.get("Principled BSDF")
        texture = nodes.new("ShaderNodeTexImage")
        texture.image = image
        tint = nodes.new("ShaderNodeMixRGB")
        tint.blend_type = "MULTIPLY"
        tint.inputs[0].default_value = 1
        # Existing body uses this neutral tint in Godot; the new head must not
        # inherit the original red head multiplier.
        tint.inputs[2].default_value = (.79059, .79059, .79059, 1)
        material.node_tree.links.new(texture.outputs["Color"], tint.inputs[1])
        material.node_tree.links.new(tint.outputs[0], shader.inputs["Base Color"])
        material.node_tree.links.new(tint.outputs[0], shader.inputs["Emission Color"])
        shader.inputs["Emission Strength"].default_value = .75
        shader.inputs["Roughness"].default_value = .78
        shader.inputs["Metallic"].default_value = 0
        for obj in components:
            obj.data.materials.clear()
            obj.data.materials.append(material)
        bpy.ops.wm.save_as_mainfile(filepath=str(NATIVE / "master.blend"), compress=True)

    # Render a NEW UV layout from the new meshes, not pixels edited from an old
    # atlas. UV-seam copies overlap only where the two symmetric parts share art.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    guide_collection = bpy.context.scene.collection
    for index, data in enumerate(payload):
        verts = [(u, v, index * .00001) for u, v in zip(data["uv"][::2], data["uv"][1::2])]
        mesh = bpy.data.meshes.new(data["name"] + "_UV")
        mesh.from_pydata(verts, [], [tuple(range(i, i + 3)) for i in range(0, len(verts), 3)])
        obj = bpy.data.objects.new(data["name"], mesh)
        guide_collection.objects.link(obj)
        tint = data["colors"][:4]
        obj.data.materials.append(make_material(data["name"] + "_guide", tint))
    camera_data = bpy.data.cameras.new("UVLayoutCamera")
    camera = bpy.data.objects.new("UVLayoutCamera", camera_data)
    guide_collection.objects.link(camera)
    camera.location = (.5, .5, 2)
    camera.rotation_euler = (0, 0, 0)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1
    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = False
    scene.display.shading.show_cavity = False
    scene.display.shading.show_object_outline = True
    scene.display.shading.object_outline_color = (0, 0, 0)
    scene.display.shading.background_type = "WORLD"
    scene.world = bpy.data.worlds.new("UVLayoutBackground")
    scene.world.color = (.005, .010, .008)
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(WORK / ("new_cygni_helmet_uv_applied.png" if PAINTED_UV else "new_cygni_helmet_uv_guide.png"))
    bpy.ops.render.render(write_still=True)
    print("NEW_CYGNI_HELMET_BLOCKOUT_AND_UV_READY", flush=True)


if __name__ == "__main__":
    main()

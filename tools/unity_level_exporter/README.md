# Legacy Unity level exporter

This exporter rebuilds the 17 recovered campaign maps from Unity's
text-serialized scenes. It writes `stage.obj`, collision geometry, spawn and
waypoint metadata, render settings, materials, and textures without opening the
Unity editor.

Both Unity 2017 material dictionary layouts are supported: the newer
`first`/`second` representation and the direct `- _MainTex:` / `- _texBase:`
representation used by the late-game lightmapped stages. `_texBase` is used as
the diffuse texture. `stage.gltf` / `stage.bin` carry the exact OBJ triangles
and original UV1 as Godot UV2, because OBJ cannot represent two UV channels.
Runtime loads that visual mesh and restores `_texLightmap` with its original
per-material scale/offset and shader multiplier (1x for `iPhone/LightMap`, 2x
for `Optimized/LightMap` and the `_double` variants).

Lightmap PNGs are copied byte for byte at source resolution. There are 270
lightmapped material surfaces across the 17 maps. `level.json` also preserves
all 1,866 source Light components, including their disabled hierarchy state;
they are editor/bake data, not 1,866 lights to activate in the running game.
The authored baked illumination remains visible at every quality level. High
and medium add a small dynamic light response for shadows and weapon flashes;
low retains the baked result alone. Pure `SolidTexture` sky/backdrop materials
remain unlit, as in Unity.

The three `SolidAndAlphaTexture` lamp materials in Levels 1, 3, and 5 also
retain their second emissive layer: `_tex2 * _TintColor + _texBase`, with
the Bright variant doubling `_tex2` and binding `_texBase` to UV2.

The source project uses Gamma color space (`m_ActiveColorSpace: 0`). The runtime
shader preserves the source texture multiplication in sRGB, including on
linear renderers, and uses the exported atlas transform exactly once. See
`Assets/Shader/Optimized Lightmap.shader` and `Assets/Editor/StaticLightmap.cs`
in the original Unity workspace. Godot's renderer color-space contract is
documented under [OUTPUT_IS_SRGB](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/spatial_shader.html).

Existing restored textures at the required resolution are preserved byte for
byte. Newly recovered textures are written as 2x RGBA PNGs with Pillow and a
4096-pixel cap. Reused basenames receive an eight-character Unity GUID suffix,
so one source texture cannot overwrite another.

```powershell
python tools/unity_level_exporter/export.py `
  --assets-root E:\Star-Warfare-1.0.2\Star-Warfare-1.0.2\Assets `
  --godot-root .

.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/level_restoration_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/scene_asset_integrity_test.tscn
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/sector_lighting_test.tscn
```

The committed export report is `level_export_report.json`. A clean full export
has 17 levels, 58 visual renderer batches, 1,851 primitive colliders, 315 mesh
colliders, and zero converter warnings.

The shared OBJ writer collapses repeated Unity material instances and groups
all faces using the same render state into one OBJ material section. This keeps
every restored level below Godot's 256-surfaces-per-mesh limit without dropping
geometry. The schema comment in generated OBJ files is versioned deliberately:
when external MTL/texture recovery changes, updating it forces Godot to rebuild
its OBJ cache (Godot does not otherwise track `stage.mtl` as an import dependency).

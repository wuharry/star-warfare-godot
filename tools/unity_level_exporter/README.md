# Legacy Unity level exporter

This exporter rebuilds the 17 recovered campaign maps from Unity's
text-serialized scenes. It writes `stage.obj`, collision geometry, spawn and
waypoint metadata, render settings, materials, and textures without opening the
Unity editor.

Both Unity 2017 material dictionary layouts are supported: the newer
`first`/`second` representation and the direct `- _MainTex:` / `- _texBase:`
representation used by the late-game lightmapped stages. `_texBase` is used as
the diffuse texture; the legacy secondary light map remains outside OBJ's
single-diffuse-material model.

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

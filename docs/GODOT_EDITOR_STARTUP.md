# Godot editor texture-import crash

Date: 2026-09-08

Rule: Keep `rendering/textures/vram_compression/compress_with_gpu=false` in
`project.godot` for this project on the current Windows/Godot 4.7.2 setup.

Why: The graphical editor crashed with access violation `0xc0000005` while
reimporting level textures, including `level_16/booox_10.png`. The executable
offset was `0x3286e8a`. Although the project renders with GL Compatibility,
Godot's GPU texture compressor creates an auxiliary Vulkan device. The crash
followed that device's initialization. The same import completed and the editor
exited normally after disabling GPU compression. The logs also mention a missing
Epic Vulkan-overlay manifest; this alone does not establish the underlying
driver/overlay defect, and no system registry or driver changes were made.

How: This setting selects CPU texture compression. Keep the existing desktop
and mobile compression formats, mipmaps, texture dimensions and import-quality
settings. CPU and GPU encoders can produce different compressed bytes; this is
not a texture-resolution reduction or a change to the game's renderer.

Godot's implementation at the exact engine commit:

- [Image compression dispatch](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/core/io/image.cpp)
- [Auxiliary rendering device in BetsyCompressor](https://github.com/godotengine/godot/blob/ed1daf0bf001b61586d9930840f2f1394092c079/modules/betsy/image_compress_betsy.cpp)

Verification: Run the graphical editor through actual import and preview
generation. A headless editor import does not exercise this failing GPU path.
For a bounded graphical probe:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --editor --path . --verbose --quit-after 600
```

Local diagnostic logs from the reproduction and successful comparison are in
`test_output/editor_startup/`. The previous armor and lighting changes remain
in place; no import cache or `.import` sidecar was manually rewritten.

## Windows renderer initialization crash (2026-10-04)

Rule: Keep `rendering/gl_compatibility/driver.windows="opengl3_angle"` in
`project.godot`. Restart an already-open project to load this startup setting.

Why: The latest three Windows Application Error events point to NVIDIA
`nvoglv64.dll` (32.0.15.9579), exception `0xc00000fd`, during Godot 4.7.2
startup. The game log stops after the engine banner, before renderer or game
script initialization. The same project and armor resources start and run with
ANGLE over Direct3D 11. Asset decoding, skinning and source hashes remain valid.

How: Select ANGLE as the Windows Compatibility driver in the project settings.
Keep the Compatibility renderer, CPU texture compression and artwork. The
existing Godot native-driver fallback remains available; no driver installation
or system settings are required. Other platform drivers keep their defaults.
See [Godot's Windows Compatibility driver documentation](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-gl-compatibility-driver-windows).

Verification: Use the normal graphical engine without `--rendering-driver`.
The project main scene, `tests/menu_equipment_test.tscn` and
`tests/smoke_test.tscn` all exit 0 and show ANGLE/Direct3D 11 in their startup
banners. The editor is checked separately with a bounded graphical startup.
Evidence, process arguments, exit codes and original crash events are retained
in `test_output/startup_crash_20261004/`; real save-file hashes are checked.

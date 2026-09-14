# Thunder detail v4

Thunder set 06 combines the approved blue/amber concept with correctly paired Star Warfare 2 helmet topology and surface detail. The player, store and equipment preview all load `assets/armors/thunder/thunder.scn` through `ArmorVisuals.REWORKED_SCENES[6]`.

The enlarged amber visor preserves the prototype's open appearance and rounded lower contour, with the current diagonal upper brow and the original curved engraved channels. The crown stays low. The respirator has a recessed intake, bevelled graphite housing and individual louvres; its depth is compressed toward the jaw after user review. An overlapping ribbed neck socket connects the two games' different neck construction. The back retains the original SW2 panels, vents and UV layout.

Chest, shoulder, forearm and leg plates have actual crests and sloping chamfers. Painted edges sample their own original atlas instead of a generic blue strip. Source triangle cutouts, winding and interpolated skin weights are retained. The original tall collar corners are tucked into the shoulder line.

## Source and paint

[Source provenance](source_sw2/README.md) documents the exact renderer/mesh/material links from the user-provided SW2 OBB. The old `Avatar06_head.png` and new `sw_06_head_d` belong to different mesh versions; only the latter is paired with the selected head. Original source JSON and textures are retained under `source_sw2/.gdignore`.

The selected [helmet atlas](textures/helmet_detail_albedo.png) was refined with the built-in image_gen tool at its native 1254 x 1254 resolution. [Exact prompts](helmet_texture_prompt.txt) include the corrective opaque pass. The original normal map (256 x 256) and emission map (512 x 512) are preserved; this does not claim they were upscaled. Four body atlases remain the previous 1254-square Thunder repaint.

Unity stores material masks in the source PNG alpha channels. Many fully transparent pixels contain valid diffuse RGB or tangent normals. Godot's default alpha-border processing changes those values. The compiler therefore decodes the four helmet PNGs directly and saves lossless `ImageTexture` `.res` files through Godot. Runtime materials reference these portable resources, not development-only raw file loading. No mipmaps, lossy image compression, hand-edited import files or edited cache files are involved. Tests compare every decoded pixel against the raw source.

The original normal map uses Blender's preserved tangent frame. Texture addressing flips V once at Godot export while tangent handedness stays paired with the source map. The runtime is authoritative; the editable [Blender file](../../../docs/art/armor_rework/thunder.blend) provides the geometry and source materials for further art work.

## Build and inspect

From the repository root:

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background --python-exit-code 1 --python tools/armor_rework/build_thunder.py
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/armor_rework/compile_thunder.gd -- --self-test
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/armor_rework/compile_thunder.gd
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://tests/thunder_armor_test.tscn
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility res://tools/thunder_detail_preview/capture.tscn -- --stage=current
python tools/thunder_detail_preview/build_preview.py --publish
```

[Build report](build_report.json) records the geometry, source and texture hashes. The four interchangeable parts carry revision `thunder_detail_v4` and retain the original named 28-bone binding. Test captures equip all four pieces using an isolated profile; they do not change the user's current mixed armor selection, rank or currencies.

The [interactive Godot comparison](../../../docs/art/thunder_detail_v4/index.html) includes matched before/after studio angles, close details, movement/reload and real levels. Original SW2 Blender reference renders are clearly labelled separately. The [previous v3 report](../../../docs/art/thunder_concept_v3/index.html) remains archived.

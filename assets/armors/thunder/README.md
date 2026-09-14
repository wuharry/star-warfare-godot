# Thunder — concept reconstruction v3

The runtime Thunder set (06) is rebuilt toward the [approved full-body concept](../../../docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png). This replaces the previous `thunder_mk1_helmet_v2` asset. The concept is the visual target; a single view does not specify every hidden surface, so the side/back construction continues its visible design language.

- The helmet has a new rounded shell, fitted continuous crown spine, curved amber V aperture, angular ear cartridges and segmented jaw guards. The pointed original head shell is replaced.
- The body has fitted chest plates, three overlapping shoulder tiers, shallow abdominal relief, forearm/wrist shells, knee/shin plates and separate toe guards. New surfaces retain the original UV seams and interpolate the original skin weights.
- Four dedicated Thunder atlases were repainted; two generated swatches serve the new blue shells and amber visor. [Selected files and exact prompts](../../../docs/art/armor_rework/thunder_texture_prompts.md) document the built-in imagegen work. The import files record lossless storage and no mipmaps. The shaders remain opaque, including atlases whose unused regions have alpha.
- The body uses partial painted-color fill alongside real lighting. The helmet's shell paint handles both Compatibility's sRGB output and Forward+'s linear output. Geometry supplies the edges and thickness.

## Actual game integration

`scripts/game/armor_visuals.gd` maps `REWORKED_SCENES[6]` to `res://assets/armors/thunder/thunder.scn`. The player, store and equipment preview use this same asset. Its four mesh names remain `ArmorHead_06`, `ArmorBody_06`, `ArmorHand_06`, `ArmorFoot_06`; each carries revision `thunder_concept_v3` and named binds to the original 28-bone skeleton.

Equipment IDs, gameplay values, original assets and other armor sets are unchanged. The four parts remain interchangeable with other sets. The full appearance requires equipping all four Thunder parts; captures use a separate test profile rather than replacing the player's selected equipment.

[build_report.json](build_report.json) records the actual triangle counts, bounds and source hashes. The editable Blender source is [thunder.blend](../../../docs/art/armor_rework/thunder.blend); the compiled scene and Godot shaders are the runtime authority.

The SW2 reference assets from commit `252aab1b38d0298994053ffaaec39677ef1ae4ee` were inspected for plate construction. Their raw OBJs have no skin weights, a different rest pose and incompatible direct texture pairing, so they are not substituted wholesale. Existing recovered asset rights remain unchanged by the new paint and geometry.

## Rebuild and verify

Run from the repository root with Blender 5.1 and Godot 4.7.2. Let Godot import new assets normally; do not edit resource UIDs or `.godot` caches.

```powershell
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background --python-exit-code 1 --python tools/armor_rework/build_thunder.py
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/armor_rework/compile_thunder.gd -- --self-test
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . --script tools/armor_rework/compile_thunder.gd
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://tests/thunder_armor_test.tscn
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --headless --path . res://tests/equipment_refinement_test.tscn
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility res://tools/thunder_concept_preview/capture.tscn -- --stage=current
python tools/thunder_concept_preview/build_preview.py
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility --script res://tools/render_armor_thumbnails.gd -- --set-id=6
```

The committed [interactive comparison](../../../docs/art/thunder_concept_v3/index.html) contains the concept, previous runtime and rebuilt runtime. Captures cover four full-body angles, four helmet angles, armed idle, moving reload and levels 1/3. Each run checks the actual revision and preserves the original save SHA-256. No substitute model, billboard, image compositing or body scaling is used in these captures. `python tools/thunder_concept_preview/build_preview.py --publish` refreshes the committed report only when its resource hashes still match the captured model and materials.

Logic tests verify source validation, mesh attributes, normalized skin weights, mixed equipment, animation and store/customize material identity. Passing them does not replace inspecting rendered surfaces and movement. Consult each run's logs and capture manifest for actual results; the commands above are reproducible verification instructions.

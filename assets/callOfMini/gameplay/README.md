# Call of Mini playable armor

These eight generated scenes adapt the enhanced pack to the existing Unity
player rig. Each scene contains four skinned parts (`ArmorHead`, `ArmorBody`,
`ArmorHand`, `ArmorFoot`) with IDs 21–28. `ArmorVisuals.ensure_parts` attaches
them to the player's existing `Skeleton3D`; the original 79 animations and
weapon/backpack sockets continue to drive the character and shop preview.

`ArmorVisuals` also restores the original 21 armor sets' unlit material mode
on per-instance overrides. Their 106 Unity material references resolve to
`Assets/Shader/SolidTexture.shader` (22), `SolidAndAlphaTexture_Bright.shader`
(78), or `SolidAndAlphaTexture.shader` (6); those passes combine textures
without lighting. The imported glTF defaults to lit PBR, which otherwise
turns the player black in the original dark ambient lighting. For example,
`Assets/Resources/avatar/01/Head.prefab` references `Assets/Material/2/head.mat`,
whose shader GUID resolves to `SolidTexture.shader`. The prefab disables
light probes. The starter backpack `Avatar/01/Bag` also uses the unlit Bright
shader (`Material/01.mat`) and white `_TintColor`; its gameplay and shop
materials restore those settings without applying its unused gray `_Color`.
Other backpacks retain their separate material rules. Reconstruction of the
legacy two-texture addition/tint animation remains outside this change.

The source Collada import retained vertex weights but did not create a `Skin`,
and its imported bone rests do not describe the mesh's authored bind pose.
The converter reads the DAE controller's inverse-bind matrices, bridges the
bone axes, and fits geometry near each bone to Viper's corresponding geometry.
The baseline retarget retains every original triangle and UV. Body, forearm/hand, and lower-leg
triangles are split into the same equipment responsibilities as the existing
player; shared seam vertices use the same fitted coordinates and weights.

The original enhanced scenes and textures remain the source assets. The
generated scenes reuse their enhanced materials. Regenerate after modifying
the source pack or the canonical player rig:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/callofmini_enhancer/retarget_armors.gd
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/render_armor_thumbnails.gd -- --callofmini-only
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --editor --path . --import
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/callofmini_gameplay_test.tscn
```

Thumbnail generation requires a rendering display. `fit_report.json` records
source geometry sizes and fitted rest-space sizes in Godot units. The gameplay
test measures actual CPU-skinned vertices in the same `idle_rifle` frame for
Viper and all eight sets, then checks animation deformation and mixed pieces.
Visual acceptance uses `tests/callofmini_visual_capture.tscn` at a fixed camera.

The 32 shop items use Viper's existing per-part prices and stats, with no extra
set bonus. They are optional appearance purchases, available at the initial
rank; original equipment IDs, progression, and owned items remain stable.

## Assault Armor style prototype (2026-09-10)

Set 21 now uses Viper's body, gloves and boots with a muted purple material
tint, plus the original Assault skull helmet and rounded Assault shoulder
plates. This gives elbows, knees and ankles the original game's segmented
shape instead of rounding the source pack's box gloves and wedge boots.
The head is preserved; only the shoulders are remodeled in Blender.
All meshes retain the shared player skin and animation sockets. Canonical
parts keep their original UVs/textures; no bitmap textures were repainted.
Other added sets are unchanged. `fit_report.json` describes the baseline
retarget; `assault_refinement_report.json` records this extra authoring pass.

After regenerating the baseline above, reapply the prototype **before**
rendering thumbnails. Blender 5.1 is required for the authoring command only,
not for playing or opening the generated Godot scene:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/callofmini_enhancer/refine_assault.gd -- --export
& 'C:/Program Files/Blender Foundation/Blender 5.1/blender.exe' --background --factory-startup --python-exit-code 1 --python tools/callofmini_enhancer/refine_assault.py
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tools/callofmini_enhancer/refine_assault.gd -- --import
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --path . --script res://tools/render_armor_thumbnails.gd -- --callofmini-only --set-id=21
```

The bridge checks its source hash and refuses to re-export an already refined
scene, preventing cumulative beveling. Temporary Blender/JSON authoring files
and the before/after review are in `test_output/assault_refinement/`.

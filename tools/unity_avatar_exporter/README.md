# Legacy animated avatar exporter

This converter rebuilds the original player skeleton, skin weights, bind poses,
materials, and all 79 recovered ground/flying animation clips directly from the
text-serialized Unity assets. It writes a glTF 2.0 scene which Godot imports
without requiring a Unity installation or license.

The generated scene deliberately keeps one canonical Skeleton3D and one
AnimationPlayer. Its independently selectable skinned meshes use zero-based
Unity equipment IDs:

- `ArmorHead_00` through `ArmorHead_20`
- `ArmorBody_00` through `ArmorBody_20`
- `ArmorHand_00` through `ArmorHand_20`
- `ArmorFoot_00` through `ArmorFoot_20`

ID `00` is visible by default. The remaining variants use
`KHR_node_visibility`, supported by Godot 4.5 and later, so switching equipment
only requires toggling the matching named nodes. All variants share the same 28
imported bones, including `r hand gun` and `fly_bag`.

Unity reuses generic texture basenames such as `body.png` across unrelated
sets. Armor textures therefore live in `armor_textures/` under content-addressed
names (`<stem>_<sha256>_2x.png`) and are deduplicated by URI. The export needs
Pillow and writes 2x RGBA PNGs.

All 25 Unity bags are exported separately beneath `bags/ArmorBag_XX/`, with
their source IDs, Unity scale rules, geometry counts, and texture list in
`bags/manifest.json`. Bags 15 and 23 preserve all renderable geometry, but their
legacy `FlyBagAnimationScript` motion is recorded as a limitation because OBJ
does not carry that script animation.

```powershell
python tools/unity_avatar_exporter/export.py `
  --project-root E:\Star-Warfare-1.0.2\Star-Warfare-1.0.2 `
  --output assets/models/player/animated/player.gltf
```

Then force a Godot import and run the focused contract test:

```powershell
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
.\.tools\godot-4.7.2\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/avatar_import_test.gd
```

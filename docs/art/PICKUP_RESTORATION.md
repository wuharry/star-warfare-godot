# Original monster loot and pickup effects

Restored 2026-09-12 from `Star-Warfare-1.0.2/Assets` without modifying Unity source.

| Runtime visual | Original source / trigger |
| --- | --- |
| Money model | `Resources/loot/Money.prefab`, `LootManagerScript.SpawnItem(Money)` |
| Energy magazine | `Resources/loot/Enegy.prefab`, `LootManagerScript.SpawnItem(Enegy)` |
| White halo | `Resources/loot/Halo.prefab`, attached to either uncollected drop, camera-facing at world scale 0.4 |
| Gold pickup | `effect_pick_gold_001.prefab`, `Player.OnPickUp(Money)` |
| Blue pickup | `effect_pick_energy_001.prefab`, `Player.OnPickUp(Enegy)` |

`LootType.cs` defines only Money and Enegy. The white source found in this path is
the persistent Halo, not a third reward or a third `OnPickUp` branch. Existing
`ammo` callers are normalized to energy; reward amounts and drop probabilities
are unchanged. The monster spawn path now uses the original floor + 1 height.

The pickup prefabs contain three animated mesh rings and one star emitter.
Original mesh positions, UVs, hierarchy, quaternion/scale curves, alpha curves and
their Hermite tangents are exported. Textures are copied byte-for-byte. Runtime
shaders recover the unlit/additive states and the energy magazine's pulsing
`_tex2` overlay. The magazine has no authored UV1, so both texture stages use UV0.
Particles use Godot CPU simulation with the source delay, emission duration,
lifetime/size ranges, size curve, texture and sphere radius. Random trajectories
are not bit-identical to Unity's particle simulator.

Effects attach at player + 1 and expire after the original two seconds. Drops
expire after 60 seconds; duplicate overlap callbacks cannot award a second reward.
Money uses the original random `pickup_money01`/`pickup_money02` sounds.

## Reproduce

```powershell
python tools/unity_pickup_exporter/export.py --assets-root E:/Star-Warfare-1.0.2/Assets --output assets/pickups
python -m unittest discover -s tools/unity_pickup_exporter -p test_export.py
.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --editor --path . --quit
.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/pickup_restoration_test.tscn
.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/pickup_visual_capture.tscn
```

`assets/pickups/pickups.json` records source paths and SHA-256 checksums for the
prefabs, meshes, animation clips, materials, shaders and copied textures.
The capture writes `test_output/pickup_preview.png` (not committed).

Both export presets explicitly include `assets/pickups/pickups.json`, since the
runtime reads it through FileAccess. No release build was produced for this fix.

Validation: parser regression tests, pickup scene assertions (including actual
physics overlap), smoke assertions, and the 1280x720 GL Compatibility capture
passed. Scene-test shutdown still reports text/CanvasItem/ObjectDB leaks; the
existing smoke scene reports these too, and its final run also reported weapon
texture UID fallback warnings. Harness verification failed on existing generated
policy/config drift outside this change. These are not treated as clean passes.

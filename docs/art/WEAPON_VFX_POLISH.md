# Weapon VFX polish — 2026-09-12

Adds a presentation-only layer to the existing weapon visuals. No damage,
collision queries, ammo costs, tracer cadence, or projectile speeds are changed.

- Laser: retain the fine cylindrical core, reduce the opaque-looking outer
  cylinders, add soft additive ribbons with travelling energy filaments and
  emission/endpoint flares.
- Friendly projectiles: retain their original models and add world-space sampled
  trails that taper, curve, and remain briefly after the projectile disappears.
  Spawn placement is sampled after `_ready`, and teleports break the trail.
- Laser hits and the existing `spawn_explosion` path: expanding surface-oriented
  rings and visible one-shot motes. Particle scales are final world sizes.
- Legacy energy/fire billboard textures use additive blending to remove black
  rectangular backgrounds; smoke keeps alpha blending.

The soft halo is additive geometry/shader falloff, not a new full-screen bloom
pass. It works in the existing GL Compatibility renderer and retains depth
testing. High/medium/low quality cap active polish effects at 64/36/18; low quality
omits secondary motes. Trails retain at most 48 points (24 below high). These are
allocation limits, not measured FPS guarantees.

## Owned files / integration

`scripts/game/weapon_vfx_polish.gd` owns lifetime, detached trail history, budget,
and soft materials. Its two shaders are `assets/shaders/weapon_*.gdshader`.
`game_world.gd` calls beam/burst helpers. `projectile.gd` attaches a trail and
corrects fallback billboard blending. Concurrent `OriginalWeaponEffect` changes
in that same projectile file are preserved. One integration fix uses
`rotate_object_local` for the windblade, avoiding a collision between its inherited
`rotation` property and the other script's static `rotation()` method.

## Verification

```powershell
.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/weapon_polish_test.tscn
.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/weapon_polish_occlusion_capture.tscn
.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --path . --rendering-method gl_compatibility --resolution 1280x720 res://tests/weapon_polish_visual_capture.tscn
```

- PASS: independent scene assertions for degenerate beams, trail sampling and
  cleanup, teleports, impact particles, quality budgets and budget recovery.
- PASS: real 1280x720 GL Compatibility rendering of ribbons, motes and rings;
  occlusion capture checks covered versus exposed beam pixels and was inspected.
- Earlier integrated captures ran, but concurrent RPG source changes mean those
  before/after images are not a controlled comparison of this layer alone.
- FAIL: existing `projectile_vfx_test` expects legacy RPG nodes that concurrent
  `OriginalWeaponEffect` work replaces. Expectations were not changed here.
- PASS: integrated laser/plasma/RPG capture after the rotation-call fix, inspected
  at 1280x720 using GL Compatibility. The plasma's black billboard rectangle is gone.
- PASS with warnings: smoke assertions. Weapon texture UID fallbacks and shutdown
  resource leaks remain in the combined working tree.
- Initial integrated captures also report existing text/CanvasItem/texture
  shutdown leaks. Independent polish tests/capture exit without those warnings.

Captures are written to ignored `test_output/weapon_polish_*.png`.
No release build, mobile FPS measurement, or commit was performed for this task.

# Thunder actual runtime comparison

`capture.tscn` uses `WarfarePlayer._apply_recovered_armor_visibility`, the production skeleton and materials, the existing FR28a reload fixture, and real `game.tscn` levels. It does not substitute a reference billboard, adjust body/head proportions, or change the armor materials for capture.

The studio light and camera are controlled so silhouette and material detail can be reviewed against the supplied concept. The existing `idle_rifle` pose is used with weapons/backpack hidden for the studio images; its arm pose is not the crossed-arm pose in the concept. The actual current and baseline meshes each determine their framing through CPU-skinned bounds. A reference from a single angle cannot specify an exact rear view.

Capture the baseline **before** replacing the mapped Thunder scene:

```powershell
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility res://tools/thunder_concept_preview/capture.tscn -- --stage=baseline
```

Capture the current mapped scene after building/importing the production assets:

The current stage requires the `thunder_concept_v3` metadata on every visible Thunder part, including those loaded by the two live game levels. The manifest also records the production scene SHA-256 at capture startup to distinguish geometry iterations sharing the same revision name.

Current studio and live-game SubViewports explicitly use the game's high preset: render scale 1.0 and 4× MSAA. The archived baseline predates this capture correction and used the SubViewport default (MSAA disabled); its original images remain intact. Compare geometry and painting rather than treating their antialiasing difference as an asset change.

```powershell
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility res://tools/thunder_concept_preview/capture.tscn -- --stage=current
python tools/thunder_concept_preview/build_preview.py
```

Use a real renderer; `--headless` is not a rendered-appearance check. Each run writes 20 images to `test_output/thunder_concept_preview/<stage>/`: 4 full-body angles, 4 helmet angles, armed idle, 9 moving reload frames, and 2 real gameplay views. Studio output is 1200 × 1440, game output 1600 × 900, independent of desktop window dimensions. The capture logs the four visible part revisions and verifies the original save's SHA-256 remains unchanged. Save mutations are redirected to an isolated test profile before player creation.

The builder copies the supplied reference image without processing it and embeds the capture manifests into the HTML. Open `test_output/thunder_concept_preview/index.html`; no server, external libraries, or network are required. Baseline-only output is explicitly labelled as such. Passing capture/browser checks verifies provenance and presentation, not complete visual equivalence or every possible animation pose.

After visual review of the final build, `python tools/thunder_concept_preview/build_preview.py --publish` also copies the exact selected PNGs, original reference, manifests, and an HTML page with adjusted relative links to `docs/art/thunder_concept_v3/`. The normal local report is still built. Publishing rejects a current capture whose scene hash no longer matches the production Thunder scene. It copies no browser profiles or intermediate candidates and performs no bitmap edits. Run `node tools/thunder_concept_preview/check_preview.mjs --published` against the isolated browser below to check that committed location and save its own browser report/screenshots there.

For the browser check, start an isolated headless Edge/Chrome with debugging port 19446 and its own temporary profile, then run:

```powershell
node tools/thunder_concept_preview/check_preview.mjs
```

The checker validates every capture, all angle/scope/stage controls, reload views, zoom, local links, desktop/mobile layout, and saves browser screenshots. It closes only its own isolated browser session.

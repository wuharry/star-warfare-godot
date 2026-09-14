# Thunder v4 actual detail comparison

The preview loads the production Thunder scene through `WarfarePlayer` and the existing animation fixture. It preserves the user's real save by redirecting `GameState.save_path` before creating players, then checks the original file SHA-256 at exit. Every material/shader/texture resource used by visible armor is hashed. No bitmap compositing, substitute armor materials, or model scaling is used.

Capture v3 **before** replacing `assets/armors/thunder/thunder.scn`:

```powershell
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility res://tools/thunder_detail_preview/capture.tscn -- --stage=baseline
```

After building and importing the final v4 scene:

```powershell
& '.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe' --path . --rendering-method gl_compatibility res://tools/thunder_detail_preview/capture.tscn -- --stage=current
python tools/thunder_detail_preview/build_preview.py
```

Each stage writes 30 native PNGs: five full-body and five helmet angles, seven localized detail crops rendered directly at 1200 × 1440, one armed idle, nine moving reload frames, and three gameplay captures at 1600 × 900. Baseline and current both use 4× MSAA and identical studio lights; current framing reuses baseline bounds. The third gameplay frame adds a low-front inspection camera inside the actual level 3 scene; it does not claim to be the normal player camera.

The current capture requires `thunder_detail_v4` on all four parts, also checked in both gameplay levels. The reference concept is copied byte-for-byte. Header reference cropping is CSS-only; clicking opens the complete original image. The model's rear is reviewed against original SW2 geometry, because the supplied concept does not depict its back. Neither capture success nor browser success constitutes complete visual equivalence.

The final design enlarges the visor opening, keeps the diagonal upper border and central brow drop, wraps the lower border around the face following the v3 prototype, retains the curved visor channels, and pulls the respirator thickness inward. These are design changes to compare visually; the report makes no claim of identical proportions. The helmet's fully opaque painted atlas covers its front and rear consistently.

The final helmet's original SW2 texture channels are loaded through byte-preserving Godot `ImageTexture` `.res` resources. In the source files, alpha stores material data; the normal Godot PNG alpha-border correction can alter valid RGB texels. The capture manifest hashes the actual `.res` resources sampled by the shader, along with the production shader, scene and other armor textures.

After reviewing final native images:

```powershell
python tools/thunder_detail_preview/build_preview.py --publish
```

This produces `docs/art/thunder_detail_v4/index.html`, with baseline/current frames, original reference, and manifests. Publishing rejects a capture when the production scene or any captured material resource has changed. It leaves the historical v3 report intact.

When the source audit's four selected SW2 renders are present, the builder also copies their exact PNG bytes into a clearly labelled source-reference section. These images use the original extracted SW2 geometry with its correctly paired diffuse, normal and light textures in Blender. They are not represented as Godot captures or as the final reconstructed armor. Source mapping details remain in `assets/armors/thunder/source_sw2/README.md`.

For the browser check, start an isolated headless Edge/Chrome with remote debugging port 19447 and its own temporary profile, then run `node tools/thunder_detail_preview/check_preview.mjs` (`--published` checks the documentation copy). The checker verifies all native images, comparison controls, motion and gameplay galleries, zoom, local links, desktop/mobile overflow, and JavaScript errors; its browser is closed on completion.

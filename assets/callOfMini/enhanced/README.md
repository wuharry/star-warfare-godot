# Enhanced Call of Mini armor pack

This directory contains the eight restored Call of Mini armor models in a
Godot-ready, non-destructive layout. The ZIP archives one directory above are
kept unchanged.

Each armor folder contains:

- the original `.dae` mesh with its existing UV coordinates and texture names;
- a matching `.tscn` scene with Godot-ready double-sided, anisotropic,
  baked-lighting-safe material overrides (use this scene in the game);
- `armor.png`, `equip.png`, and `helmet.png` as 1024 x 1024 RGBA textures;
- a `source/` directory containing the untouched 128 x 128 / 256 x 256 atlas
  sources. Godot ignores this comparison directory.

`equip.png` and `helmet.png` were restored as high-resolution stylized
hard-surface armor, using the active `armor_textures` corpus as the visual
reference. The final pass blends the restoration with the original atlas and
always copies alpha from the source, so transparent padding and UV-island edges
remain deterministic. The shared 128 x 128 under-suit `armor.png` is resized
without generative repainting because inventing geometry in that sparse atlas
would be less UV-safe.

The final images are 1K assets, not native 1K captures. Their extra painted
surface information improves close-up readability, while the original mobile
meshes remain intentionally low-poly.

The finishing utility is `tools/callofmini_enhancer/postprocess.gd`. It accepts
an original atlas, an optional restored atlas, and an output path:

```sh
godot --headless --path . \
  --script res://tools/callofmini_enhancer/postprocess.gd -- \
  --source=/absolute/path/source.png \
  --generated=/absolute/path/restored.png \
  --output=/absolute/path/final.png \
  --size=1024 --blend=0.72
```

Run `tools/callofmini_enhancer/build_scenes.gd` after reimporting the DAE files
to regenerate the ready-to-use `.tscn` wrappers.

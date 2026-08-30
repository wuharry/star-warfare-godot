# Legacy Unity YAML Mesh converter

This is the no-Unity fallback converter for the text-serialized Mesh assets in
Star Warfare. It supports the project's uncompressed Unity 2017
`serializedVersion: 8` layout, including separated/interleaved vertex streams,
16/32-bit index buffers, submeshes, UVs, and normals. It applies the transform
hierarchy from each prefab and converts Unity's handedness to Godot while fixing
triangle winding.

Run the selected restoration from the repository root:

```powershell
python Godot/tools/yaml_mesh_converter/convert.py selected --project-root .
```

This resolves mesh, material, and diffuse-texture GUIDs and writes:

- `Godot/assets/models/enemies/bug01.obj`
- `Godot/assets/models/weapons/gun00.obj`
- `Godot/assets/models/player/player.obj`

Each OBJ has an adjacent MTL and copied diffuse PNG files. The command also runs
the strict built-in OBJ validator and records its results in
`conversion_report.json`.

Other commands:

```powershell
python Godot/tools/yaml_mesh_converter/convert.py prefab Assets/Resources/weapon/gun00.prefab out.obj --assets-root Assets
python Godot/tools/yaml_mesh_converter/convert.py mesh Assets/Mesh/polySurface154.asset out.obj
python Godot/tools/yaml_mesh_converter/convert.py validate out.obj
```

## Deliberate limits

- OBJ is a static default-pose format. Skeletons, skin weights, blend shapes,
  and animation clips are not exported.
- The old custom shaders are reduced to MTL diffuse materials. In two-texture
  light shaders, `_texBase` is treated as diffuse and `_tex2` is not copied.
- Compressed Unity meshes and serialized versions other than 8 fail loudly
  instead of producing guessed geometry.
- When a source lacks normals (as the selected assets do), the converter creates
  area-weighted smooth normals. Existing normals are preserved and transformed.

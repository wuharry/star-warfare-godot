# Isolated Unity 6 OBJ exporter

This tool converts selected legacy Unity 2017 assets without opening or changing the original `Assets` directory. It creates a unique project below the Windows temporary directory, follows serialized Unity GUID references, copies only the required dependency closure, omits legacy code/plugins/shaders, and runs Unity 6000.1.10f1 in batch mode.

## Run

From PowerShell 7:

```powershell
cd Godot/tools/unity_exporter
./Run-Export.ps1
```

Unity must have an active Personal or Pro editor license on the machine. Use `-KeepTemp` to retain the isolated project for inspection, or override `-UnityPath`, `-SourceProject`, and `-OutputPath` when needed.

Successful output is written to `Godot/assets/models/legacy_unity/`:

- `level1_static.obj` — enabled Level1 `MeshRenderer`s carrying Unity static flags, with world transforms baked.
- `bug01.obj` and `gun00.obj` — enabled model renderers from the matching prefabs.
- `player.obj` — the visible default Player prefab, when importable.
- `armor01.obj` — the 01 avatar set assembled from Body, Hand, Foot, Head, and Bag prefabs, when importable.
- Matching `.mtl` files, deduplicated main textures below `textures/`, `export_report.json`, and `validation.json`.

Unity coordinates are converted as `(x, y, z) -> (x, y, -z)`. Object transforms are baked into the OBJ vertices, normals use the inverse-transpose transform, mirrored winding is corrected, UVs are retained, and `SkinnedMeshRenderer.BakeMesh` captures the currently loaded pose.

## Checks and isolation

`Run-Export.ps1` runs `Validate-Exports.ps1` before and after copying results. The validator checks non-empty geometry, face indices, MTL definitions, and every referenced texture. A license-independent C# API compile check is also available:

```powershell
./Test-Compile.ps1
```

`Prepare-IsolatedProject.ps1` can be run separately for inspection. Its `isolated-copy-manifest.json` records every copied or deliberately excluded asset. Unity upgrade writes occur only inside the temporary copy; no script in this directory writes beneath the original Unity `Assets` tree.

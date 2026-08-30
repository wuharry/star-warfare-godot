# Legacy animated avatar exporter

This converter rebuilds the original player Skeleton, skin weights, bind poses,
materials, and selected weapon-specific animation clips directly from the
text-serialized Unity assets. It writes a standard glTF 2.0 scene which Godot
imports without requiring a Unity installation or license.

```powershell
python tools/unity_avatar_exporter/export.py `
  --project-root E:\Star-Warfare-1.0.2\Star-Warfare-1.0.2 `
  --output assets/models/player/animated/player.gltf
```


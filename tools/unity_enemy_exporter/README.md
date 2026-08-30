# Legacy animated enemy exporter

Rebuilds a text-serialized Unity enemy prefab's hierarchy, skin, materials and
the animation clips referenced by its legacy `Animation` component as glTF 2.0.

```powershell
python tools/unity_enemy_exporter/export.py --project-root E:\Star-Warfare-1.0.2\Star-Warfare-1.0.2 --prefab Resources\enemy\bug01.prefab --output assets\models\enemies\animated\bug01\bug01.gltf
```

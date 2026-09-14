# Thunder concept v3 — verification

Validated on 2026-09-14 with Blender 5.1 and Godot 4.7.2, Compatibility/OpenGL on RTX 4080 Laptop GPU. Runtime scene: `assets/armors/thunder/thunder.scn`; all four parts carry `thunder_concept_v3`.

| Check | Result |
| --- | --- |
| Blender export and Godot compile | PASS; 4 parts, 28 named skeleton binds |
| Compiler malformed-input checks | PASS; 9 cases |
| Thunder character, skin weights, materials, mixed equips, animation, store/customize | PASS |
| New atlas paths and full visor UV coverage in the actual player | PASS |
| Other armor and weapon refinement regression | PASS; 27 armor sets, 85 weapon meshes |
| Armor purchase/save system | PASS |
| Equipment menu | PASS; 6 tabs, 141 armor entries, 47 weapons |
| Store thumbnails | 4 Thunder images rendered from the final meshes |
| Runtime comparison | 20 archived before + 20 final frames; player save unchanged |
| Texture import | 6 dedicated 1254² PNGs, lossless, mipmaps disabled |

The final capture manifest records the exact scene, two shader and six texture SHA-256 hashes. The [offline comparison](../thunder_concept_v3/index.html) includes front, three-quarter, side and rear views, helmet closeups, held weapon, moving reload and two actual game levels. Current captures use the game's high preset with 4× MSAA; the archived baseline used the SubViewport default without MSAA.

Visual review corrected open jaw surfaces, intersecting crown plates, duplicated source paint under raised shells, source-face winding and redundant shoulder seam walls. Read-only body diagnostics verified all 1,306 retained source surface triangles/fragments kept their winding, with no tiny triangles or invalid normals. Four coincident knee-junction edges remain in otherwise closed added components; this is not a claim of a single globally manifold mesh.

The result follows the reference's rounded head silhouette, long crown spine, warm V aperture and layered blue armor. Panel outlines, respirator details and painted highlights remain an interpretation of the image. The unseen back is an extension of that design, not a separately supplied reference. Technical and browser passes establish working integration and a reviewable comparison, not a numerical percentage of visual identity.

Some existing capture shutdowns log RID/ObjectDB cleanup warnings. They did not change the capture result or the original save. The unrelated reference-import worktree changes were not part of this change.

# Thunder detail v4 — verification

Validated on 2026-09-15 with Blender 5.1 and Godot 4.7.2, Compatibility/OpenGL on RTX 4080 Laptop GPU. Runtime scene: `assets/armors/thunder/thunder.scn`; four parts carry `thunder_detail_v4`.

| Check | Result |
| --- | --- |
| Blender export / Godot compile | PASS; 12,694 triangles, four parts, 28 named binds |
| Compiler input rejection | PASS; 12 valid/malformed cases, including tangent frames |
| Thunder mesh / rig / mixed equipment / animation / store | PASS |
| Four helmet runtime textures equal raw PNG texels | PASS, including transparent RGB; no mipmaps or lossy image-channel compression |
| Other armor and weapons | PASS; 27 armor sets, 85 weapon meshes |
| Armor purchase / save system | PASS |
| Equipment menu | PASS; six tabs, 141 armor entries, 47 weapons |
| Thunder thumbnails | Four images rendered from the current model |
| Runtime capture | 30 matched baseline + 30 current images; current run preserves original save SHA-256 |

The paired SW2 source fixes the old mesh/atlas mismatch. The original 974 head triangles receive one linear subdivision before controlled front deformation. This preserves original rear shape and UV islands while giving the enlarged visor/lower contour enough vertices to bend. The final head has 6,316 triangles including the ribbed neck socket and recessed respirator; body/arms/legs have 3,628 / 980 / 1,770.

User feedback is incorporated into the final contour: larger amber aperture, diagonal upper brow with descending central spine, rounded lower wrap and inset respirator. The mouth housing projection relative to its mount plane is reduced 56%; its intake, louvres and bevels remain geometric. Original back panels/vents retain the source topology, with coherent opaque repainting across the entire atlas. Fine visor engravings use the original tangent-space normal map as well as the atlas paint; they are not claimed to be individually sculpted mesh grooves.

Visual inspection covers front, three-quarter, side, back, low front, seven close-up details, armed idle, moving reload and levels 1/3. The HTML labels original SW2 Blender renders separately from actual Godot output. The scene/material/texture hashes are captured in its manifests. This supports review of the actual integration, not a numerical claim of identity to one concept image.

The capture tool redirects its own save path before creating players. An intermediate scratch capture saw the real save change while the user had the editor/game open; no backup was restored and no user progress was overwritten. The final current capture records an unchanged original-save hash.

Existing broad equipment tests still report fallback to texture paths for old weapon UIDs. Save recovery tests intentionally exercise invalid test-save backups. These do not affect the Thunder assertions. User `.vscode` and unrelated reference-import edits are excluded from this change.

See [runtime details](../../../assets/armors/thunder/README.md), [source provenance](../../../assets/armors/thunder/source_sw2/README.md), [image prompts](../../../assets/armors/thunder/helmet_texture_prompt.txt), and [interactive comparison](../thunder_detail_v4/index.html).

## SW2 crown rounding — 2026-09-16

The upper shell now follows a rounded dome instead of a compressed crest. The accepted visor, cheek plates and respirator (324 triangles on material slots 12–14) retain exactly the same positions, normals, tangents, UVs and skin weights. Body, arms, legs and prototype B remain unchanged. Godot front, three-quarter, side and in-level captures were reviewed; updated A/B images are in [the comparison page](../thunder_helmet_comparison_v5/index.html).

## Further SW2 respirator inset — 2026-09-16

The default SW2 respirator depth is reduced from 0.44 to 0.24 of the authored depth, moving its foremost face inward by 18.2 mm in model space. The intake, louvres and side bevels compress together. A local recess in the concealed original blue chin mounting ridge prevents it from breaking through the intake. The amber visor, rounded crown, body and prototype B remain unchanged. This supersedes the respirator position in the preceding crown-only update.

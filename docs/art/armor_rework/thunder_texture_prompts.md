# Thunder concept rebuild — UV texture prompts

2026-09-14. Four separate edits using the built-in `imagegen` tool. All four original atlases and the exact approved concept were viewed before editing. Each call used its corresponding UV atlas as image 1 and the concept as image 2, for surface-style reference only.

The existing `equipment_refined` textures were not overwritten. Dedicated Thunder copies allow the new model to use the new painted finish without changing other armor.

| Part | Selected workspace asset | Actual native size |
| --- | --- | --- |
| body | `assets/armors/thunder/textures/dce7a1446714.png` | 1254 × 1254 |
| shoulder | `assets/armors/thunder/textures/d6da6925f6b4.png` | 1254 × 1254 |
| arms | `assets/armors/thunder/textures/df2d0a0b46da.png` | 1254 × 1254 |
| legs | `assets/armors/thunder/textures/14ceb45bf36d.png` | 1254 × 1254 |

The prompt requested 2048² if possible, but the built-in tool returned 1254² for all four images. These are native generated outputs; no upscaling, downscaling, compositing, filtering or pixel edits were performed outside imagegen. They match the input pixel dimensions, with repainting rather than a larger numerical resolution.

## Review and limitations

- All four complete outputs were visually inspected. Main UV island arrangement, yellow insert locations, blue panel boundaries and dark joint fabric remain visually aligned with the originals. Panel facets, inset borders and fine chipped edges are clearer. Atlas review does not establish pixel-perfect UV invariance; wrapped model review is still required.
- Body, shoulder and legs were returned as RGBA with transparent unused regions; arms was returned as RGB with the gray unused background. The production armor shader must remain opaque and sample RGB only. Alpha should not be enabled for these hard armor materials.
- No new head UV atlas was produced here: the rebuilt helmet uses separately authored geometry/material mapping.
- Final runtime color and visible wear should be reviewed with the final rebuilt mesh, camera and material settings. These generated files alone do not prove exact concept reproduction.
- Generation diagnostics and file hashes are in the local `test_output/thunder_concept_audit/texture_generation.json`. Original generated cache files remain intact.

## New helmet shell paint

Built-in imagegen also generated `assets/armors/thunder/textures/blue_shell_paint.png` (1254 × 1254). The exact concept was viewed and supplied as a style reference. The generated swatch is mapped onto the new helmet shells; it does not reuse the incompatible old head atlas.

Prompt: Create one seamless square 1024x1024 diffuse color texture tile for the blue painted armor in the attached Thunder character reference. Only a completely flat material swatch filling the image edge to edge, NO character, NO helmet, NO panels, NO distinct large cracks, NO borders or vignettes. Muted steel cobalt/navy blue painted metal matching the medium blue upper helmet and chest; average sRGB approx #315878. Stylized hand-painted game art, fine restrained irregular brush mottling, occasional extremely faint short hairline scuffs, delicate cloudy blue pigment variation. Matte, non-plastic. Uniform diffuse illumination, no baked directional highlights, no reflected objects, no cast shadows. Low contrast detail so real curved geometry will carry highlights. Seamless repeat all edges. This texture will be directly mapped onto the newly modeled helmet and armor shell.

## Curved visor paint

Built-in imagegen generated `assets/armors/thunder/textures/amber_visor_paint.png` at 1254 × 1254. It is mapped continuously across the new curved aperture using explicit grid UVs; the bitmap contains no silhouette or armor geometry.

Prompt: Generate one square flat diffuse texture map for the amber visor glass of the attached Thunder armor reference. This is a technical bitmap texture to UV-map onto an already modeled curved V-shaped visor, so fill the ENTIRE SQUARE with glass color; do NOT draw a V silhouette or a helmet, no borders, no transparency, no objects, no text. Match the reference's warmly luminous yellow-gold face aperture: pale golden yellow center (#ffdd63), golden honey yellow upper center, warm rich amber-orange shading toward left and right edges and narrow bottom edge. Restrained hand-painted subtle broad angular/faceted tonal variation within the amber glass, softened transitions, no grains, no scratches, no reflections of objects. Keep central 70 percent clearly bright YELLOW GOLD, not mustard brown or solid orange. Top corners amber, side edges orange, middle light gold. Almost uniform enough for wrapping across a small game visor, but with readable painted depth. Square 1024x1024 surface-color texture, no fake 3D frame.

## body

- Edit target: `assets/equipment_refined/textures/dce7a1446714.png`
- Style reference: `docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png`
- Generated source: `C:\Users\whw88\.codex\generated_images\01a0a03f-ed66-7051-a881-ea9fea8d1352\exec-26cba8f4-5e28-4610-afe8-f19932870503.png`
- Selected output: `assets/armors/thunder/textures/dce7a1446714.png`

Exact prompt:

```text
Use case: precise-object-edit. Asset type: a production square flat UV albedo texture for an existing stylized game armor mesh. Image 1 is the edit target. Image 2 is ONLY a reference for painted surface finish and the steel-blue / warm-yellow color family, not a layout or subject to reproduce. Repaint Image 1 in high-definition at 2048 by 2048 if possible, retaining its ENTIRE square UV atlas exactly: every island silhouette, placement, relative scale, seam, connector, yellow insert and gray unused region stays fixed. Keep all dark cloth/rubber areas and their boundaries. Refine fuzzy painted borders into crisp fine edged material transitions and fine irregular edge wear, deepen narrow seams, add restrained large clean facet shading within existing blue panels. Match the reference's matte, hand-painted dark steel-blue armor and warm golden-yellow insets, dark brown-black quilted joint fabric. Remove coarse cloth-like grain from blue metal panels. Keep fine wear localized to existing armor edges; no excessive random scratches or broad white outlines. DO NOT invent new panel lines, bolts, symbols, islands, lighting highlights, logos or text. DO NOT render a 3D armor, a mannequin, concept art, perspective or shadows behind the UV islands. Return only the complete flat square UV atlas, edge-to-edge, preserving the original layout precisely. Specific edit target: torso/chest/waist atlas. Preserve the existing two horizontal yellow bars at upper right, chest yellow tabs and waist V emblem at lower left. Keep ribbed dark undersuit readable with clean stitched bands.
```

## shoulder

- Edit target: `assets/equipment_refined/textures/d6da6925f6b4.png`
- Style reference: `docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png`
- Generated source: `C:\Users\whw88\.codex\generated_images\01a0a03f-ed66-7051-a881-ea9fea8d1352\exec-833be1d3-293a-4ab7-ba23-f784a3f3bd5f.png`
- Selected output: `assets/armors/thunder/textures/d6da6925f6b4.png`

Exact prompt:

```text
Use case: precise-object-edit. Asset type: a production square flat UV albedo texture for an existing stylized game armor mesh. Image 1 is the edit target. Image 2 is ONLY a reference for painted surface finish and the steel-blue / warm-yellow color family, not a layout or subject to reproduce. Repaint Image 1 in high-definition at 2048 by 2048 if possible, retaining its ENTIRE square UV atlas exactly: every island silhouette, placement, relative scale, seam, connector, yellow insert and gray unused region stays fixed. Keep all dark cloth/rubber areas and their boundaries. Refine fuzzy painted borders into crisp fine edged material transitions and fine irregular edge wear, deepen narrow seams, add restrained large clean facet shading within existing blue panels. Match the reference's matte, hand-painted dark steel-blue armor and warm golden-yellow insets, dark brown-black quilted joint fabric. Remove coarse cloth-like grain from blue metal panels. Keep fine wear localized to existing armor edges; no excessive random scratches or broad white outlines. DO NOT invent new panel lines, bolts, symbols, islands, lighting highlights, logos or text. DO NOT render a 3D armor, a mannequin, concept art, perspective or shadows behind the UV islands. Return only the complete flat square UV atlas, edge-to-edge, preserving the original layout precisely. Specific edit target: shoulder cap atlas. Preserve the three large islands, the central slotted round fastener, all five yellow insets and existing panel boundary geometry. Make blue panels clean painted metal with subtle bevel edge accents.
```

## arms

- Edit target: `assets/equipment_refined/textures/df2d0a0b46da.png`
- Style reference: `docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png`
- Generated source: `C:\Users\whw88\.codex\generated_images\01a0a03f-ed66-7051-a881-ea9fea8d1352\exec-ff4d2b8e-7aa5-47b2-b122-bb61e92c85a7.png`
- Selected output: `assets/armors/thunder/textures/df2d0a0b46da.png`

Exact prompt:

```text
Use case: precise-object-edit. Asset type: a production square flat UV albedo texture for an existing stylized game armor mesh. Image 1 is the edit target. Image 2 is ONLY a reference for painted surface finish and the steel-blue / warm-yellow color family, not a layout or subject to reproduce. Repaint Image 1 in high-definition at 2048 by 2048 if possible, retaining its ENTIRE square UV atlas exactly: every island silhouette, placement, relative scale, seam, connector, yellow insert and gray unused region stays fixed. Keep all dark cloth/rubber areas and their boundaries. Refine fuzzy painted borders into crisp fine edged material transitions and fine irregular edge wear, deepen narrow seams, add restrained large clean facet shading within existing blue panels. Match the reference's matte, hand-painted dark steel-blue armor and warm golden-yellow insets, dark brown-black quilted joint fabric. Remove coarse cloth-like grain from blue metal panels. Keep fine wear localized to existing armor edges; no excessive random scratches or broad white outlines. DO NOT invent new panel lines, bolts, symbols, islands, lighting highlights, logos or text. DO NOT render a 3D armor, a mannequin, concept art, perspective or shadows behind the UV islands. Return only the complete flat square UV atlas, edge-to-edge, preserving the original layout precisely. Specific edit target: forearm/glove atlas. Preserve the black quilted strip at top, large forearm guard island, the single gold tab, two round fasteners, two blue wrist tabs and small glove underside island. Keep worn blue plate edges thin and crisp.
```

## legs

- Edit target: `assets/equipment_refined/textures/14ceb45bf36d.png`
- Style reference: `docs/art/thunder_mk_comparison_v1/images/b_mk1_reference_helmet_v2.png`
- Generated source: `C:\Users\whw88\.codex\generated_images\01a0a03f-ed66-7051-a881-ea9fea8d1352\exec-b7c76faf-fab8-40fa-b435-e4d56ec67281.png`
- Selected output: `assets/armors/thunder/textures/14ceb45bf36d.png`

Exact prompt:

```text
Use case: precise-object-edit. Asset type: a production square flat UV albedo texture for an existing stylized game armor mesh. Image 1 is the edit target. Image 2 is ONLY a reference for painted surface finish and the steel-blue / warm-yellow color family, not a layout or subject to reproduce. Repaint Image 1 in high-definition at 2048 by 2048 if possible, retaining its ENTIRE square UV atlas exactly: every island silhouette, placement, relative scale, seam, connector, yellow insert and gray unused region stays fixed. Keep all dark cloth/rubber areas and their boundaries. Refine fuzzy painted borders into crisp fine edged material transitions and fine irregular edge wear, deepen narrow seams, add restrained large clean facet shading within existing blue panels. Match the reference's matte, hand-painted dark steel-blue armor and warm golden-yellow insets, dark brown-black quilted joint fabric. Remove coarse cloth-like grain from blue metal panels. Keep fine wear localized to existing armor edges; no excessive random scratches or broad white outlines. DO NOT invent new panel lines, bolts, symbols, islands, lighting highlights, logos or text. DO NOT render a 3D armor, a mannequin, concept art, perspective or shadows behind the UV islands. Return only the complete flat square UV atlas, edge-to-edge, preserving the original layout precisely. Specific edit target: shin/boot/knee atlas. Preserve both large connected islands, small sole islands, gold knee tab and both gold side inserts. Make shin armor clear steel-blue planar facets, maintain dark black boot rubber and all fine sole seams. Reduce the source's broad white scraped outlines to thin restrained edge wear like the reference.
```

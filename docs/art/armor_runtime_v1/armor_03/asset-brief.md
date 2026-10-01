# Hydra / original game proportions

ASSET CH_Hydra
CATEGORY modular human-worn armor
VIEWS docs/art/original_armors_v1/images/c04_concept.png + images/c04_turnaround.png; perspective concept defines shapes, not limb lengths
SCALE original game units, Y up, -Z forward; baseline helmet width .518, total height 1.912
PROPORTIONS head .676/1.912=.354; shoulder width 1.075/1.912=.562; pelvis .778/1.912=.407; knee .387/1.912=.202; neck 1.358/1.912=.710; hand .736/1.912=.385; ankle .137/1.912=.072; unchanged original bone coordinates
PARTS head: rigid head/neck; body: torso, pelvis, thighs, shoulders and upper arms; arms: forearms/gloves; legs: calves/boots
SILHOUETTE 保留藍綠圓冠、低分節冠條及綠框單方額頭裝置；黃綠連續面罩向下延伸並擴大，兩側下角收斜，下方改成短窄藍色護邊與貼合的小中央護片。; 小型藍肩和短外展綠片
MATERIALS [{'family': '中深藍', 'hex': '#426F99', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '黃綠', 'hex': '#9EAD66', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '黃綠玻璃', 'hex': '#BBC87D', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '黑棕', 'hex': '#282D29', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}]
ARTICULATION named original Bip01 skeleton; existing idle/run/shoot/reload; no new animation library
INFERRED ['armor panel depths and bevel widths', 'back panels hidden by independent backpacks', 'concept reshaped around original game skeleton; no 85% fidelity claim']
TARGET Godot 4.7, native .scn; provisional <=8000 tris, one opaque vertex-color material, 128px gameplay character

# Pegasus / original game proportions

ASSET CH_Pegasus
CATEGORY modular human-worn armor
VIEWS docs/art/original_armors_v1/images/c09_concept.png + images/c09_turnaround.png; perspective concept defines shapes, not limb lengths
SCALE original game units, Y up, -Z forward; baseline helmet width .518, total height 1.912
PROPORTIONS head .676/1.912=.354; shoulder width 1.075/1.912=.562; pelvis .778/1.912=.407; knee .387/1.912=.202; neck 1.358/1.912=.710; hand .736/1.912=.385; ankle .137/1.912=.072; unchanged original bone coordinates
PARTS head: rigid head/neck; body: torso, pelvis, thighs, shoulders and upper arms; arms: forearms/gloves; legs: calves/boots
SILHOUETTE 與身甲一致的白灰頭盔，配深色淺 V 玻璃、雙低眉尖與分層護頰；冠頂、側殼、下巴與後殼統一白灰。; 白灰寬肩分層，縮短尖端便於抬臂
MATERIALS [{'family': '白灰', 'hex': '#D5DADB', 'target_percent': None, 'usage': '頭盔外殼與身甲共用白灰主色；依 2026-09-29 使用者更正。色票是美術近似值，不是圖像取樣或 UV 材質值。'}, {'family': '深藍黑', 'hex': '#253848', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '藍', 'hex': '#517EA8', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}]
ARTICULATION named original Bip01 skeleton; existing idle/run/shoot/reload; no new animation library
INFERRED ['armor panel depths and bevel widths', 'back panels hidden by independent backpacks', 'concept reshaped around original game skeleton; no 85% fidelity claim']
TARGET Godot 4.7, native .scn; provisional <=8000 tris, one opaque vertex-color material, 128px gameplay character

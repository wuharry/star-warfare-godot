# Strike / original game proportions

ASSET CH_Strike
CATEGORY modular human-worn armor
VIEWS docs/art/original_armors_v1/images/c05_concept.png + images/c05_turnaround.png; perspective concept defines shapes, not limb lengths
SCALE original game units, Y up, -Z forward; baseline helmet width .518, total height 1.912
PROPORTIONS head .676/1.912=.354; shoulder width 1.075/1.912=.562; pelvis .778/1.912=.407; knee .387/1.912=.202; neck 1.358/1.912=.710; hand .736/1.912=.385; ankle .137/1.912=.072; unchanged original bone coordinates
PARTS head: rigid head/neck; body: torso, pelvis, thighs, shoulders and upper arms; arms: forearms/gloves; legs: calves/boots
SILHOUETTE 鋼藍分節圓冠、雙青色冠環；Atom＋Recruit 青色連續面罩向下收窄，底中央留小凹口，短下巴與收口頰甲。; 圓肩外殼與較短下層肩片；青色圓節點集中
MATERIALS [{'family': '鋼藍', 'hex': '#47749C', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '青色', 'hex': '#52C7CE', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '胸片金色', 'hex': '#DDB44A', 'target_percent': None, 'usage': '保留胸甲中央小金片；本輪頭盔玻璃改為青色，色票為美術近似值。'}, {'family': '深色內襯', 'hex': '#24282E', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}]
ARTICULATION named original Bip01 skeleton; existing idle/run/shoot/reload; no new animation library
INFERRED ['armor panel depths and bevel widths', 'back panels hidden by independent backpacks', 'concept reshaped around original game skeleton; no 85% fidelity claim']
TARGET Godot 4.7, native .scn; provisional <=8000 tris, one opaque vertex-color material, 128px gameplay character

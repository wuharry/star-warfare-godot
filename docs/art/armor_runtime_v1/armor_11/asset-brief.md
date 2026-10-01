# Cygni / original game proportions

ASSET CH_Cygni
CATEGORY modular human-worn armor
VIEWS docs/art/original_armors_v1/revisions/c12_helmet_fusions_20260929/images/anubis_gold_t_swept.png + images/c12_turnaround.png; perspective concept defines shapes, not limb lengths
SCALE original game units, Y up, -Z forward; baseline helmet width .518, total height 1.912
PROPORTIONS head .676/1.912=.354; shoulder width 1.075/1.912=.562; pelvis .778/1.912=.407; knee .387/1.912=.202; neck 1.358/1.912=.710; hand .736/1.912=.385; ankle .137/1.912=.072; unchanged original bone coordinates
PARTS head: rigid head/neck; body: torso, pelvis, thighs, shoulders and upper arms; arms: forearms/gloves; legs: calves/boots
SILHOUETTE Anubis 融合分層眉甲、內收白灰護頰與短中央下巴；金色面罩上方寬、下方收成中等寬中央直條，呈輕微 T 字；保留雙側短後掠翼。; 雙肩各一短鈍翼，呼應頭盔側翼
MATERIALS [{'family': '白灰', 'hex': '#D8DCDA', 'target_percent': None, 'usage': '依使用者更正，頭盔外殼、側翼與身甲共用白灰主色；美術近似色票，非圖像取樣或 UV 材質值。'}, {'family': '深綠', 'hex': '#344D40', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '銅橙', 'hex': '#BA7D57', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '反光金色玻璃', 'hex': '#CBA44D', 'target_percent': None, 'usage': '使用者採用的金色微 T 面罩；近似美術色票，非圖像取樣或 UV 材質值。'}]
ARTICULATION named original Bip01 skeleton; existing idle/run/shoot/reload; no new animation library
INFERRED ['armor panel depths and bevel widths', 'back panels hidden by independent backpacks', 'concept reshaped around original game skeleton; no 85% fidelity claim']
TARGET Godot 4.7, native .scn; provisional <=8000 tris, one opaque vertex-color material, 128px gameplay character

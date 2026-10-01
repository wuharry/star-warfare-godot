# Fortune / original game proportions

ASSET CH_Fortune
CATEGORY modular human-worn armor
VIEWS docs/art/original_armors_v1/images/c02_concept.png + images/c02_turnaround.png; perspective concept defines shapes, not limb lengths
SCALE original game units, Y up, -Z forward; baseline helmet width .518, total height 1.912
PROPORTIONS head .676/1.912=.354; shoulder width 1.075/1.912=.562; pelvis .778/1.912=.407; knee .387/1.912=.202; neck 1.358/1.912=.710; hand .736/1.912=.385; ankle .137/1.912=.072; unchanged original bone coordinates
PARTS head: rigid head/neck; body: torso, pelvis, thighs, shoulders and upper arms; arms: forearms/gloves; legs: calves/boots
SILHOUETTE 暗綠低圓冠、連續鋼藍眉框與低位深紫面窗；寬斜切鋼藍護頰、側頰斜通風口、中央綠色護片與封閉短下顎。取消額前中央黑徽槽、鼻部凸塊和原方下巴 U 形缺口。; 低圓鋼藍肩殼配綠色下緣
MATERIALS [{'family': '暗綠', 'hex': '#475E45', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '鋼藍', 'hex': '#6B8397', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '深紫玻璃', 'hex': '#554458', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '黑棕', 'hex': '#29272A', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}]
ARTICULATION named original Bip01 skeleton; existing idle/run/shoot/reload; no new animation library
INFERRED ['armor panel depths and bevel widths', 'back panels hidden by independent backpacks', 'concept reshaped around original game skeleton; no 85% fidelity claim']
TARGET Godot 4.7, native .scn; provisional <=8000 tris, one opaque vertex-color material, 128px gameplay character

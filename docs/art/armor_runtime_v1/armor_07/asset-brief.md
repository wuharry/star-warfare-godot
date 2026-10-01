# Atom / original game proportions

ASSET CH_Atom
CATEGORY modular human-worn armor
VIEWS docs/art/original_armors_v1/images/c08_concept.png + images/c08_turnaround.png; perspective concept defines shapes, not limb lengths
SCALE original game units, Y up, -Z forward; baseline helmet width .518, total height 1.912
PROPORTIONS head .676/1.912=.354; shoulder width 1.075/1.912=.562; pelvis .778/1.912=.407; knee .387/1.912=.202; neck 1.358/1.912=.710; hand .736/1.912=.385; ankle .137/1.912=.072; unchanged original bone coordinates
PARTS head: rigid head/neck; body: torso, pelvis, thighs, shoulders and upper arms; arms: forearms/gloves; legs: calves/boots
SILHOUETTE B＋Recruit 分片圓冠、淺 V 青色窄面罩與短收口下巴；保留 Atom 紫藍配色、三顆額冠青燈和圓耳機構。; 後掠雙尖片縮短為感測護片
MATERIALS [{'family': '紫', 'hex': '#66507F', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '鋼藍', 'hex': '#487098', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '青', 'hex': '#58CDD0', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '黑', 'hex': '#242632', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}]
ARTICULATION named original Bip01 skeleton; existing idle/run/shoot/reload; no new animation library
INFERRED ['armor panel depths and bevel widths', 'back panels hidden by independent backpacks', 'concept reshaped around original game skeleton; no 85% fidelity claim']
TARGET Godot 4.7, native .scn; provisional <=8000 tris, one opaque vertex-color material, 128px gameplay character

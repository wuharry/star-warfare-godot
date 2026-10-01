# Draco / original game proportions

ASSET CH_Draco
CATEGORY modular human-worn armor
VIEWS docs/art/original_armors_v1/images/c10_concept.png + images/c10_turnaround.png; perspective concept defines shapes, not limb lengths
SCALE original game units, Y up, -Z forward; baseline helmet width .518, total height 1.912
PROPORTIONS head .676/1.912=.354; shoulder width 1.075/1.912=.562; pelvis .778/1.912=.407; knee .387/1.912=.202; neck 1.358/1.912=.710; hand .736/1.912=.385; ankle .137/1.912=.072; unchanged original bone coordinates
PARTS head: rigid head/neck; body: torso, pelvis, thighs, shoulders and upper arms; arms: forearms/gloves; legs: calves/boots
SILHOUETTE 寬額低冠、細窄水平視孔、盾形不透明鐵灰面甲與收短下巴；煤灰側頰包框銜接小圓耳座，取消大片玻璃護目鏡與中央深色縱條。; 向外折肩板改平，增加短下層活動片
MATERIALS [{'family': '煤灰', 'hex': '#3A4147', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '鐵灰', 'hex': '#68727B', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '黑色內襯與暗凹槽', 'hex': '#1D2226', 'target_percent': None, 'usage': '黑色用於軟內襯、細窄視孔與接縫；正面為不透明鐵灰金屬面甲，不使用大片玻璃護目鏡。色票為美術近似值。'}]
ARTICULATION named original Bip01 skeleton; existing idle/run/shoot/reload; no new animation library
INFERRED ['armor panel depths and bevel widths', 'back panels hidden by independent backpacks', 'concept reshaped around original game skeleton; no 85% fidelity claim']
TARGET Godot 4.7, native .scn; provisional <=8000 tris, one opaque vertex-color material, 128px gameplay character

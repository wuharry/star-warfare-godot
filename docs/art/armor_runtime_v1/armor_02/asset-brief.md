# Tank / original game proportions

ASSET CH_Tank
CATEGORY modular human-worn armor
VIEWS docs/art/original_armors_v1/images/c03_concept.png + images/c03_turnaround.png; perspective concept defines shapes, not limb lengths
SCALE original game units, Y up, -Z forward; baseline helmet width .518, total height 1.912
PROPORTIONS head .676/1.912=.354; shoulder width 1.075/1.912=.562; pelvis .778/1.912=.407; knee .387/1.912=.202; neck 1.358/1.912=.710; hand .736/1.912=.385; ankle .137/1.912=.072; unchanged original bone coordinates
PARTS head: rigid head/neck; body: torso, pelvis, thighs, shoulders and upper arms; arms: forearms/gloves; legs: calves/boots
SILHOUETTE 保留原大面積橙金玻璃及中央下緣尖折、低分節藍冠條、雙鼠尾草綠冠條、厚眉和圓耳罩。中央向上尖起的護片改成實心鋼藍切面與底部短橫進氣口；兩側以斜向分件護頰覆在深色下顎軌上，維持 Tank 厚重且緊湊的臉部輪廓。; 厚藍肩加短上折綠護唇，降低外伸
MATERIALS [{'family': '鋼藍', 'hex': '#567D9D', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '鼠尾草綠', 'hex': '#93AD84', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '橙玻璃', 'hex': '#DE9B46', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}, {'family': '黑棕', 'hex': '#302E2C', 'target_percent': None, 'usage': '本輪原版配色身份的近似美術色票；不是圖像取樣或UV材質值。'}]
ARTICULATION named original Bip01 skeleton; existing idle/run/shoot/reload; no new animation library
INFERRED ['armor panel depths and bevel widths', 'back panels hidden by independent backpacks', 'concept reshaped around original game skeleton; no 85% fidelity claim']
TARGET Godot 4.7, native .scn; provisional <=8000 tris, one opaque vertex-color material, 128px gameplay character

# Titan 頭盔修正 brief

**本次只修正指定 Titan 頭盔，以大片金色玻璃與實際圓弧貼合草稿，同時保留原遊戲體格。**

- ASSET：Titan / C-06 / ID 5；rigged modular armor helmet。
- CATEGORY：角色裝甲中的剛性頭盔；與原頭部骨架、頸部接縫相容。
- VIEWS：指定圖為全身斜視概念，非正交圖。估計相機方位約 25–35°，僅作造型參考，不以成人身體比例量測遊戲尺寸。比對圖使用真正 Godot 相機與同一模型。
- SCALE：以凍結原 source 的 Godot 單位為準。原頭部寬／高／深約 0.63822 / 0.67258 / 0.59944；本版約 0.55837 / 0.67239 / 0.59945。沒有另定真實公尺身高。
- PROPORTIONS：頭部高／角色高約 0.347；主要體格由原骨架決定，肩／四肢維持原件。單張透視概念不提供可驗證的多視角像素尺寸或 silhouette IoU。
- PARTS：主頭殼、玻璃視域、外圍護框、側扣、頸部接縫；維持一個原模組、一個材質 surface 與三個連續 UV 區域。
- SILHOUETTE：玻璃延伸到上額；前緣鼓起；上弧有少量新增頂點；短淺護框；耳部收小。
- MATERIALS：原版不透明、unlit、手繪 diffuse。藍色塗裝與金色玻璃感烘焙在貼圖內；不改成寫實 PBR。
- ARTICULATION：28 原骨架；原頂點 bind／weights 精確保留，新弧線中點沿用相同父邊權重。原武器／背包掛點與待機、跑動、換彈共用。
- INFERRED：側後方深度、不可見接縫依原件推測。保留原低多邊形折面，不宣稱概念完整還原。
- TARGET：Godot 4.7.2 / Compatibility；正式 SCN、可攜 GLB、內嵌原生 PNG 的 Blender master。頭盔 132 tris / 302 UV 座標 / 3 charts；本次最多增加 10% 面數／座標。
- ACCEPTANCE：實際引擎正、斜、側、後與動作擷取；SCN、GLB、master、來源與完整 RGB 檢查。工程 PASS 和使用者美術接受分開記錄。

# Thunder 草稿風格：全裝甲新一輪概念

本輪為概念草稿；每套保留原裝甲配色與辨識特徵，以已選定的 Thunder 全身草稿統一美術表現。範圍是除 Thunder 外的 28 套，含 Viper、Fortune。草稿不直接套用遊戲模型或貼圖。

## 共用生成規格

Use case: stylized-concept / style-transfer. Generate ONE new full-body armor concept portrait. Input 1 (references/thunder_style.png) is the exact accepted THUNDER ART-STYLE reference ONLY: compact heroic proportions, large helmet, short sturdy limbs, thick angular overlapping armor plates, sharp readable bevels, restrained thin painted edge wear, subtle hand-painted surface variation, matte finish, dark ribbed flexible undersuit, soft neutral gray studio lighting and floor. Match this reference's high quality stylized painted game-art finish and weight; avoid glossy plastic, photoreal humans, cheap smooth CGI or a tall slender adult silhouette.

The OTHER input images are the target armor's ORIGINAL DESIGN AND COLOR authority. Preserve its primary/secondary paint colors, visor color, accent colors and their location/relative coverage, its distinctive helmet silhouette, face opening, chest motif and shoulder type. Do NOT copy Thunder's blue/yellow palette, helmet, respirator or shoulder design onto other sets. Re-engineer and refine the original suit with readable faceted plate thickness and layered joints in the Thunder art style. Keep each set recognizable, including unusual horns, crests or insignia only where the original has them. Dark materials must stay readable. Restrain tiny surface lines and wear; no random LEDs or invented color accents.

Composition: one complete character in a front three-quarter view, compact 4.5–5 head-heights proportions comparable to the Thunder image, strong grounded stance, feet separated and fully visible, arms relaxed slightly bent near the waist so chest and shoulders remain visible. Empty hands, no weapon or backpack, no cropped horns/boots. Plain soft gray studio backdrop with grounded shadow. Single portrait, approximately 4:5 aspect ratio, high native resolution. No extra panels, text, labels, watermark, UI or scenery. This is a new concept painting, not a UV atlas, not a recolored Thunder clone.

## 記錄方式

逐套輸出 `images/armor_NN.png`；完整實際 prompt 存在 `prompts/armor_NN.txt`。每套 `entries/armor_NN.json` 記錄 id、name、image、prompt、references、generated_source、sha256、dimensions、palette（繁體中文原配色摘要）、features（繁體中文保留特色）、review（實際檢視觀察）、status=`concept_pending_user_review`、tool=`built-in image_gen`。圖片只能直接複製內建 imagegen 選定成果，不做程式後製。參考圖片先查看；原配色以本輪 references 為準，不以舊 v2 概念圖為準。

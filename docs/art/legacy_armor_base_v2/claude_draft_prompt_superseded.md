# 已作廢：Claude 原稿的貼圖生成 prompt（2026-10-02 撤下）

這段在 docs/art/ARMOR_TEXTURE_STYLE_SPEC.md 的初版正文裡，現已移出，只留作對照。
不要拿它生成——三條限制經全 21 套實測證明是錯的：

1. "Fill all negative space with the set's dominant dark base colour"
   底色不固定：18 Black Hole 的 body atlas 底是純白 (255,255,255)、head 是
   淺灰 (170,178,186)，02 Tank 是全黑，00 Viper 是深藍。
2. "Highlights are ... never white speculars" 與 "98% of pixels must stay below 0.75"
   p98 明度跨 21 套的實測範圍是 0.416–1.000，中位 0.745。18 Black Hole 達 1.0。
3. "one dominant hue carrying about 90%" 與 "accent ... never on large plates"
   色相集中度實測 17.2%–100%；03 與 16 是刻意多色，14 Chaos、19 X-Field 有大片鮮色甲片。

現行版本見 ARMOR_TEXTURE_STYLE_SPEC.md 的「整合基底 prompt」與 base_prompt.txt。

---

## Claude 原稿 Prompt（保留對照；生成請用下方整合版）

以下保留原稿便於比較，但固定亮度／色相、禁止白高光、固定黑色空島的限制已被上述檢查修正，**不要再直接拿這段生成**。概念圖從
[original_armors_v1/index.html](original_armors_v1/index.html) 取。

```text
Produce ONE square 512x512 UV diffuse texture atlas for a stylized third-person
shooter character armor part. Output the flattened atlas only — never a 3D
render, never a character, never a turnaround.

RENDERING CONTEXT (critical): this texture is drawn UNLIT. The engine applies
no lighting, no specular and no shadows; the texture IS the final on-screen
pixels. Paint the lighting into the texture: a key light from above and in
front, a 1-2 px lighter rim along each plate's upper edge, a soft gradient
darkening toward the lower edge, and recessed seams painted as dark bands.
This is a finished painted illustration, NOT a flat albedo map.

VALUE RANGE: keep the image dark. Mean pixel value should land near 0.22
(sRGB 0..1). At most 5% of pixels may exceed value 0.62, and 98% of pixels
must stay below 0.75. Highlights are a lighter shade of the base hue, never
white speculars.

PALETTE: one dominant hue carrying about 90% of the coloured pixels, plus a
single contrasting accent. The accent appears only on the visor, thin glow
strips and small indicator dots — never on large plates. A fully desaturated
greyscale set is also acceptable.

OPACITY: the atlas is 100% opaque. Fill all negative space with the set's
dominant dark base colour. No transparency, no checkerboard, no cutouts, no
drop shadow. Unused UV islands are painted flat black and left in place.

DETAIL SCALE: authored for 256x256 native resolution. Large plate divisions,
one or two grooves per plate, one glow strip. No rivets, no text, no logos, no
fine surface noise, no photoreal metal, no chrome.

TOUCH: hand-painted with restrained paint grain. Crisp plate edges, soft
interior gradients. Not vector-flat, not photographic.
```

接著補上這一套的具體內容，例如：

```text
SUBJECT: helmet (head) atlas for the armor shown in the attached concept art.
DOMINANT HUE: desaturated steel blue, base around #304050.
ACCENT: warm amber, used only on the visor band and two indicator dots.
Keep the silhouette, plate divisions and visor shape from the concept art.
```

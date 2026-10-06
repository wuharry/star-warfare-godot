# 原版裝甲風格與 AI 素材生成規格（Claude＋Codex 整合版）

**先用本頁末段的「整合基底 prompt」與「交給 sol6.1 的完整工作指令」；前面的統計用於參考，不是所有新裝甲都必須命中的數字。**

- 原版資料：SW 的全部 21 套、CoM 的全部 8 套；不是目前的 AI 精修貼圖或試作模型。
- 新造型資料：[概念圖總覽](original_armors_v1/index.html)。原版決定畫法與遊戲比例，新概念決定造型與配色分區。
- 證據：[全部模型與貼圖](legacy_armor_base_v2/README.md)、[逐檔清單與 SHA-256](legacy_armor_base_v2/inventory.json)、[Claude 統計複算](legacy_armor_base_v2/claude_statistics_check.json)。
- 本頁統計原稿由 Claude 提供；Codex 於 2026-10-02 複算並補入全部模型／貼圖分析、例外、生成與驗收方式。以下已修正過度推論，不以統計通過宣稱風格一致。

## 原版貼圖統計：適用範圍

生成新裝甲素材前先讀這份。所有數字由 `assets/models/player/animated/armor_textures/`
的 105 張原版貼圖實測得出（SW1 的 00–20 共 21 套，每套 5 個不同貼圖檔）。下方另有 CoM 原始資料與模型分析，兩組資料不混算。

## 原版 SW 的立體明暗主要畫在 diffuse 貼圖上

[armor_visuals.gd:100-126](../../scripts/game/armor_visuals.gd#L100) 把所有原版裝甲
材質設成 `SHADING_MODE_UNSHADED`。表面的明暗不靠一般燈光／PBR 高光計算，
因此需要把主要亮邊、陰影與反光畫進貼圖。貼圖仍放在 Godot 的 `albedo_texture` 欄位；
差別在畫法，並不是不能叫 albedo。材質 tint、取樣、色彩轉換仍會影響螢幕上的顏色，
也不能由 UNSHADED 推斷物件完全不會投射陰影。

所以給生圖模型的指令是「畫一張**已經打好光的成品插畫**」，不是「畫一張等著被打光的
基礎色貼圖」。兩者差別：

| | 只有底色的貼圖 | 原版的 painted diffuse |
| --- | --- | --- |
| 甲片表面 | 均勻平塗 | 上緣亮、下緣沉的漸層 |
| 邊緣 | 無 | 1–2 px 亮邊描在受光側 |
| 凹槽 | 無 | 直接畫成深色帶 |
| 整體亮度 | 中性 | 偏暗（見下） |

## 硬規格

| 項目 | 值 |
| --- | --- |
| 原生尺寸 | 256×256（repo 內為 `_2x` 兩倍放大的 512×512；5 張為 1024） |
| 每套件數 | 5：`head` / `body` / `jian`（肩）/ `hand` / `foot` |
| 通道 | RGBA，但**不透明度 100%**，105 張全部 coverage = 1.000 |
| 背景 | 不透明；可見黑、灰、白及主色底，不能一律規定主色或黑色 |
| 版面 | UV islands 直接攤在背景上，島與島之間沒有留白框線 |

不透明不等於固定背景色。例如 Black Hole 原圖有大塊白色底，Tank 有黑底。
重畫既有 UV 時保留其邊界、底色與留邊；不能把看似空白的區域自行挖透明。

## 亮度：原版比你想的暗很多

以「一整套 5 張」為單位統計（不是單張，單張差異太大：腳部幾乎全是底色，
頭部幾乎全是甲片）：

| 指標 | 最低 | 中位 | 最高 |
| --- | --- | --- | --- |
| 平均明度 | 0.140 | **0.224** | 0.412 |
| p98 明度（最亮的 2% 從哪裡開始） | 0.416 | **0.745** | 1.000 |
| 明度 > 0.62 的像素占比 | 0.1% | **5.0%** | 18.1% |

這是各欄分別計算的中位數，不一定來自同一套。`value` 是 HSV 的 V，也就是
`max(R,G,B)`；不是人眼感知亮度或線性光強。此處包含整張 atlas 的底色與未使用區域，
未乘材質 tint，也未按模型上實際可見面積加權。AI 圖「通常有多少亮像素」尚未建立樣本統計。

11、15、18 約有 15–18% 亮像素；19 實測約 8.9%。18 Black Hole 的 p98 達 1.0，
但模型仍是黑色裝甲，因為 atlas 的白底也被算入。**新素材應與相近配色的原裝甲比較，
不能強制瞄準全家族中位數。** 例如 Cygni 原圖的白甲不應被壓成 Viper 的深藍亮度。

## 配色：一個主色相吃掉絕大多數

用色相的圓形集中度量（有彩色像素中，落在主色相 ±30° 內的比例）：

| 指標 | 最低 | 中位 | 最高 |
| --- | --- | --- | --- |
| 色相集中度 | 17.2% | **92.6%** | 100% |

複算為 14 套在 85% 以上，其中含程式將無達標彩色像素的 Draco 設為 100% 的特例；
真正有達標彩色像素的是 13 套。上表的 100% 最高值就是這個特例，不是實際量到的值。
（`tools/armor_texture_check.py` 的同一個 fallback 已於 2026-10-02 改成回報「不適用」，
但本節表格保留原稿數字以對應當時的複算紀錄。）
03（17.2%）和 16（57.6%）是明顯多色例子。
這個比例只計 `S > 0.25 且 V > 0.25` 的像素，不是甲片面積。
**保留每套的大色塊主次關係，不強制單一色相占 90%。** 例如 Chaos、R.O.M.E 有大片紅甲；
X-Field 是紅甲配青色模組，不能把青色一律縮成面罩上的小點。

有彩色像素（飽和度 >0.25 且明度 >0.25）的占比從 0% 到 62.8% 都有——
09 Draco 沒有通過上述門檻的彩色像素，但原圖存在 RGB 不相等的像素，所以應稱
「低彩度深灰」，不能稱數學上的純灰階。是否使用鮮明色彩由裝甲設計決定。

幾套的實測主色：

下表於 2026-10-02 依 `player.gltf` 的材質名稱重算，取代原稿按檔名順序抽樣的版本。
hex 是整套 atlas 出現最多的三個量化色，含底色與未使用區，**不是甲片的材質配方**。

| 裝甲 | 主色相 | 出現最多的三色 | 色相集中度 | 有彩色像素 | 檔名前綴 |
| --- | --- | --- | --- | ---: | --- |
| 00 Viper | 211°（藍） | `#101020` `#000000` `#001020` | 94.7% | 15.0% | `head_` |
| 06 Thunder | 201°（青藍） | `#303030` `#101010` `#000000` | 82.2% | 23.6% | `09_` |
| 09 Draco | 未達彩色門檻 | `#101010` `#303030` `#202020` | — | 0.0% | `10_` |
| 11 Cygni | 28°（銅橙） | `#202020` `#101010` `#B0B0B0` | 93.9% | 2.8% | `man12_` |
| 18 Black Hole | 209°（藍） | `#101010` `#000000` `#101020` | 91.9% | 2.2% | `renze_` |
| 19 X-Field | 359°（紅） | `#602020` `#401010` `#101010` | 88.9% | 62.8% | `man_20_` |
| 20 Wrath | 212°（藍） | `#000000` `#101020` `#000010` | 84.6% | 24.5% | `man21_` |

**貼圖檔名的數字不等於 armor id。** `man_20_*` 掛在 `ArmorBody_19`，`man21_*` 才是 20
Wrath。按檔名抽樣會整套對錯——原稿把 19 X-Field 的紅色誤記成 20 Wrath 的主色就是
這樣來的。要對應就讀 `player.gltf` 的材質名 `ArmorHead_<id>_*`，不要讀檔名。

Cygni 的 28° 只來自 2.8% 的達標彩色像素（銅橙嵌條），整套主體是白灰甲——
`#B0B0B0` 才是它的識別色。色相集中度高不代表整套是那個顏色。

## 畫法規則

從貼圖對照圖逐張看出來的共通手法（這一節是目視歸納，沒有量化）：

- **可見寬明暗漸層與受光邊。** 多處上緣較亮、凹處較暗，但 atlas 的島各有旋轉，不能把圖片上方當成所有甲片的受光方向。
- **甲片之間用深色縫隙分開**，不是黑色描邊。縫隙是材質，不是線稿。
- **大色塊先讀得到。** 原圖仍有鉚釘、徽記、刮痕與局部細紋，例如 Thunder 的肩部螺絲、Cygni 的布料紋；細節只應保留在縮小後可辨識的位置。
- **筆觸是手繪的**，有輕微顆粒，不是向量平塗，也不是照片材質。
- **面罩常是視覺焦點**，也有無玻璃面罩的 Draco、Andromedae，以及大面積鮮色甲片的 Chaos、R.O.M.E；不能把它寫成唯一允許高彩度的區域。
- 不能從 atlas 外觀判定某一區「用不到」；先查 UV 使用範圍，再保留或製作相鄰色留邊。

## 已撤下的原稿 prompt

初版正文那段 prompt 已移到
[legacy_armor_base_v2/claude_draft_prompt_superseded.md](legacy_armor_base_v2/claude_draft_prompt_superseded.md)，
附上三條限制各自被哪項實測推翻。**正文不留它的全文，避免被直接複製貼上。**
生成一律用下方的「整合基底 prompt」。

## 驗收

**原版與新版並排應像同一位美術製作的不同裝甲；這是使用者於 2026-10-02 設定的交付底線。** 用同一相機、姿勢與顯示高度，比較遊戲比例、甲片明暗、亮邊與凹縫畫法、材料表現及細節密度；例如 Cygni 新頭盔可以改成金 T 面罩，但白甲仍應使用原 Cygni 的灰白漸層與克制亮邊，不能變成大塊純白或馬賽克式三角分色。統計和工程 PASS 不代表這項目視門檻已通過。

檢查器可列出數據，**以一整套 5 張為單位**，但它的 PASS／FAIL 只代表所寫門檻，
不是美術或 UV 驗收。新幾何先確定模型與 UV，再生成對應貼圖；不能任意生 atlas 後逼模型去配。

```sh
python3 tools/armor_texture_check.py path/to/new_set/*.png
```

門檻是 21 套原版的實測 min–max，所以**刻意亮或白的設計本來就會貼著端點跑，
不是瑕疵**；中位數只是參考，不是目標。2026-10-02 修了兩個會給出假結論的地方：

- 沒有達標彩色像素時（09 Draco），色相項原本回報 1.0 並印 PASS。改成印
  「不適用」且不計入通過與否——量不到的東西不該產生 PASS。
- 門檻四捨五入到小數三位，讓剛好定義下限的那一套（09 的 p98 等於 0.416）
  會 FAIL 自己。加 0.001 容差。

回歸：21 套原版現在全部通過自己的門檻（0 FAIL）；修之前 09 會 FAIL。

## Claude 原稿的範圍限制（下方補入 CoM 與模型規格）

- UV 版面本身。生圖模型排不出能對上現有模型的 UV island；要沿用現有版面就得走
  `precise-object-edit`（既有做法見 [thunder/helmet_texture_prompt.txt](../../assets/armors/thunder/helmet_texture_prompt.txt)），
  要全新版面就得先在 Blender 攤好再把版面圖當輸入。
- CoM 的 21–28 套。那批有自己的材質規則，上面數字只取 SW1 的 00–20。
- 背包與武器。它們各自有動畫／疊加材質，不吃這套 unlit 規則。
- 畫法規則那一節是目視歸納，沒有量化門檻，驗收腳本測不到。


---

## Codex 全素材分析：共通畫法與每套例外

**全部舊裝甲共享「大塊外形＋貼圖畫立體感」的方法，但造型複雜度、配色與頭盔比例會隨裝甲改變。** 生成新素材時先選目標所屬家族，再從全部分析中選相近的原套作畫法參考；不把兩款遊戲的身體比例取平均。

### 原始來源與排除範圍

**這份基底只從舊模型和舊貼圖取規則，AI 精修版與先前失敗試作不參與基準。** 所有路徑與檔案 SHA-256 已記在 [inventory.json](legacy_armor_base_v2/inventory.json)，以便確認後續餵給生成器的是同一批圖。

| 家族 | 舊版資料 | 實際檢查 | 不作原版基準的資料 |
| --- | --- | --- | --- |
| SW，ID 0–20 | `assets/models/player/animated/player.gltf`、`player.bin`、`armor_textures/*_2x.png` | 21 套、84 個部位 mesh、105 張不同 PNG、106 個材質貼圖使用位置；Tank 的手部貼圖另被頭部一個 surface 共用 | `assets/equipment_refined`、`assets/armors/angular`、`assets/armors/thunder`、Cygni 各次試作 |
| CoM，ID 21–28 | `assets/callOfMini/*.zip` | 8 套 DAE、24 張 PNG 檔；`enhanced/*/*.dae` 與 `enhanced/*/source/*.png` 均逐檔確認和 ZIP 位元組一致 | `enhanced` 頂層的 1K 精修 PNG、`gameplay/*.scn` 的重定向與 Assault 修改 |
| 新概念 | `docs/art/original_armors_v1/index.html` | 21 套 concept 路徑、雜湊、採用狀態與設計說明另存於 inventory 的 `concepts` | 不用概念圖的寫實身長和密集細紋去推翻遊戲比例 |

SW 的 `_2x` 是匯出器做的 LANCZOS 放大；100 張為 512²、R.O.M.E 的 5 張為 1024²。依 `TEXTURE_EXPORT_SCALE=2` 推回來源為 256²／512²，這是有匯出程式支持的推算，不是假稱持有原生 Unity PNG。CoM 則直接讀 ZIP：helmet/equip 為 256²、armor 為 128²。這批 129 個 PNG 檔的 alpha 全部為 255。

本次共擷取 116 張視圖（每套正、斜、側、背）；SW 保留匯入 tint，CoM 使用白色 tint 與 unlit 顯示來檢查 diffuse。CoM 原模型面向 +Z，展示時只旋轉根節點以對齊 SW 的 -Z，沒有翻 UV 或重定向骨架；各套 CoM 獨立按高度取景，不能用圖上同高推斷兩遊戲同一世界尺寸。這是本 repo 原始資產的檢查圖，不是兩款原遊戲執行時的截圖。

### 外形與模型配置

**原版造型首先由低面數模型的大輪廓決定，貼圖只能補表面，不能修正錯誤的頭盔大小與下巴外形。** 先讓新模型在無貼圖狀態下有正確身體比例、頭肩關係和關節位置，再畫貼圖；例如 Cygni 的斜收護頰需要真的改 mesh，不能把白甲畫在舊臉旁邊便期待輪廓改變。

| 項目 | SW 原版實測／配置 | CoM 原始資料與可用規則 |
| --- | --- | --- |
| 完整套裝面數 | 682–1,590 tris；Viper 682、Cygni 1,006、Black Hole 1,590 | 600–694 tris；Mark-6 117R 是此 ZIP 的 614 tris |
| 外形 | 大頭、短身、厚實前臂／小腿，腳掌能承接身體重量；曲面由少量切面表達，後期套裝有較多尖翼／角 | 頭更佔視覺重量，身軀與肢體更方整、甲片更簡化；不要套到 SW 後直接變方塊公仔 |
| 部位 | `ArmorHead_XX`、`ArmorBody_XX`、`ArmorHand_XX`、`ArmorFoot_XX`；肩材質在 body 中 | DAE 主要分 helmet、equip、role；遊戲內拆成四件的是後續適配，不是 ZIP 原生結構 |
| 貼圖角色 | head／body／jian（肩）／hand／foot；原版部位跨 surface 可共用貼圖 | helmet／equip／armor；8 套共用相同內容的深色 undersuit 圖，部分頭盔 atlas 也共用 |
| 細節分配 | 輪廓、厚薄、突起用 mesh；小縫、螺絲、分片亮邊可畫在 diffuse | 大平面與簡化甲片，面罩／色帶和少量大標記比細雕刻重要 |
| 骨架交付 | 遊戲沿用匯入骨架與武器／背包掛點；製作時保留現有關節契約，不能任意拉長四肢 | 新 CoM 裝甲若進同一遊戲，另驗證適配後尺寸與動作；原 DAE 的 rest pose 不是遊戲動畫驗收 |

`inventory.json` 有全部 SW 頭部最大連通區尺寸。它只是幾何分析，不等於人類的「幾頭身」：例如 Thunder 的頭冠、Chaos 的大角若和頭殼連著就會被算入；不能把所有套裝強制為同一頭高比例。Cygni 最大連通頭部約 `0.461 × 0.782 × 0.700`，Atom 約 `0.615 × 0.621 × 0.584`，這些差異就是不同設計，不是應消除的誤差。

### 畫法、材質與配色

**風格一致要對齊的是甲片怎麼畫、細節如何分配，而不是要求每套一樣暗、同色或同一面罩。** 使用相近原套的板材與布料畫法，將新概念的色塊和識別形狀放回這套畫法中。

| 要保留的做法 | 舊素材中看得到的例子 | 新素材如何使用 |
| --- | --- | --- |
| 大面明暗＋窄亮邊＋深凹縫 | Viper、Fortune 的頭殼／胸甲；Cygni 白甲 | 先畫體積，再加少量刮痕。亮邊寬度要按 UV 尺度看，不能全圖固定同一線寬 |
| 甲片和軟衣要分開讀 | Viper 的暗腹部、Cygni 的深綠／黑接縫、CoM 共用 undersuit | 關節深但仍可辨認，避免純黑大洞；粗布／肋紋只放軟材質 |
| 局部細節可存在 | Thunder 的肩部圓螺絲、Cygni 布紋、Andromedae 圓徽記 | 不把低解析度誤解為零細節，也不把這些細節鋪滿所有甲片 |
| 玻璃主要靠畫出的色階／反光 | Viper 紫面罩、Hydra 黃綠面罩、CoM Mark-6 金黃面罩 | 少數寬反光區即可；不必建立透明折射材質才能像玻璃 |
| 全封閉面甲是另一類型 | Draco、Andromedae | 新概念指定不透明面甲時，不因「科幻」自動加一大片玻璃 |
| 發光分布有套裝差異 | Strike 的環與小條、Phoenix 的藍色分支線、Knight 綠色區塊 | 沿用個別設計的光源角色；不把所有縫都加亮 |
| 留有乾淨大面 | Viper、Tank 的護臂與小腿；CoM 的大胸片 | 高解析度輸出也不增加整面刻線、密集鉚釘或金屬刷紋 |
| 顏色受貼圖與材質共同影響 | Pegasus 原 atlas 白灰但原匯入頭盔 tint 變紅；Cygni 同理變粉 | 依使用者要求，兩者新頭盔都跟身甲同色；不能把匯入 tint 當新設計配色 |

以下是逐套模型與所有 atlas 的目視歸納，顏色是材料角色描述，**不是經過分區量測的精確 HEX 配方**。各套面數則直接讀 mesh 的三角形索引。

| ID／舊裝甲 | tris | 舊素材配色與可辨識做法 |
| --- | ---: | --- |
| 00 Viper | 682 | 鋼藍甲、黑褐軟衣、紫面罩；圓頂、大片胸片、窄亮邊 |
| 01 Fortune | 720 | 灰藍與深綠、暗紫面罩；較圓的盔殼和護脛，分片較少 |
| 02 Tank | 796 | 藍甲、淺綠邊框、橙面罩；中央冠條、實心下頷、厚肩 |
| 03 Hydra | 760 | 青藍甲、黃綠肩邊／面罩；分段冠頂、局部明顯刮痕 |
| 04 Strike | 722 | 深青藍、青色燈環／線、金面罩；科技圓點與大甲片並存 |
| 05 Titan | 700 | 藍灰甲、橙黃面罩／小嵌條；大胸片、腹部黑接縫 |
| 06 Thunder | 782 | 鋼藍、黃條、琥珀面罩；高冠、耳圓件、扇形肩片 |
| 07 Atom | 860 | 紫甲配淺青藍甲、青色圓燈；寬圓頭殼、肩側尖翼 |
| 08 Pegasus | 1,128 | 原 atlas 白灰甲配深藍接縫／面窗；頭部匯入紅 tint 不作新設計目標 |
| 09 Draco | 854 | 低彩度煤灰甲與黑接縫；封閉面甲、短槽孔與厚層片 |
| 10 Phoenix | 1,022 | 深藍紫、青藍分支線；尖耳／肩翼、局部細紋；使用者要求保留原版 |
| 11 Cygni | 1,006 | 白灰甲、深綠接縫、銅橙條；原面窗有藍紫／橙邊，原圖粉頭為 tint，新版指定金 T 面罩 |
| 12 Andromedae | 1,168 | 鋼藍、黑褐軟衣、青色圓徽記；封閉面甲與圓肩裝置 |
| 13 Perseus | 852 | 黑／深綠、灰白分支面紋、橙邊；尖收面甲、肩部疊片 |
| 14 Chaos | 1,036 | 紅甲、黑角／肢體、黃金火焰紋；尖長角和強色塊，不是低彩度通例 |
| 15 DEC.24 | 958 | 紅甲、白邊、淡黃綠面窗；帽形頭殼、明顯寬白高光 |
| 16 Knight | 1,260 | 藍灰甲、亮綠區、少量橙點；尖冠、多角肩片、胸部條帶 |
| 17 R.O.M.E | 1,056 | 紅甲、白條／銀面窗、黑褐關節；頭冠、雕紋胸片，貼圖來源尺寸特例 |
| 18 Black Hole | 1,590 | 深灰黑甲、細藍邊、暗青點；多層鱗片、腹部肋紋；atlas 白底不能算成白甲 |
| 19 X-Field | 1,074 | 紅甲、青色面窗／胸部與肩蜂巢；大色面比較平整、黑凹縫鮮明 |
| 20 Wrath | 1,118 | 鋼藍、黑、銀金飾邊、紅面罩；高側角與彎曲肩翼、局部雕紋 |
| 21 Assault Armor | 606 | 此 ZIP 為黑盔黃面部圖案、紫色甲、橙胸塊；大方塊甲與腰帶 |
| 22 Combat Suit | 600 | 紫甲、亮綠面罩、黑軟衣；圓大頭、簡單胸片 |
| 23 Drillmaster | 642 | 灰藍甲、綠面罩、青色小燈；大額甲和下頷呼吸區 |
| 24 Heavy Battlesuit | 694 | 卡其甲、淺藍面罩、黑接縫；雙高側翼、厚肩／護脛 |
| 25 Mark-6 117R | 614 | 此 ZIP 為軍綠與紫分區、金黃面罩；中額色條、簡化 T 形面窗 |
| 26 Recon Suit | 646 | 橙色迷彩、藍面罩、黑腰帶；高側鰭、大片迷彩形狀 |
| 27 Sanguine Chaos | 650 | 深灰褐甲、橙面窗／雙線；窄面罩、斜眉、大塊下頷 |
| 28 Training Suit | 644 | 淺／深軍綠、橙色窄視窗、青色小燈；圓帽沿、簡化面甲 |

### 三種輸入各有責任

**新版只做指定的局部改動；主要輪廓、比例與製作方式沿用原版。** 概念圖不能同時決定比例、表面畫法和 UV；這三件事要各自有可靠參考。 按下表提供圖片，生成器才知道哪些特徵要保留、哪些要轉換。

| 輸入 | 決定 | 不決定 | Cygni 例子 |
| --- | --- | --- | --- |
| 原模型視圖 | 身體比例、關節位置、體積大小與可讀性 | 不強制新頭盔照抄舊長下巴 | 保留遊戲大頭短身與手腳大小 |
| 原始 atlas | 明暗畫法、材質區分、細節密度 | 不強制新甲片使用舊形狀／舊配色 | 參考白甲、深綠軟區和局部粗布紋 |
| 已選新概念 | 新頭盔／面罩、甲片安排、色塊與識別特徵 | 不採用寫實成人比例和每個微小刻線 | 白灰同色盔殼、金色 T、內收頰甲、短下巴 |
| 新模型＋UV＋區域遮罩 | 貼圖哪個像素落在哪個表面、哪裡接縫 | 不授權生成器任意移動 UV 島 | 金色只能落在新模型真正的面罩上 |

```text
全部原素材分析 → 共通規則／套裝例外
                          ↓
原模型主要輪廓／比例／UV 方法＋畫法基底＋已選概念局部 → 遊戲比例的局部改造
                          ↓
外形有變：新模型 → UV 展開／材質區域 → 生成 diffuse → 貼回模型檢查
外形不變：原模型與原 UV 固定 → 編修對應 diffuse → 貼回模型檢查
```

例如 Cygni 想從舊長下巴改成短下巴，必須走「外形有變」；只拿原 atlas 生一張看似正確的頭盔圖，再貼回舊模型，仍然會是舊長下巴，並可能把金色和白甲畫到錯誤位置。

### 原版的連續頭殼與 UV 方法（2026-10-02 更新）

**局部輪廓調整先使用既有頂點與 UV，避免為收小耳甲或護框再拆出新區域（Titan 2026-10-06 補充）。** 共用幾何位置與鏡像接縫一起移動；已有切分中點跟隨父邊的位移，保留原 UV／權重。以灰模和完成貼圖比對後才決定是否需要更多切分。Titan 最新獨立試作維持 v4 的 164 tris／334 UV 座標／3 區域，沒有新生貼圖或替換正式裝備，見 [本次對照](titan_runtime_v1/review/draft_alignment_20261006/index.html)。

```text
LOCAL GEOMETRY REVIEW ADD-ON: first try moving existing shell vertices while
keeping the current UVs, broad chart count, topology and skin weights locked.
Move shared physical seam instances and mirrored pairs together. Existing arc
midpoints follow their parent edge displacement; do not leave them behind.
Review clay, painted, side and moving poses using the same model and camera.
Only add cuts when the existing cage cannot express the needed silhouette.
Keep inferred adjustments separate from measured reference dimensions.
```

**使用者要求：新版必須非常接近對應原版，只接受局部改動；不得大幅重做後失去原版風格。** 保留主要輪廓、遊戲比例、連續體積、分片密度與 UV 共用方式。新概念只轉換已指定的局部；例如 Cygni 可縮短下巴、內收頰甲及改金 T 面罩，不因此把整個頭盔換成大量獨立甲片。這項範圍優先於早期「新概念決定新造型」的泛用措辭。

**新版沿用原版的製作方法：完整主頭殼、大片連續 UV、對稱部分共用貼圖；新概念仍決定輪廓與面罩。** 眉甲與頰甲先接成完整體積，細縫、淺層分片及倒角亮邊由 diffuse 表現；只有影響外輪廓、動作或必要厚度的附件另外建模。適用到其他套裝時先查該套原件，不把 Cygni 的配置硬套給所有裝甲。

Cygni 原件的頭部為 238 tris，最大連續頭殼 166 tris；貼圖上的相連區域為 7（左右重疊合併）。被使用者否決的試作為 596 tris、141 個相連區域。數量是偏差證據，不是硬性美術門檻；真正要避免的是把主體切成零碎片段，再替每片各畫一圈亮邊。實測在 [original_head_method.json](cygni_runtime_v2/review/original_head_method.json)。

- 保留大面明暗連續；UV 切口放在後側、隱藏處或必要邊界。
- 對稱表面可鏡像共用 UV；使用者指定的非對稱設計要保留獨立區域。
- UV 島邊界不是甲片邊界；不得逐島、逐三角形加亮框或黑框。
- 用原拓撲改造時可保留原 UV，但要真的改外輪廓；Cygni 仍須短下巴、內收頰甲與金 T 面罩。
- 可用 Blender 局部改造原 mesh：縮短下巴、內收頰部、調整頭冠／側翼；保留遊戲尺寸、原骨架、掛點與可用權重，保存可編輯 `.blend` 和改動前後對照。這是使用者要求的建模做法，不限於換貼圖。
- 先檢查灰模、棋盤格與接縫，再把實際 UV／區域圖交給圖片生成器；生成器不負責展 UV。

### Titan：大片玻璃與局部圓弧（2026-10-05）

**本次 Titan 以草稿的大片金色玻璃面罩為主；圓弧必須做到 3D 輪廓，藍色只作外圍護框。** 使用者允許這套頭盔小幅增加 UV／幾何切分，但仍禁止數量翻倍或把主頭殼切碎；這項放寬只適用本次指定的 Titan。

- 在原有弧線邊緣加入少量頂點，延用相同骨架權重與連續 UV；只補貼圖高光不能修正側面折角。
- 分別量測三角形、UV 座標及連續 UV 區域；三者不能混稱「UV 面數」。本次頭盔為 124 → 132 tris、294 → 302 個 UV 座標，連續區域維持 3。原 UV 中只調整 10 個取樣座標，避免共用中線採到 atlas 邊框而變成面罩中央的尖角。
- 原三角形須有可追溯的切分關係，不能遺失或重複面；新增頂點繼承同一原邊的權重。這次採取 10% 的面數／座標增量上限作為實作預算，不是給其他套裝的新授權。
- 大頭短身、身體與四肢、武器／背包掛點仍以實際原模型為準。草稿只有斜視圖，側後方深度需標示為推測；遊戲可用與使用者美術接受分開記錄。

套裝附加 prompt（搭配基底、實際 UV 與選定草稿）：

```text
TITAN HELMET: the front is predominantly one continuous convex amber-gold
glass faceplate, extending up into the forehead dome and wrapping toward the
temples. A shallow steel-blue perimeter frame supports it. Preserve the game's
large-head proportions and hand-painted diffuse style. The mesh silhouette must
carry the curvature; a painted highlight cannot replace curved geometry.
Use a few local edge subdivisions only when required. Keep the broad connected
UV charts and mirrored reuse, and report triangle/UV-coordinate/chart counts
separately. Never turn the shell into many outlined fragments or double counts.
The shared face-center seam is glass interior, not an external black rim, blue
nose or vertical highlight. Check the actual wrapped model before delivery.
```

實際素材、實送 prompt、變更前快照與驗證見 [Titan README](titan_runtime_v1/README.md)。

### 整合基底 prompt（直接複製）

**這段是後續生成應使用的共用開頭；再接套裝條件與實際輸出類型。** 原版全套分析已濃縮在其中，生成一套時附目標套與相近套的參考即可，不必把所有 29 套同時混進生成圖片。可單獨取用 [base_prompt.txt](legacy_armor_base_v2/base_prompt.txt)。

```text
Translate the supplied NEW armor concept into the visual language of the supplied ORIGINAL mobile-game armor assets.

REFERENCE RESPONSIBILITIES
A — Original in-game mesh views: authority for game-scale body proportions, joint locations, thickness hierarchy and readable silhouette mass.
B — Original diffuse atlases: authority for painted lighting, edge treatment, surface detail frequency and material separation. They do not dictate the new design or its UV layout.
C — New approved concept: reference for the specifically approved LOCAL helmet/visor, plate and color changes. Keep the original armor strongly recognizable in overall mass, proportion, construction and painting style. A concept does not authorize a wholesale redesign, extra fragmentation or realistic anatomy; simplify it to fit the legacy construction. Its cinematic lighting and microscopic detail are NOT target style.
D — Target mesh renders, exact UV layout and material-region masks, when provided: authority for texture placement. A missing D must never be invented and described as a working UV atlas.
Explicit user corrections override reference-image artifacts, such as a pink/red imported helmet tint.

STYLE FAMILY
Use {STYLE_FAMILY: Star Warfare or Call of Mini}, matching the chosen old model, not an average of both games. Make it look authored alongside that old model. Human wearing hard-surface armor: enclosed helmet, broad chest and shoulder plates, compact torso, short sturdy limbs, substantial gloves and boots, dark flexible joints. Preserve the selected game skeleton's limb lengths and body mass. Translate the new concept onto those proportions. Do not turn it into an adult realistic soldier, a slender action figure, a smooth toy, a voxel doll or an exposed-piston robot.

SHAPE HIERARCHY
Read the helmet, chest, shoulders, forearms and shin/boot masses before small detail. Use broad faceted planes and controlled curved transitions. Keep neck, elbow, hip and knee gaps readable and functional. Real geometry must carry silhouette-changing fins, cheek volume, visor recess, shoulder overhang and plate thickness. Paint can describe small seams, screws and bevel highlights. Preserve {DESIGN_IDENTITY_FEATURES}; simplify minor segmentation rather than erasing those features. Preserve the selected legacy armor's main contour and mass; make only the approved local changes, such as Cygni's shorter chin and gold T visor. Do not replace the whole helmet with a different design language. Other suits keep their own legacy features rather than adopting Cygni's proportions.

LEGACY CONSTRUCTION AND UV METHOD
USER CONSTRAINT: new armor must remain very close to its corresponding original. Local edits are acceptable; wholesale changes to silhouette, body proportions, plate segmentation or UV fragmentation are not. Compare original and new clay geometry at the same camera/scale before generating diffuse. Preserve the major continuous masses and original-compatible UV reuse where possible. Do not trade the legacy identity for more detail, more triangles or more separately outlined pieces. If the concept cannot fit within this local-edit scope, show the departure explicitly rather than silently adopting it.
Build each major helmet or armor mass as a coherent low-poly shell. Use separate geometry only for genuine silhouette-changing attachments, moving pieces or necessary thickness. Keep the brow and inward-swept cheeks continuous with the shell; paint most shallow seams, bevels, vents and layering cues into diffuse. Do not assemble the face from many floating plates, bevel every tiny piece, or triangulate the shading into a mosaic.
Author broad continuous UV charts for the shell and visor. Reuse mirrored UV space for genuinely symmetric surfaces and matching paint; provide unique space only where an approved asymmetric feature needs it. Cut seams at hidden/rear transitions or real material boundaries. An automatic projection that splits individual triangles or every little plate into separate charts is not an acceptable default. Original atlas layouts are evidence for chart continuity and mirrored reuse, not a universal island-count limit. If adapting a compatible original cage, preserve its broad UV layout and vertex-to-UV correspondence while reshaping the contour for the new concept. Blender may be used to make local edits to the existing mesh: shorten an elongated chin, sweep cheeks inward, soften a crown or shorten side fins. Preserve game scale, joints, attachment points and compatible weights. Save an editable .blend and record the actual geometry changes; a retextured unchanged mesh is only a surface trial. If making a new cage, author equivalent continuous charts before requesting imagery.
UV chart boundaries are technical cuts, not armor plate edges. Maintain broad painted gradients across adjoining faces and matching seam pairs. Do not draw a bright rim or dark outline around every UV island or triangle. Image generation paints the validated layout; it must not invent, repack or repair the layout. Inspect clay, checker and textured front/side/back views on the same model before claiming a usable material.

PAINTING AND MATERIALS
Painted diffuse with broad, restrained light-to-dark gradients across each surface; lighter exposed edges and dark recessed seams imply the low-poly volume. Orient the painted lighting by the surface in 3D, not by the top edge of the atlas. Keep some quiet plate interiors. Allow sparse readable wear, a few fasteners, vents or symbols only where the reference supports them. Keep cloth/rubber mostly dark, with localized coarse ribbing or fabric pattern. Visors use simple painted reflection bands and color depth; do not require physical transparency. Opaque metal faceplates stay metal when the concept has no visor. Avoid dense scratches, noisy brushed-metal grain, all-over hexagons, micro-greebles, mirror chrome, glossy product-render highlights and cinematic rim lights. Avoid making every seam a thick black outline or every edge a bright glow.

COLOR
Use {MAIN_ARMOR}, {SECONDARY_ARMOR}, {FLEXIBLE_JOINTS}, {VISOR_OR_FACEPLATE}, {ACCENT_LOCATIONS} from the approved concept. Preserve a readable hierarchy of large armor colors, dark joints and focal accents. Match the closest original armor's material treatment. Do not force all suits to dark blue, one hue, a fixed mean brightness or a universal accent percentage. White armor, saturated red armor, two-color armor and dark opaque helmets all exist in the original corpus. Saturated accents may appear on armor plates when the design requires them. Preserve head/body color agreement when specified.

DETAIL SCALE
The SW source family mostly uses five 256x256 diffuse atlases per suit, with R.O.M.E using five inferred 512x512 sources. CoM uses helmet/equip at 256x256 and undersuit at 128x128. These describe original feature density, not a ban on higher-resolution output. A larger output must retain this restrained feature density. Check the design at a small game-like display size as well as close-up. Enlarging the image must not add thousands of new surface details.

OUTPUT CONTRACT
Follow the appended task: design sheet, texture atlas, or actual 3D model. These are different deliverables.
For an atlas: paint only the supplied target UV layout; preserve island coordinates, relative scale, orientation, seam relationships and masks. Preserve opacity and source padding when editing an existing map. Produce one flat diffuse image, no character render, perspective, labels, swatches, checkerboard or decorative border. Never project a perspective concept drawing onto the whole atlas. Do not pretend a texture can change the old mesh silhouette.
For a model: reproduce the concept's forms at the old game proportions; verify grey geometry before texturing, then author UVs and compatible rigging. A PNG is not a rigged GLB or a validated game asset.
Report missing views and inferred surfaces. Validate the textured model from front, side, rear, the gameplay camera and moving poses beside original armor. Do not claim style consistency or UV correctness from image statistics alone.
```

### Cygni 套裝附加條件（示範用法）

**套裝條件只規定這套的新設計，不改掉上面的畫法與遊戲比例規則。** 以下以目前主圖為準；開始生成前仍須核對 gallery 是否已採用較新的候選。

```text
TARGET: Cygni / armor ID 11 / design C-12. STYLE_FAMILY: Star Warfare.
DESIGN SOURCE: docs/art/original_armors_v1/images/c12_concept.png, the current main gallery image. Inspect the gallery's user_review and helmet_studies records before generating; study candidates do not automatically replace the selected main image. The supporting turnaround is a design reference, not a dimensionally exact blueprint.

KEEP THESE DESIGN FEATURES:
- White/light-grey helmet shell matching the white/light-grey body armor.
- Gold T-shaped visor: a broad eye band narrowing into a central downward strip, flanked by inward-swept cheek armor. Do not broaden glass into both lower cheeks.
- Layered brow, compact chin, short swept-back side fins. Avoid square cheek blocks and the elongated original helmet's lower guard.
- White armor over a dark desaturated green secondary shell and charcoal flexible joints.
- Small copper-orange inserts on chest and selected limb/helmet regions; short shoulder wings echoing the helmet fins.

TRANSLATE TO THE GAME:
Use the old SW character's large helmet, compact body, short limb spans, chunky hands/boots and existing joint positions. The new full-height adult anatomy in the concept is not the target. Preserve the original Cygni shell identity and construction. Make local mesh changes for the approved shorter chin and swept cheeks, plus the gold T visor; avoid a wholesale helmet replacement.
Use original Cygni diffuse maps to judge white paint, dark green, subdued gold/copper and restrained seam/cloth detail. Imported pink head tint is not desired. Gold glass should have a simple broad painted reflection, not a photoreal environment reflection.
New chest/cheek/fin shapes that alter silhouette require model work and matching UVs. If only original UVs are supplied, label the result a surface-style trial on the OLD geometry; it is not completion of this new design.
Phoenix remains unchanged. No rollout to later armor sets is authorized by this analysis prompt alone.
```


### 貼圖生成的附加指令

**能貼回模型的 atlas 必須附上實際 UV，不能從一張全身概念圖猜貼圖版面。** 以下接在基底與套裝條件後；沒有 UV 時先完成模型與 UV，不把任意拼排的零件圖當成可用貼圖。

```text
OUTPUT: one opaque diffuse UV atlas for {PART}, {WIDTH} x {HEIGHT}.
Input A is the exact UV/layout reference for the target model. Input B is its
material-region mask. Input C is an unlit render showing where those regions
land. Input D is the selected new concept. The original atlas/style samples
are painting references only unless A explicitly uses that same original UV.

Keep every UV island's position, size, orientation and outer silhouette exact.
Chart boundaries are technical seams, not armor outlines. Continue painted
gradients across adjoining surfaces; do not rim every island or triangle.
Keep seam pairs consistent in color and edge-detail continuation. Paint the
specified material only inside its designated region. Do not add a front-view
helmet picture over an unfolded side shell. Do not place reflected highlights
as if every rotated island faces the same direction in the square image.
Use opaque adjacent-color padding sufficient for the target mip levels, as
specified by the UV bake/export. For existing-map edits preserve the supplied
padding and opacity. Do not black out an area unless the UV mask says it is safe.
No rendered character, labels, swatches, wireframe, checkerboard, extra parts,
cast shadow behind islands, transparency, invented UV layout, or tiled noise.
Save the generated original separately from resized/exported runtime versions.
This is a candidate until placement, seams and material reading pass on-model review.
```

### 交給 sol6.1 的完整工作指令

**把下面交給下一個執行工作，就能按同一份規格生成、建模與驗證；不能把「生成了一張圖」當成已完成遊戲素材。** 先以一套做完整示範，再將同一方法擴到已授權套裝，可以早點發現整套都會重複的錯誤。

```text
請在 star-warfare-godot 專案工作，先讀
1. docs/art/ARMOR_TEXTURE_STYLE_SPEC.md 的整合版規則與基底 prompt。
2. docs/art/legacy_armor_base_v2/README.md、inventory.json 及全部原始參考圖。
3. docs/art/original_armors_v1/index.html 中目標裝甲的 images、user_review、
   helmet_studies；實際打開選定圖片，不只讀文字或根據圖片檔名猜。

目標：以原版的遊戲比例、貼圖畫法、材料表現及細節密度，製作新版概念的裝甲素材。
預設先做 Cygni（ID 11）示範；如果使用者另指定套裝，就替換套裝條件。
不要把此預設寫成使用者已批准的新版外形。

套用「整合基底 prompt」＋所選概念的「套裝附加條件」＋明確的輸出類型。
新版要非常接近對應原版，只接受指定局部改動；原版決定主要輪廓、遊戲體格、
分片密度與 UV 方法，新概念補入局部新設計。不照抄原 Cygni 的長下巴，
也不沿用概念圖的成人長腿。檢查正、側、背時要用同一個模型。

如果新概念改變頭盔／肩甲／胸甲外形：
先製作符合遊戲骨架的模型，檢查主體輪廓與關節後製作 UV 和材質區域遮罩，
再用圖片生成工具產生對應 diffuse。UV 輸入要來自這個模型。
主體採連續頭殼／甲片與大片 UV；對稱部分可鏡像共用。不要以逐片自動投影
代替展 UV，也不要讓生成器替每個 UV 島各畫亮框；詳見「原版的連續頭殼與 UV 方法」。
如果只試貼圖：固定原模型和原 UV，明確標示「舊幾何上的表面風格試作」，
不得把它稱為完整新版裝甲。

所有生成必須使用實際圖片生成工具，保存實際 prompt、參考路徑／hash、輸出原圖
和處理記錄。不要用程式拼出一個不相干的頭盔或把概念透視圖硬投影成 atlas。
只要求圖片生成器產出它能交付的影像；可用 3D 模型、UV、骨架與匯出另用建模工具完成。

驗收：與原模型在相同相機／姿勢／顯示高度並排，檢查無貼圖輪廓與完成材質，
再看正側背、實際遊戲鏡頭、持槍待機、跑動與換裝。檢查頭盔與胸肩不穿插、
接縫不斷裂、面罩不錯位、材質不突然變成寫實金屬，保留武器與背包掛點。
128px 高度可以先作縮小檢查，但它是暫定檢視尺寸，不是量測過的實際遊戲高度。

保存獨立版本，提供原版／新素材同畫面比較、來源與生成記錄、驗收結果及未完成項。
概念 PNG、貼圖 PNG、可用 GLB／場景分開標示；缺視角與推測部分明說。
貼圖統計 PASS 不能代替 UV、骨架、動作或視覺驗收；不要承諾未證實的 100% 風格一致。

當前套用範圍沿用使用者要求：至 Cygni 的前段裝甲，Phoenix 保留原版；
Thunder 依已選版本，不任意蓋過。Cygni 後面的套裝保留原版。
本次「分析所有原素材」不等於授權把全部 29 套一起改掉。
```

### 原分析階段的驗收與交接狀態

**以下保留分析階段的紀錄；後續 Cygni 生成、建模和遊戲檢查見 [Cygni 示範 README](cygni_runtime_v2/README.md)。** 本輪另補入連續頭殼、原 UV 與 Blender 局部改造規則，不能把舊分析表的 NOT RUN 當成現在沒有試作。

**本次完成的是全原素材分析和生成規格；依使用者最新安排，新素材由後續 sol6.1 工作生成。** 目前的參考圖都是原資產擷取或排版，沒有把新的 PNG、模型或材質套到遊戲。

| 檢查 | 狀態 | 證據／限制 |
| --- | --- | --- |
| SW 全套 mesh／材質／PNG 清單 | PASS | 21 套、84 mesh、105 PNG；逐項可追溯 |
| CoM 原件驗證 | PASS | 8 DAE、24 PNG 與 ZIP 位元組相同 |
| 全套參考擷取 | PASS | Godot 4.7.2、Compatibility、640×720、116 張；選定視圖與全部 atlas 彙整為參考頁 |
| 全家族與全部 atlas 目視歸納 | 完成觀察 | 見 5 張 corpus 圖與兩張 family 圖；不是數值化的「風格相似率」 |
| Claude 統計複算 | PASS（數值複算） | 範圍與中位數重現；修正解讀、數量、個別示例 |
| 新圖片／新模型生成 | NOT RUN | 使用者指定交由 sol6.1 執行 |
| 新素材入遊戲及視覺驗收 | NOT RUN | 尚未有依本版規格生成的素材 |

原版樣式覆蓋全部裝甲；武器、背包、敵人與 UI 是不同素材類別，不以本規格假稱一併完成分析。

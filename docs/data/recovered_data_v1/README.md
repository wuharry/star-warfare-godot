# 原版數據套用（2026-09-16）

[可查閱的 HTML 對照表](index.html) · [完整 76 張原表](tables.json)

遊戲載入 `scripts/core/recovered_game_data.gd`，由這次提供的 `assets/starwarfare_data/resDataSets_raw.bin` 生成。原檔保留不改；CSV/JSON 是附帶摘錄，存在欄位誤標與排序差異，不能直接當 runtime schema 使用。`.gdignore` 阻止 Godot 把這些 CSV 當翻譯表匯入；匯出的遊戲依賴已生成的 GDScript 常數，不需要讀取封存原檔。

## 已套用與保留範圍

| 資料 | 使用者可見的結果 |
| --- | --- |
| 47 把武器（表 13） | 遊戲與商店共用傷害、射速、能量、價格、解鎖階級；補上正射程及帶正負號的持槍減速。射程 0 的武器沿用現有瞄準距離；彈匣、換彈、VFX 仍由既有武器系統處理。 |
| 109 件裝甲／背包（表 14） | 原表數字和原 catalog 核對一致，改為直接引用生成資料；32 件 Call of Mini 外觀仍沿用 Viper 基礎屬性。 |
| 21 組套装效果、44 組技能、8 組武器加成、2 組防禦（15、73–75） | 保留原始有號數解碼，實際 HP／回血恢復原單位；不再乘 0.01。 |
| 玩家與裝甲能力 | 最大 HP = 裝甲＋背包＋套裝 HP，原版基礎 HP 為 0。Viper＋初始背包為 1,400；現有 100 點護盾仍獨立存在。Andromeda 回血 10,000、Attack Shield 每次 100、Impact Wave 22,000。 |
| 11 件消耗品（表 16） | 商店價格、持續時間、效果資料讀取原表；本次沒有新增道具使用介面。 |
| 15 種怪物（表 0；攻擊表 1–11） | 全部進 catalog；現有關卡及開放地圖的 4 種已載入模型按下表套用。其餘 11 種不新增 AI／生成流程。 |
| 12 級軍階（表 17） | 擊殺經驗採用原表，套用裝甲經驗加成，按原門檻解鎖；存入 v4 save。原關卡進度給予的階級下限、資金及裝備保留。 |
| 升級表 18、排程表 19–72 | 已解碼並在 `tables.json` 保留；沒有把 54 張原版子關卡表直接當成目前 8 張單人地圖。此次不新增升級系統、子關卡選擇或完整 Boss 狀態機。 |

| 現有 AI 名稱 | 模型／原版 ID | 基礎 HP | 第一攻擊傷害 | 金錢 | 經驗 |
| --- | --- | ---: | ---: | ---: | ---: |
| crawler | bug01 / 工蟲 0 | 45 | 70 | 90 | 10 |
| spitter | bug03 / 蠍尾蟲 2 | 35 | 100 | 160 | 15 |
| brute | bug04 / 自爆蟲 3 | 25 | 300 | 130 | 20 |
| boss | boss01 / 龍 10 | 80,000 | 700 | 299,999 | 60,000 |

`brute` 是復刻版既有內部名稱；原版 `bug04` 的身分是 Boomer，不能誤配為大型甲蟲。此次保留其既有近戰 AI，沒有宣稱已還原自爆行為。原表 Boss 移速／首招間隔為 0，由原版狀態機驅動；目前沿用復刻版 Boss 的移動和動作計時。其遠程招式仍由原有動作倍率處理。近戰表射程 0 沿用模型近戰距離。

關卡 HP 倍率以第一關第一波 1.0 為基準，保留復刻版關卡／波次增幅；精英保留現有 HP ×1.65、移速 ×1.16、傷害 ×1.35、金錢／經驗 ×2。這些是明確的復刻版調整，不是假稱從原表讀出。每次擊殺直接計入戰局金錢，經驗加入角色；通關、開放地圖結算或返回主選單時存檔。一般關卡的金錢仍按原有通關規則結算。

## 欄位核對依據

核對本機復原 C#：`Star-Warfare-1.0.2/Assets/Scripts/Assembly-CSharp/`（不依賴該外部目錄執行遊戲或重建）。

| 原始程式 | 確認事項 |
| --- | --- |
| `Weapon.LoadConfig`、`WeaponFactory.CreateWeapon` | 表 13：[1] damage、[2] signed short /100 射擊間隔、[3] range、[4] signed byte /10 爆炸範圍、[5] splashDamage、[7] signed byte /10 speedDrag、[8] 能量、[9/10] 金錢／秘銀、[11] 武器類別、[13] 解鎖軍階。 |
| `Enemy.LoadConfig` | 表 0：[1] HP、[2] 移速、[3] 攻擊表 ID、[4] 經驗、[5] lootCash；附帶 JSON 的 `score` 名稱有誤。 |
| `GameWorld`、`EnemyType` | `bug01..08` 對應 ID 0..7；`boss01` 是 Dragon ID 10。附帶 JSON 將龍排到最後，不能拿其陣列 index 當 ID。 |
| `LocalPlayer.Init`、`Player.Init` | 玩家 MaxHp 從 0 加上裝備 HP；持槍移速加上 Weapon.GetSpeedDrag 後至少 3.5。 |
| `Item.LoadConfig` | 表 16 效果與價格；Force Shield 的 206 是 signed byte -50，代表 50% 減傷。 |
| `Rank.LoadConfig` | 表 17 軍階名稱和累積經驗門檻，最高 20,000,000。 |
| `EnemySpawnScript`、`WeaponUpgrade.LoadConfig` | 表 19+ 是 stage/substage 生成組合；表 18 是武器升级價格／傷害百分比，不能誤用於軍階。 |

此次核對另外修正舊武器常數中三處誤放欄位：Morpheus / Spreader 的 100、XMAX-TREE 的 20 屬於射程，原表 splashDamage 都是 0。其餘 44 列既有主要武器欄位一致。

## 重建和驗證

```powershell
python tools/update_recovered_game_data.py
python tools/update_recovered_game_data.py --check
& ./.tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/recovered_data_test.tscn
```

`recovered_data_test` 檢查實際載入的遊戲與玩家：武器價格／戰鬥值、RPG 彈匣欄位誤讀防護、怪物生成／受擊／擊殺獎勵只發一次、HP 單位、軍階門檻、舊存檔與大額測試資金、經驗存取。所有有存檔的本次測試使用獨立測試路徑。

實際通過：`recovered_data_test`、`armor_system_test`、`props_store_test`、`armor_power_test`、`enemy_ai_test`、`weapon_fire_feedback_test`、`menu_equipment_test`、`expanse_test`、`reload_catalog_running_test`（55 組跑動動作／24 把飛行武器）、`smoke_test`、`settings_test`。後兩者用忽略目錄中的繼承場景設定獨立存檔與初始裝備，原測試 assertions 不變。詳見 [驗證紀錄](verification.json)。部分測試結束有既有字型／CanvasItem 清理訊息；無 GDScript 解析錯誤。這些結果不等於完成原版全部 AI 與戰役還原，也不代表新數值的完整難度平衡已經遊玩驗收。

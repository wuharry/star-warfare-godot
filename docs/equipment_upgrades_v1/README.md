# SW1／Call of Mini 裝備升級

已將來源的逐級數值與費用接入桌面、手機、存檔及 WarfarePlayer。可開啟 [逐級查詢與八張遊戲截圖](index.html)。

## 來源與邊界

| 來源 | 已核對證據 | 使用方式 |
| --- | --- | --- |
| `原資料/Star+Warfare_Alien+Invasion_3.01_APKPure.xapk` | [resDataSets 比對](../reconstruction_v1/sw1/data_verification.json)；table 18 為 8 × 2，SHA-256 `5b29368724eb16e5335d26bec215a6939bf9480c2076bf4c3c1f7b2dfc0e39bd` | `assets/starwarfare_data/resDataSets_raw.bin` 與 APK 資料逐位元一致；重用既有解碼器。 |
| 既有 SW1 1.0.2 還原程式 | `E:/Star-Warfare-1.0.2/Assets/Scripts/Assembly-CSharp/WeaponUpgrade.cs`、`Weapon.cs` 的 `Upgrade`／`GetDamageUpgradePrice`／`SimpleDamage`、`Global.MAX_LEVEL_WEAPONW`、`CustomizeUI.cs` | 用於辨識表格欄位、原始傷害累加、百位截斷、七個升級圖示。3.01 APK 是 IL2CPP，這些 C# 消費端不是宣稱由 3.01 反編譯而來。 |
| `原資料/Call+of+Mini™+Infinity_2.6_APKPure (1).xapk` | 同包 `Assembly-CSharp.dll` 的 `CoMHalo.DataConfig::LoadAvatarElement`、`ShopUITransaction::Upgrade_Avatar`、`CoMHalo.GameData::UpgradeAvatar` | `Config/AvatarConfig` 的逐級 HP／Shield 加成及下一級 Gold／Crystal 費用。沿用 [八套映射](../reconstruction_v1/com/mapped_armor.json) 中的原始欄位，並非 `Config_Android`。 |

CoM 方法的本地 IL 證據位於 `test_output/source_reconstruction/com/assembly_il.txt`，方法宣告行分別為 172268、321892、148652。原始 DLL 位於 `test_output/source_reconstruction/com/raw/assets/bin/Data/Managed/Assembly-CSharp.dll`。這些為既有 APK 解析輸出，未將整份大型 IL 再複製入 Git。

本次裝備升級涵蓋目前的 47 把 SW1 武器，以及 8 套 CoM 裝甲的生命／護盾。CoM 等級特殊被動、弱點、暴擊連鎖、天賦及進化系統尚未移植，介面不宣稱那些能力生效。SW1 裝甲／背包沒有另外添加升級表；Thunder 的 SW2 模型只作外觀。

## 原始規則

SW1 傷害按原始基礎值累加；升級費用使用武器的原始點數售價，即使該武器購買時使用秘銀。費用以百為單位向下截斷：`floor(原價 × 本級費用百分比 / 10000) × 100`。所有 47 × 7 段費用已與原程式 float32 運算比對，329 筆相符。

| 到達等級 | 本次費用／原點數售價 | 本次增加／基礎傷害 | 累計傷害倍率 | FR28a 費用／傷害 |
| --- | --- | --- | --- | --- |
| 1 | — | — | 1.00 | —／20 |
| 2 | 30% | 15% | 1.15 | 4500／23 |
| 3 | 50% | 20% | 1.35 | 7500／27 |
| 4 | 70% | 25% | 1.60 | 10500／32 |
| 5 | 100% | 30% | 1.90 | 15000／38 |
| 6 | 200% | 40% | 2.30 | 30000／46 |
| 7 | 300% | 50% | 2.80 | 45000／56 |
| 8 | 450% | 70% | 3.50 | 67500／70 |

射速、能量、彈匣、換彈及原始次要 splash damage 不隨這條傷害升級曲線改動；原 `Weapon.Upgrade()` 只改主傷害。

CoM 原索引 0–6 顯示為 LV 1–7。`UpgradePropAddPer` 累加到 1 後乘原始 HP／Shield，不逐級相乘。四部件共用一個 `armor_set_levels[set_id]`，每件占升級後整套數值的 25%；扣款只發生一次。角色基礎 HP、背包與既有套裝加成另算。

| 到達等級 | 累計 HP／護盾倍率 | Assault Armor 單次費用 |
| --- | --- | --- |
| 1 | 1.0 | — |
| 2 | 1.2 | 2000 點數 |
| 3 | 1.4 | 5000 點數 |
| 4 | 1.6 | 10000 點數 |
| 5 | 1.8 | 25 秘銀 |
| 6 | 2.1 | 49 秘銀 |
| 7 | 2.5 | 99 秘銀 |

各套裝費用讀自己的 `BuyMoney`／`BuyCrystal` 陣列；上表不是共用硬編碼。這八套 Config 資料沒有 Obsidian 支付欄位。

## 資料流與存檔

```text
SW1 table 18 / CoM AvatarConfig
              ↓
EquipmentUpgradeRules → GameState.get_upgrade_quote
                              ↓
桌面升級按鈕／手機 UPGRADE → EquipmentUpgradeDialog
                              ↓
GameState.upgrade_equipment(item_key, expected_level)
     所有權／等級／餘額重查 → 扣款 → 原子存檔
                                          ↓
                         equipment_upgraded / store_changed
                                          ↓
                 GameState.get_weapon_data / get_armor_item
                                          ↓
                         WarfarePlayer + 裝備預覽
```

存檔版本 5 加入 `weapon_levels` 與 `armor_set_levels`，舊存檔缺少欄位時從 LV 1 起算，保留金額與所有權。拒絕未知裝備與錯誤型別；有效整數限於來源最大等級。存檔失敗時撤回本次扣款和升級，不發成功訊號。重複確認同一張報價會因等級已改變而拒絕。

## 驗證

| 檢查 | 結果 |
| --- | --- |
| `equipment_upgrade_test` | PASS：逐級費用／傷害、四部件共享等級、全目錄、實際射擊傷害、生命／護盾、保留換彈與子彈、升級存檔重載、舊存檔、壞資料、存檔失敗撤回。 |
| `equipment_upgrade_ui_test` | PASS：桌面與手機點擊／確認、Tab／Enter、Esc、取消不扣款、背景滑動鎖住、固定報價目標、餘額不足、滿級、文字布局。 |
| 裝備回歸 | PASS：`mobile_customize_sw1_test`、`mobile_store_sw1_test`、`desktop_armory_ui_test`、`menu_equipment_test`、`armor_system_test`。 |
| `source_reconstruction_test` | 行為斷言 PASS；退出另報 2 ObjectDB instances leaked、1 resource still in use，並非完全無警告。 |
| 畫面 | GPU capture PASS；已檢視八張 1280 × 720 截圖，Compatibility / OpenGL 3.3。手機使用強制手機布局，Android／iOS 實機 NOT RUN。 |
| 生成資料 | `update_recovered_game_data.py --check`、`build_equipment_upgrade_review.py --check` PASS。 |
| Harness | FAIL：既有 13 個 generated drift；本次未修改這些 harness 檔案。 |

故意測試無法寫入的路徑與損壞的存檔，會印出相應 warning；它們是失敗路徑測試的預期結果。新測試使用隔離存檔並核對正式存檔雜湊。

```powershell
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --editor --path . --quit
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/equipment_upgrade_test.tscn
& .tools/godot-4.7.2/Godot_v4.7.2-stable_win64_console.exe --headless --path . res://tests/equipment_upgrade_ui_test.tscn
# GPU 截圖：上一條移除 --headless，場景路徑後加入 -- --capture。
# 將紀錄放到 test_output/equipment_upgrades 對應 log 後：
python tools/build_equipment_upgrade_review.py
python tools/build_equipment_upgrade_review.py --check
python tools/update_recovered_game_data.py --check
```

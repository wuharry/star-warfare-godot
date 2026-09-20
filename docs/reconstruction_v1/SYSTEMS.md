# 數值契約與實際套用

數值依來源身份對應，不依相同英文名稱直接覆蓋；Thunder 的 SW2 頭盔素材仍屬外觀，本作 Thunder 裝備數值採 SW1。

| 來源 | 解碼契約 | 現在的消費端 |
| --- | --- | --- |
| SW1 `resDataSets` | 76 張表、32342 bytes；逐位元等同 `assets/starwarfare_data/resDataSets_raw.bin` | `recovered_game_data.gd` → GameState、ArmorCatalog、PropsCatalog、MonsterCatalog；沿用既有已核對的欄位單位 |
| SW2 `data/datatable` | `DataTableScript` component，32-byte header 後為 227 張具名表；逐列字串陣列，消費完整 2169816 bytes | `sw2/tables.json` 與 HTML；本輪沒有將未核實的欄位裝進 SW1 catalog |
| CoM `Config/` | 原 DLL DataConfig.Load* 直接載入 Config/；Config_Android 是另一份同包資料，分開保留 | `recovered_com_data.gd` → ArmorCatalog、GameState、WarfarePlayer、UnityEquipmentShell |

SW1 欄位細節與原始表見 [既有欄位證據](../data/recovered_data_v1/README.md)與[數值查詢頁](../data/recovered_data_v1/index.html)；此處沿用同一份 SW1 數值來源。

## CoM 整套裝甲適配

| 項目 | 原作證據 | 本作規則 |
| --- | --- | --- |
| HP／護盾 | AvatarConfig.HP／Shield；Avatar.Initialize、Player.CalcMaxHp／CalcMaxShield | 原 HP、護盾各除以 4 分到現有四部件；混搭逐件相加。原 SW1 四件各持有 25 點護盾，維持原有 100 基準。 |
| 玩家基礎 HP | Player.CalcMaxHp：`1 + (level - 1) * 5` | 只有完整 CoM 套裝加入此基礎值；既有 SW1 背包與套裝加成仍獨立計算。 |
| 護盾恢復 | ShieldRestoreTimeLimit／ShieldRestorePercent；Player.CalcShieldSelfRestoreSpeed | 完整 CoM 套裝才啟用；停止受傷後延遲，按最大護盾比例每秒恢復；再次受傷重置延遲，不超上限。跨過延遲邊界的一幀只計剩餘時間。 |
| 售價 | BuyMoney／BuyCrystal 的第 0 級；ShopUITransaction.Buy_Avatar | 整套只收費一次，取得四個部件；金幣對應點數、水晶對應秘銀。UnlockGold／UnlockCrystal 是另一種提早解鎖交易，不能誤當普通售價。 |
| 解鎖 | UnlockLevel + LevelExp；GameData.AddExp／GetLevelUpgradeExp | 用本作累積經驗換算 CoM 的來源等級，獨立於 SW1 軍階。原程式用「目前等級」查表，1→2 與 2→3 都消耗 250；本作換算上限 31。 |
| 舊存檔 | 原本可能只買到 CoM 某個部件 | 正常載入時補齊同套所有權；不扣款，不變更目前裝備。這輪所有測試使用隔離存檔，未寫使用者正式存檔。 |
| 裝備升級 | UpgradePropAddPer、BuyMoney／BuyCrystal；LoadAvatarElement、Upgrade_Avatar | 已接入 CoM 七級生命／護盾升級，四部件共用套裝等級與一次扣款；SW1 武器依 table 18 升至八級。[規則、驗證與畫面](../equipment_upgrades_v1/index.html)。 |
| 特殊被動 | WeaknessDesc、LevelDesc、Player 內條件分支 | 原資料完整保存；弱點／擊殺連鎖／PvP 特殊被動尚未移植，不把描述文字當作已生效能力。 |

例如 Assault Armor 普通購買是 8000 點數、來源等級 7；12000 的 UnlockGold 是另一種來源交易，不替換普通價格。四部件 HP 各 32.5，合計 130，整套護盾合計 250。

## 數值與音效的資料流

```text
XAPK → APK / OBB → Unity TextAsset / MonoBehaviour
                           ↓
                 build_source_catalogs.py
                           ↓
                 recovered_com_data.gd
                           ↓
       ArmorCatalog → GameState → WarfarePlayer / 商店

AudioClip → 解碼 PCM → 去重 → recovered_sources/catalog.json
                                      ↓
                     RecoveredSourceAssets → AudioDirector
```

SW1 原版使用共同能量池，現在的彈匣與換彈是已接受的現代化設計。這輪保留原傷害、射擊間隔與能量值，也保留現有換彈；不把射擊間隔欄誤認為彈匣容量。

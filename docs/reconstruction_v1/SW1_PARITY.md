# SW1 原版功能補齊（2026-10-30）

本次以本機 `star-warfare/Assets/Scripts/Assembly-CSharp` 與原始 `Resources` 為依據。使用者排除 Bank、廣告及彈藥購買／補充服務；已接受的彈匣換彈、既有額外地圖及混搭裝備保留。SW2／CoM 的完整遊戲並非本次原版範圍。

## 實際入口與資料流

| 功能 | 玩家入口／行為 | 實作 |
|---|---|---|
| 原版單人關卡 | 選地圖後選五個任務或生存；SKIRMISH 保留原有自訂波次 | `solo_missions.gd`、`solo_wave_data.gd`、`mission_director.gd`；原 tables 19–66，共 48 表、1,977 列 |
| 關卡進度 | 按順序開子關，第五子關首通獎金只領一次；軍階按 XP | `GameState.is_solo_mission_unlocked/settle_solo_run`；保留舊存檔已開地圖與裝備 |
| 戰鬥道具 | PACKAGE 帶入補血、Assist、急救包，戰鬥圖示或 Z/X/C/V/B/N/M/, 使用 | `battle_items.gd`、`battle_items_bar.gd`；原 11 種道具，先保存消耗再生效 |
| 復活 | 死亡後限時使用急救包，恢復 30%／100% HP | 保留彈匣狀態；回復視角、動畫、操作及波次排程 |
| 連殺及生涯 | 戰鬥連殺加成、個人紀錄、原 23 個成就 | `battle_progress.gd`、`career_progress.gd`、`career_panel.gd` |
| 商店優惠 | 原候選槍與軍階條件的限時折扣，購買價與顯示價一致 | `store_offers.gd`；只有購槍累計來源的秘銀使用量 |
| 原敵人與 Boss | 一般敵人依原數值、出生入口與行為；六種 Boss 場景 | `monster_catalog.gd`、`enemy_source_*`／`enemy_*_brain.gd`、`assets/models/boss_arenas` |
| 敵人狀態效果 | 地面危險區減速、離開恢復；受擊位移與受擊動畫期間中斷射擊／衝刺 | 原版每 Update 的擊退位移以 60 Hz 轉為每秒速度，使用碰撞移動；朝向取人物 `body_yaw` |
| 多人模式 | 直接 IP／同網段房間；Survival、Boss、FFA、TDM、兩種 CTF、VIP、CMI | `NetworkSession`、`match_rules.gd`、`network_world.gd` |
| 多人特殊武器與技能 | 使用原版彈道、散射、追蹤、反射、穿透、爆炸與持續傷害；技能使用來源形狀與重複命中規則 | `network_projectile.gd` 共用單人投射物，房主處理碰撞／傷害；客戶端只播放同步的外觀與特效 |
| Boss 秘銀 | 全部 Boss 死亡且整場勝利，每位參與者固定 1 秘銀 | 使用者明確選定的離線替代規則；雙 Boss 算一場，不是每隻給 1 |
| 裝甲還原 | Viper 維持現狀，其餘 28 套回到來源模型與貼圖 | SW1 使用 `player.gltf` 的原版 2× 圖集；Assault 由原始 CoM DAE 重建綁定轉換，移除早期覆寫的重製身體；同步重建 112 張非 Viper 部位縮圖 |

## 存檔與連線契約

- 戰利品在通關或敗北結算；裝備與連殺加成只套一次。`run_id` 保存結算收據，收到同一結果不能重領。存檔失敗回復錢、XP、關卡和當局生涯結果，保留重試資料。
- Expanse 的重新開始／離場先結算，失敗保留世界與重試畫面。退出程序／斷電仍不能被當作已完成一次存檔。
- 多人由房主驗證輸入、傷害、勝敗和獎勵。它不是原官方伺服器；修改本機存檔或惡意房主仍屬直接連線的信任限制。
- 多人道具依請求識別去重，已收到的消耗在離房、換槽或重連後會重試保存；若 ACK 與快照都未收到便斷線，或強制退出造成尚未持久化的欠扣遺失，尚無跨程序交易保證。
- 急救包遵循死亡動畫 4 秒加使用窗口 5 秒；包含單人 host、全隊倒地與 PvP。成功使用後取消原本的自動復活排程，不會再復活一次。
- LAN 搜尋只傳房名、模式、地圖、人數與遊戲 port。使用 nonce、封包大小／每幀數量限制、回覆節流及房間過期；不傳背包或存檔。
- Android 匯出需要 Internet permission；各平台匯出必須包含場地 `level.json`，否則美術在、碰撞和出生點卻會消失。

## 驗證與限制

| 檢查 | 已取得的證據 |
|---|---|
| 來源資料與排程 | 48 表／1,977 列逐列相符；子關排程及無盡迴圈測試通過 |
| 單人實場 | 首關 35 敵人／11 組完整勝利與開關；八張地圖 89 種實際使用的敵人／入口組合載入通過 |
| 道具與結算 | 補血、Assist 到期／刷新、復活、暫停、存檔失敗、重複結算、生涯回復、Expanse 離場重試通過 |
| Boss 場地 | 六張原 prefab，763 項資源／碰撞檢查；25 個出生點地面命中、18 個玩家站立檢查通過 |
| 場地畫面 | 1280×720 GL Compatibility 六張 arena 圖已檢視；靜態貼圖、UV2、光照保留 |
| LAN 發現 | 實際 UDP 查詢、更新、錯 nonce、非法人數、關閉過期通過 |
| 匯出資源 | 本地 Windows Desktop PCK 匯出與啟動通過；獨立 probe 確認 23 張場地 metadata／美術、14 個基礎敵人模型、三份特效 metadata，以及 17 種武器的 34 個投射／命中特效實例與所需音效；95 個程式／場景／設定檔與匯出前 hash 一致 |
| 敵人行為 | 來源敵人／Boss runtime 306 項通過；單人減速進出、正反向擊退、牆壁碰撞、中斷射擊及復活清除狀態通過 |
| 多人及 Boss 戰鬥整合 | 八模式實際雙程序傷害／比分／結算／退出通過；規則 70 項、道具／技能／急救／重送去重、六場 Boss／雙螳螂／固定秘銀通過 |
| 多人特殊攻擊 | 實際 ENet 雙程序 host 52／client 9 項通過：追蹤、穿透、反射、牆壁引爆、UFO 彈雨、機器人／黏液、友軍過濾、技能形狀與標記；客戶端副本不造成傷害 |
| 共用武器特效 | 17 種原版投射物、命中特效及特殊機器人通過 GL Compatibility 檢查；材質由每個 effect 的 mesh 持有，保留幾何快取，單人／多人共用且乾淨退出 |
| 裝甲 | 28 套原始 mesh／skin／圖集與動畫檢查、85 個武器 mesh 回歸、Viper 幾何／材質／混搭、商店操作通過；Viper 四張縮圖 hash 未變。18 張實場／動作擷圖已產出並檢視代表畫面；手機卡片保留原色與材質，桌面切換安全釋放預覽 |

所有會寫資料的測試使用隔離 profile。Godot headless 成功不代表 Android／Windows 實機或視覺全數通過。原官方配對、帳號、雲端排行與其伺服器設定不在現有來源中，未宣稱恢復那些服務；LAN／直接 IP 是本次可執行的替代。Boss 場景的動態燈光、原粒子播放與貼圖動畫未完整重現，不能將靜態場地匯入稱為逐畫面還原。

多人技能波的碰撞形狀、尺寸、傷害與重複命中遵循來源，外觀仍使用替代特效；未宣稱技能特效逐畫面一致。

手機商店 GL 擷圖測試曾一次在合成點擊後找不到升級視窗；獨立 profile 的 GL、GL 擷圖及游標診斷三次重跑均通過，根因未確認。測試已先檢查視窗有效性，避免失敗時直接解參照 null；未為此改動產品點擊時序。

原優惠的兩項修正：使用 Unix 時間計一天到期，避免原 12 小時字串歧義；候選列表最後一項也可抽中，避免原 `Random.Range` 上界錯誤。

## 重跑

使用現有 Godot 及 Python；不需要新增依賴。從 repo 根目錄執行：

```sh
python3 .harness/verify.py --list
python3 .harness/verify.py --run --only godot-original-missions
godot --headless --path . res://tests/lan_discovery_test.tscn -- --test-profile=lan_verify
godot --headless --path . --export-pack 'Windows Desktop' test_output/parity-content.pck
godot --headless --main-pack test_output/parity-content.pck --script "$PWD/tests/pack_content_probe.gd" -- --test-profile=pack_probe
```

`--export-pack` 僅產生本地驗證資源包，不是部署。測試腳本排除在正式匯出外，probe 以外部腳本讀取 pack 內的正式資源。

`python3 tests/network_suite.py VS_TDM --combat --port 24948` 可重跑特殊攻擊雙程序檢查；`--transport` 與 `--combat` 互斥。工具會建立輸出目錄，逾時一定判失敗，結束時有期限地終止、強制停止並回收兩個子程序；單一子程序清理失敗不會跳過另一個。

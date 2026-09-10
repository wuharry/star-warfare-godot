# 非原生音效試聽與來源

2026-09-10：從 `assets/original/audio/combat/` 搬出；音訊內容保持原樣，只改用途名稱及程式路徑。
直接開啟本目錄 `listen.html` 試聽。原生對照仍位於原資料夾，沒有搬進非原生分類。

| 新檔名 | 原檔名 | 現在用途／播放條件 |
| --- | --- | --- |
| enemy_hit_light.wav | flesh_hit_light.wav | 敵人普通受擊，3D，-4.5 dB，音高 0.92–1.06 |
| enemy_hit_heavy_or_lethal.wav | flesh_hit_heavy.wav | 重擊或致死命中，3D，-2.5 dB，音高 0.92–1.06；不是 HUD 擊殺確認 |
| weapon_reload_magazine_eject.wav | reload_eject.wav | 非逐發裝填武器開始換彈，3D，-4.5 dB |
| weapon_reload_magazine_insert.wav | reload_insert.wav | 彈匣／能源匣插入，3D，-3.5 dB |

掃描本專案 assets 下所有音訊並比對 Unity Assets 音訊 SHA-256（LFS pointer 以 oid 比對）：共 203 個，199 個相符，只有這四個沒有原版相符檔案。`assets/audio` 其餘音檔是原版副本。

HUD 命中用 `menu/exp.wav`（-14 dB、音高 1.08）；HUD 擊殺用 `pickup/killcombo.wav`（-9 dB、音高 1.02），兩者都與 Unity 原始檔內容一致，但目前用途是後加的暫時設計。致死時可能疊上外加重擊、原版敵人死亡與 HUD 確認音。風格是否合適需在遊戲混音中試聽，來源相同不代表用法相同。

此外 `player.gd:on_damage_dealt()` 每次有效傷害會播原版 `enemies_smash2.wav`（-7 dB、音高依傷害限制在 0.98–1.08，key 為 `local_hit_confirm`），再送出 HUD 命中 signal。因此排查違和感不能只聽 `killcombo.wav`；也要檢查玩家確認、敵人撞擊與 HUD 提示的重疊。本次只整理路徑，不改這些行為。

下列來源沿用原 README 記錄。本次在工作區、兩個相鄰 Star Warfare 專案與 Downloads 的檔名清單未找到那五份 ZIP；`.gitignore` 有 Sonniss 2026 來源包規則。不代表磁碟其他位置沒有。未重新取得原包授權附件，請保留原包與授權，不把本資料夾單獨當素材包發布。

These runtime-ready files were extracted from the user-provided
`Sonniss.com-GDC2026-GameAudioBundle2of5.zip` (historical provenance; ZIP unavailable in the inspected locations).

| Runtime file | Original archive entry | Use |
| --- | --- | --- |
| `flesh_hit_heavy.wav` | `Epic Stock Media - Halloween Game - Haunted House and Horror Audio Scare Kit/GORESplt_Gore Designed Transient Heavy Impact Smash 01_ESM_HALG.wav` | Heavy or lethal bug impact |
| `flesh_hit_light.wav` | `Epic Stock Media - Tower Defense Game/WOODImpt_Hit Blood Spill Splat Wood Impact Light Hit Squelch Small Thump 03_ESM_TDG.wav` | Normal bug impact |
| `reload_eject.wav` | `Epic Stock Media - HD Lock And Mechanism Sound Design Kit/MACHMech_Mechanism Counting Machine Interact Loose Container Short 01_ESM_HDLM.wav` | Reload start / magazine release |
| `reload_insert.wav` | `Epic Stock Media - HD Lock And Mechanism Sound Design Kit/MECHLtch_Click Deep Mechanism Latch Button Nearfield Thunk 02_ESM_HDLM.wav` | Magazine seating / latch |

The game layers the positional flesh impact with a short non-positional hit
confirmation so feedback stays readable during crowded fights.

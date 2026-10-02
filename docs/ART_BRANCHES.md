# 美術分支用途

**新版裝甲與原版高清備用版使用兩條分支，避免把不同美術方向混在一起。** 2026-10-02 使用者要求改名；原版備用版等版權方回覆授權 email 後，再決定是否繼續使用。

| 分支 | 前身 | 用途 |
| --- | --- | --- |
| `codex/new-armor-design` | `codex/original-armor-design` | 新版裝甲製作；新版 Cygni 預設替代原版，中央白色凸起已移除 |
| `codex/original-hd-backup` | `art/thunder-original-helmet` | 保留原模型與既有高清貼圖；原版頭盔與配色修復，作為備用 |

## 回家後接續

**繼續做新裝甲請使用 `codex/new-armor-design`。** 正常啟動即可在商店／配裝的 Cygni 四部件查看，無須 `--cygni-v2`。模型及來源見 [Cygni 工作入口](art/cygni_runtime_v2/README.md)。

```bash
git fetch origin
git switch codex/new-armor-design
git pull --ff-only
godot --path .
```

**查看原版高清備用版請切換至 `codex/original-hd-backup`。** 切換前保留手上的未提交修改；兩個分支仍保留原始來源及既有歷史，美術替換不改裝備數值或持有狀態。

```bash
git switch codex/original-hd-backup
git pull --ff-only
godot --path .
```

## 共用的頭盔配色修正

**原版 Cygni、Pegasus 的頭盔改用同套身體的中性色乘值，移除匯入的紅色染色。** 原 PNG、網格和 UV 不變；只複製並修正材質。原件、遊戲 loader、重複換裝及存檔保護由 `tests/original_helmet_color_test.tscn` 驗證。新版 Cygni 自己的配色不受這項原件修正影響。

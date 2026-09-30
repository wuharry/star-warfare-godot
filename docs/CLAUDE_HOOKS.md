# Claude hooks：跨平台 checkout

`.claude/settings.json` 使用 `CLAUDE_PROJECT_DIR` 執行 `.harness/claude_hook.py`。
`.codex/hooks.json` 沿用現有事件設定，從專案根目錄執行同一支腳本；不需要設定 Mac 或 Windows 的固定絕對路徑。
兩者都需要 `python3` 可執行。這次沒有更換各工具的事件格式或新增權限。

## 2026-09-30 修復

Windows 的 `core.autocrlf=true` 會將 checkout 的文字轉成 CRLF。
`.harness/lock.json` 記錄的是原本 LF 檔案的 SHA256，因而使 Claude 的 `Stop` 誤報 13 個 `generated drift`。
`.gitattributes` 現在為 `.claude/`、`.harness/`、`.codex/*.json`、`AGENTS.md` 與 `CLAUDE.md` 固定 `text eol=lf`。
本次保留所有原始 lock 雜湊及檢查邏輯，沒有降低檢查標準或關閉 Stop。

如果現有 checkout 仍顯示換行差異，先檢查並保存本機編輯，再重新 checkout 相關檔案；不要重算 lock 來消除警告。

## 驗證

從專案根目錄執行：

```sh
python3 .harness/verify.py
python3 -B -m unittest discover -s tests -p test_claude_hooks.py -v
```

測試直接執行兩份設定中的 Bash 命令，涵蓋中文提示、保護檔案拒絕、一般讀取、編輯後提醒，以及正常 Stop。
獨立暫存資料會驗證真正的檔案內容異動仍被 Stop 阻擋，且不會無限阻擋同一次結束。
沒有 Bash 時命令測試會明確標記為略過；這些測試不代表 Claude／Codex UI 已重新載入設定，也不驗證遊戲功能。

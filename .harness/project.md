# star-warfare-godot — 專案契約



此檔是 repo-specific 來源，可直接維護；共用政策改 ai-wrapper/rules 後同步。



Godot / GDScript；入口：res://scenes/main_menu.tscn。

程式在 scripts/；節點路徑、autoload 與 renderer 以 project.godot 為準。

autoload：GameState, AudioDirector, Localization。

tests/ 已有邏輯測試場景與 visual_capture 場景；不要把「原本缺 harness」誤寫成「沒有測試」。

煙霧測試只驗證其 assertions；HUD／動畫／光影另跑對應 capture 並檢視輸出，記錄 viewport、renderer 與觀察。



## 驗證



精確命令維護在 `.harness/project.json`；`python3 .harness/verify.py --list` 列出，`--run --only ID` 執行。

未安裝工具、需要外部服務或人工視覺驗收時標 NOT RUN，不能回報全綠。

# 裝甲設計候選 v2：保留辨識特徵、加大造型差異

2026-09-11。Harvey 在 v1 生成途中指出「每張裝甲要有差異性大點」「還是能稍微看出原來的特色」。因此停止 v1，逐套檢視既有頭盔／胸甲縮圖，改用各套自己的參考圖與專屬造型規格。

## 產物與限制

- 範圍為 ArmorCatalog.SET_NAMES 的 29 套人物裝甲（頭、身、手、腿）；不含背包商品與武器。
- 00 是使用者要求保存的 Viper／Assault 風格基準，保留原檔不改。其餘逐套重新生成，使用內建 imagegen，不是原 UV 貼圖換色。
- 每套 prompt 明列原辨識特徵與新結構。原槽位名稱只是內部對照，不作新遊戲商品名。
- 這些是概念設計圖，不是可載入的 3D 模型、UV 貼圖或已批准定稿。角色比例、多視角一致性、穿模／動作須在建模階段重新驗收。
- 刻意保留原辨識特徵不等於權利已清理；本批沒有商用安全保證。需另外評估授權與新設計相似程度。
- 不修改遊戲、商店、模型、動畫或使用者存檔。v1 是已停止的草案，不當完成版。

## 交接

Objective: 全槽位外觀探索，明顯造型差異且保留原特色。Owned paths: docs/art/armor_concepts_v1/、docs/art/armor_concepts_v2/。

Inputs: 現有 armor_head／armor_body 縮圖、已保存的風格基準、使用者規則。Outputs: images/、prompts/、manifest.json、index.html。Acceptance: 全套有檔案、來源和 prompt；Harvey 按套批准後才進建模。Handoff: 查看 manifest 的實際生成狀態與 review_notes；不要把工具成功當成視覺或權利驗收。

開啟 index.html 可依原套裝名稱看圖、原版參考及 prompt；灰階模式只改瀏覽器顯示，不修改原圖。

## 本次檢查

- PASS：29 個不同內容的 PNG、29 份 prompt、所有來源參考與畫廊連結存在；每套均有 review_notes，文字無尾端空白。
- PASS：harness integrity。此結果只代表投遞完整性，不代表美術驗收。
- NOT RUN：瀏覽器互動實測、遊戲 runtime／模型／動畫測試。本批僅新增概念文件，docs/art/.gdignore 阻止引擎匯入。
- 待人工確認：部分頭身比例偏大；部分 LED、條紋與戰損偏多；部分頭冠／側燈跨視角不一致。詳見每套備註，不能略過後直接建模定稿。

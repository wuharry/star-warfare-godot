# 來源、音效與美術契約

所有來源均為使用者提供的本機 XAPK；`sources.json` 記錄三作版本和完整包 SHA，逐個 Unity 物件另有檔案與 path ID。來源不需要網路，也不引用過去已搬走的工作路徑。

| 素材 | 辨識／去重方式 | 正式用途 |
| --- | --- | --- |
| 原作 AudioClip | WAV 的 fmt＋PCM SHA-256，忽略非聲音 metadata；原先保留的 MP3 依同一 SW1 原曲身份重用 | 721 個原作 clip 對應 556 個可載入路徑；334 個來源引用重用現有檔案，387 個補入。 |
| 封存庫中的音效 | 封存區被 `.gdignore`／Git 排除，不可當成遊戲正式引用 | 相同聲音若只存在封存庫，仍需補入一次正式素材庫；不宣稱「檔案存在」就已實裝。 |
| SW1 HUD／武器圖集 | 明確知道既有 PNG 是該來源的 2x 高清版本 | 保留既有圖與原座標倍率，不用 APK 舊圖覆蓋。 |
| SW2 UI | TextAsset 的 TexturePacker frames 與配對 Texture2D | 補入 22 個配對圖集／裁切表；原生 1x 座標，已在資源 catalog 可用。 |
| CoM UI | UIAtlas／UISpriteData 的原字段順序與 Material 參考 | 補入 5 張 UI 圖，Equipments 的 222 個 sprite 有原座標；未購買整套的商店卡片使用原圖示。已擁有部件仍顯示高清部件縮圖。 |
| 裝甲／模型／場景貼圖 | 全部納入 Unity 物件索引，與現有素材身分區分 | 已高清化的 Viper、Fortune、其他裝甲與 Thunder 改模保留。未被現有遊戲使用的模型／光照貼圖留在解析工作區，不無差別匯入。 |

## 已接入的 CoM 聲音事件

| 本作觸發 | 原作 clip | 證據／適配 |
| --- | --- | --- |
| 購買整套成功 | UI_buy | 原 managed UI 交易呼叫同名聲音 |
| 裝備 CoM 部件 | UI_weapon_equip | 原裝備 UI 共用此 equip 聲音 |
| 完整 CoM 裝甲受傷 | Vox_hurt_01 | 採原人聲的一個版本；目前沿用本作受傷播放節制 |
| 護盾開始恢復 | sfx_amour_heal_01 | Player.ShieldOn → `sfx_amour_heal` prefab → TAudioEffectRandom 的 clip 參考，已核對 |

`skills_shield_active` 與 `skills_shield_broken` 也已解析，但不因檔名近似就當作普通護盾恢復聲。原 PlayerShieldBrokenEffect 只有 Transform／ParticleSystem／Renderer；本輪沒有添加無依據的技能盾破裂音效。

12 個尺寸為 0×0 的 Font Texture 是執行時產生的字型頁，沒有可匯出的像素；索引標記 `empty_runtime_generated_texture`，不當作漏失美術。批次匯出未遺漏非空 AudioClip／Texture2D。

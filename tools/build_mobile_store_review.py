"""Package actual Godot captures into an offline review; does not edit images."""
from __future__ import annotations

import hashlib
import html
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAPTURES = ROOT / "test_output/mobile_store_sw1"
OUTPUT = ROOT / "docs/mobile_store_sw1"
PAGES = [
    ("mobile_weapons", "手機 · 武器", "gear"),
    ("mobile_armor", "手機 · 裝甲", "gear"),
    ("mobile_items", "手機 · ITEMS", "props"),
    ("mobile_navigation", "手機 · 導覽選單", ""),
    ("mobile_customize", "手機 · EQUIP", "gear"),
    ("mobile_backpack", "手機 · 背包", "gear"),
    ("mobile_wide", "手機 · 20:9", "gear"),
    ("mobile_source_aspect", "手機 · 3:2", "gear"),
    ("desktop_unchanged", "桌面 · 原本商品格", ""),
]


def main() -> None:
    for filename, token in (("capture.log", "MOBILE_STORE_SW1_PASS"), ("test.log", "MOBILE_STORE_SW1_PASS"),
                            ("desktop_test.log", "MENU_EQUIPMENT_TEST_PASS")):
        log = (CAPTURES / filename).read_text(encoding="utf-8-sig")
        if token not in log or "ERROR:" in log:
            raise SystemExit(f"Missing successful validation: {filename}")
    if (CAPTURES / "capture_errors.log").read_text(encoding="utf-8-sig").strip():
        raise SystemExit("Capture stderr must be clean before publishing this review")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, _, _ in PAGES:
        shutil.copyfile(CAPTURES / f"{name}.png", OUTPUT / f"{name}.png")
    desktop = ROOT / "scripts/ui/unity_equipment_shell.gd"
    committed = subprocess.check_output(["git", "show", "b90c531:scripts/ui/unity_equipment_shell.gd"], cwd=ROOT)
    normalized = desktop.read_bytes().replace(b"\r\n", b"\n")
    if normalized != committed.replace(b"\r\n", b"\n"):
        raise SystemExit("Desktop shell changed; review's unchanged claim needs re-evaluation")
    evidence = {
        "desktop_shell_sha256_lf": hashlib.sha256(normalized).hexdigest(),
        "desktop_comparison_commit": "b90c5312c495899def55aa2c9274413ae2408433",
        "renderer": "Godot 4.7.2 Compatibility / OpenGL 3.3 / RTX 4080 Laptop GPU",
        "tests": {name: (CAPTURES / name).read_text(encoding="utf-8-sig") for name in
                  ("test.log", "capture.log", "capture_errors.log", "desktop_test.log", "data_regression.log")},
        "captures": {name: hashlib.sha256((OUTPUT / f"{name}.png").read_bytes()).hexdigest() for name, _, _ in PAGES},
    }
    (OUTPUT / "validation.json").write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    buttons = "".join(f'<button data-index="{index}">{html.escape(title)}</button>' for index, (_, title, _) in enumerate(PAGES))
    page = '''<!doctype html>
<html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SW1 手機商店 · 實際遊戲檢視</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#10141a;color:#e5edf6;font:16px/1.6 system-ui,sans-serif}main{max-width:1380px;margin:auto;padding:24px}h1{font-size:28px;margin:0}p{max-width:1000px}a{color:#82d9eb}nav{display:flex;gap:8px;flex-wrap:wrap;margin:20px 0 12px}button{border:1px solid #425464;background:#24313f;color:inherit;padding:9px 13px;border-radius:5px;cursor:pointer}button[aria-pressed=true]{background:#125d6a;border-color:#73d3e7}.toolbar{display:flex;gap:22px;align-items:center;margin-bottom:12px;flex-wrap:wrap}.stage{position:relative;background:black;line-height:0;max-width:1280px}img{width:100%;height:auto}svg{position:absolute;inset:0;width:100%;height:100%;pointer-events:none}svg rect{fill:#2dd9d508;stroke:#fcae38;stroke-width:1.5}svg text{fill:white;stroke:black;stroke-width:3px;paint-order:stroke;font:13px sans-serif}small{color:#a5b6c6}table{border-collapse:collapse;width:100%;max-width:1100px;margin:18px 0}td,th{text-align:left;vertical-align:top;border-bottom:1px solid #354150;padding:9px}th{background:#1c2733}.pass{color:#80e9b0}.pending{color:#ffc977}code{overflow-wrap:anywhere}details{margin-top:24px}summary{cursor:pointer;color:#82d9eb}.overflow{overflow:auto}
</style><main>
<h1>SW1 手機商店：原版版面與主要操作</h1>
<p>裝備頁已更新：<a href="../mobile_customize_sw1/index.html">查看 CUSTOMIZE / PACKAGE 最新還原與操作驗證</a>。本頁較早的 EQUIP 截圖為商店階段紀錄。</p>
<p>以下是 Godot 實際執行的截圖。手機使用原版中央角色、裝備與分類滑動；桌面維持既有商品格。使用目前高清模型與本地化文字，沒有宣稱與舊 Unity 畫面逐像素一致。</p>
<nav>BUTTONS</nav>
<div class="toolbar"><strong id="caption"></strong><label><input type="checkbox" id="bounds"> 顯示 SW1 原始座標</label><a id="original" href="mobile_weapons.png">開啟原尺寸圖片</a></div>
<div class="stage"><img id="capture" src="mobile_weapons.png" alt="手機版 SW1 商店實際遊戲畫面"><svg id="overlay" aria-hidden="true"></svg></div>
<small>截圖為隔離測試存檔，包含購買與混搭裝甲測試；不是你的實際存檔。</small>
<div class="overflow"><table><thead><tr><th>檢查</th><th>結果</th><th>證據／限制</th></tr></thead><tbody>
<tr><td>手機商店與操作</td><td class="pass">PASS</td><td>實際 ScreenTouch / ScreenDrag；循環、慣性停靠、雙指、取消、返回、道具滑動不誤購、購買與裝備、整套 CoM 解鎖。</td></tr>
<tr><td>畫面比例</td><td class="pass">PASS</td><td>960×640、1280×720、1600×720 邏輯畫布；保持原始 3:2 版面比例及黑色外框。</td></tr>
<tr><td>桌面商店</td><td class="pass">PASS</td><td>MENU_EQUIPMENT_TEST_PASS；UnityEquipmentShell 與 b90c531 的內容相同，包含 6 分類、141 裝甲部件／背包、47 武器。</td></tr>
<tr><td>資料回歸</td><td class="pass">Assertions PASS</td><td>既有 source_reconstruction_test 退出有 2 個 ObjectDB 與 1 個 resource 清理問題。</td></tr>
<tr><td>武器升級、付費 AMMO</td><td class="pending">未移植</td><td>擁有商品顯示 OWNED；AMMO 說明目前任務補給規則，不扣款；共用能量欄顯示「—」。</td></tr>
<tr><td>Android / iOS 實機</td><td class="pending">NOT RUN</td><td>本次使用 Windows 上的 Godot 4.7.2 Compatibility 與手機模式，並非實機效能或觸感驗收。</td></tr>
<tr><td>Harness 投遞檢查</td><td class="pending">FAIL（既有）</td><td>生成政策檔案漂移，本次未更動。</td></tr>
</tbody></table></div>
<p><a href="README.md">來源、完整範圍與重現指令</a> · <a href="validation.json">驗證紀錄及雜湊</a></p>
<details><summary>座標如何還原</summary><p>從 SW1 resUI.bytes 的 vUI[11]（商店）、vUI[13]（道具）、vUI[19]（導覽列）讀取 module；把 Unity 左下原點轉成 Godot 左上原點。滑動規則對照 UIScroller、UISliderTag、UISliderAvatar、UISliderProps。中央角色使用現有模型重新取景，沒有把商品格縮窄充當手機版。</p><pre>x = anim.x + module.x + 480\ny = 320 + anim.y + module.y - height</pre></details>
<script>
const pages=PAGES;let selected=0;const image=document.getElementById('capture'),svg=document.getElementById('overlay'),bounds=document.getElementById('bounds');
const gear=[[177,494,450,99,'vUI11 / 2'],[726,248,188,21,'vUI11 / 52'],[714,386,212,136,'vUI11 / 50'],[747,526,150,58,'vUI11 / 19'],[712,126,214,12,'HP'],[712,166,214,12,'POW'],[712,206,214,12,'SPD']];
const props=[[275,107,685,450,'vUI13 / 2'],[77,148,88,75,'HEALTH'],[77,278,88,75,'AID KIT'],[77,410,88,75,'ASSIST']];
function draw(){svg.replaceChildren();if(!bounds.checked||!pages[selected][2])return;const w=image.naturalWidth,h=image.naturalHeight,s=Math.min(w/960,h/640),x=(w-960*s)/2,y=(h-640*s)/2;svg.setAttribute('viewBox',`0 0 ${w} ${h}`);const ns='http://www.w3.org/2000/svg',g=document.createElementNS(ns,'g');g.setAttribute('transform',`translate(${x} ${y}) scale(${s})`);svg.append(g);for(const [x,y,w,h,label] of pages[selected][2]==='gear'?gear:props){const r=document.createElementNS(ns,'rect');for(const [k,v] of Object.entries({x,y,width:w,height:h}))r.setAttribute(k,v);g.append(r);const t=document.createElementNS(ns,'text');t.setAttribute('x',x+3);t.setAttribute('y',y-4);t.textContent=label;g.append(t)}}
function select(index){selected=index;image.src=pages[index][0]+'.png';image.alt=pages[index][1];document.getElementById('caption').textContent=pages[index][1];document.getElementById('original').href=image.src;document.querySelectorAll('nav button').forEach((b,i)=>b.setAttribute('aria-pressed',i===index));draw()}
document.querySelectorAll('nav button').forEach((b,i)=>b.addEventListener('click',()=>select(i)));image.addEventListener('load',draw);bounds.addEventListener('change',draw);select(0);
</script></main></html>'''
    (OUTPUT / "index.html").write_text(page.replace("BUTTONS", buttons).replace("PAGES", json.dumps(PAGES, ensure_ascii=False)), encoding="utf-8")
    print(f"MOBILE_STORE_REVIEW_BUILT: {OUTPUT / 'index.html'}")


if __name__ == "__main__":
    main()

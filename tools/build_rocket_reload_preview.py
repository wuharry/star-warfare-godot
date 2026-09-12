"""Build an offline, synchronized A/B viewer from Godot's rocket captures."""
from __future__ import annotations

import json
from pathlib import Path

DIRECTORY = Path(__file__).resolve().parents[1] / "test_output/rocket_reload"
PAGE = r'''<!doctype html>
<html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>RPG-21 · 兩套換彈比較</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#10151c;color:#e5edf5;font:16px/1.6 system-ui,sans-serif}
main{max-width:1500px;margin:auto;padding:32px}h1{font-size:30px;margin:0}p{color:#b9c7d6}
.controls{display:flex;gap:14px;align-items:center;flex-wrap:wrap;margin:22px 0}
button,select{background:#243342;color:#fff;border:1px solid #465c70;border-radius:7px;padding:9px;font:inherit}
button{cursor:pointer}input{width:100%;accent-color:#4cdbc5}a{color:#64dfd0}
.pair{display:grid;grid-template-columns:1fr 1fr;gap:16px}.card{background:#080c10;border:1px solid #334150;border-radius:12px;overflow:hidden}
.card h2{font-size:20px;margin:16px 20px 0}.card p{margin:0 20px 10px;font-size:14px}.card img{display:block;width:100%}
.timeline{margin:14px 0 30px}table{border-collapse:collapse;width:100%;font-size:14px}td,th{padding:12px;text-align:left;border-bottom:1px solid #334150}
summary{cursor:pointer}small{color:#98aabc}#status{min-height:26px}
@media(max-width:780px){main{padding:16px}.pair{grid-template-columns:1fr}}
</style><main>
<h1>RPG-21 · 兩套換彈比較</h1>
<p>同一把火箭筒、同一個時間點。A 收到胸前側轉；B 抬高筒口，在身側裝填。遊戲每次換彈時隨機選擇 A 或 B。</p>
<div class="controls">
<button id="play">暫停</button>
<label>視角 <select id="view"><option value="right_front">右前方</option><option value="front">左前方</option><option value="side">左側</option><option value="rear">右後方</option></select></label>
<label>速度 <select id="speed"><option value="0.25">0.25×</option><option value="0.5" selected>0.5×</option><option value="1">1×</option></select></label>
<label>動作 <select id="mode"><option value="stationary">站立 · 完整動畫</option><option value="moving">跑動 · 關鍵姿勢</option></select></label>
</div>
<div class="pair"><section class="card"><h2>A · 胸前側收</h2><p>離肩 → 側收穩住 → 取彈裝填 → 回肩</p><img id="a" alt="方案 A 換彈動畫"></section>
<section class="card"><h2>B · 立筒裝填</h2><p>離肩抬筒 → 身側穩住 → 上方對準 → 回肩</p><img id="b" alt="方案 B 換彈動畫"></section></div>
<div class="timeline"><input id="scrub" aria-label="換彈進度" type="range" min="0" max="2.42" step="0.001" value="0"><div id="status" aria-live="polite"></div></div>
<details><summary>參考遊戲與檢查方式</summary>
<p>檢視的是公開影片抽樣畫面，僅比較主要姿勢與動作階段，未量測完整動畫或角度。兩套方案是配合 RPG-21 模型重新設計。</p>
<table><thead><tr><th>參考</th><th>可確認的動作</th><th>本次借用</th></tr></thead><tbody>
<tr><td><a href="https://www.youtube.com/watch?v=H9eEc6LJqo8&t=368s">Fortnite OG · Rocket launcher（6:08 起）</a></td><td>火箭筒離肩，移到身前操作，再回肩。</td><td>A 的身前操作與回肩分段。</td></tr>
<tr><td><a href="https://www.youtube.com/watch?v=g6oDZf93eys&t=210s">GTA Online · 第三人稱換彈（3:30 起）</a></td><td>RPG 從肩上轉到身前，明顯改變筒身角度。</td><td>兩套都先改變持槍姿勢，再裝填。</td></tr>
<tr><td><a href="https://www.youtube.com/watch?v=J5zr359ZCR0">Helldivers 2 · GR-8 Recoilless Rifle</a></td><td>穩住武器，操作後膛、装填、復位。</td><td>中段穩住與復位；其後膛結構不套用到 RPG-21。</td></tr>
</tbody></table>
<p>RPG-21 使用原模型拆出的彈頭，位置、尺寸及貼圖保持一致。發射後前端彈頭隱藏；換彈途中取消不會留下已裝填的假彈頭。容量仍為一發，鏡頭可自由轉動。</p>
<small>Godot 4.7.2 · Compatibility · 1280 × 720 · 站立 30 fps。跑動圖為離散姿勢；連續跑動另經實際物理更新測試。此預覽可直接離線開啟。</small>
</details></main>
<script>
const data=__DATA__, $=id=>document.getElementById(id);
let playing=true,ready=false,time=0,last=0,token=0,frames=[],cache=new Map();
function image(path){if(!cache.has(path)){const img=new Image();cache.set(path,new Promise((resolve,reject)=>{img.onload=()=>resolve(img);img.onerror=()=>reject(Error(path));img.src=path;}));}return cache.get(path);}
function show(){if(!ready)return;let frame=frames[0];for(const candidate of frames){if(candidate.time>time)break;frame=candidate;}
$('a').src=frame.a;$('b').src=frame.b;$('scrub').value=time;
const stage=time<.22*data.duration?'離肩、調整筒身':time<.30*data.duration?'取新彈':time<.65*data.duration?'帶彈對準':time<.82*data.duration?'裝入筒口':time<.86*data.duration?'裝填完成、左手回位':'回肩';
$('status').textContent=`${time.toFixed(2)} / ${data.duration.toFixed(2)} 秒 · ${stage}`;}
async function load(){const current=++token;ready=false;$('status').textContent='載入兩套同步畫面…';
frames=data.groups[$('mode').value][$('view').value];
try{await Promise.all(frames.flatMap(f=>[image(f.a),image(f.b)]));if(current!==token)return;ready=true;show();}
catch(error){$('status').textContent='找不到擷取圖片，請依文件重新產生預覽。';console.error(error);}}
$('play').onclick=()=>{playing=!playing;$('play').textContent=playing?'暫停':'播放';};
$('scrub').max=data.duration;$('scrub').oninput=()=>{time=+$('scrub').value;show();};
$('view').onchange=load;$('mode').onchange=load;
function tick(now){if(last&&ready&&playing){time+=Math.min((now-last)/1000,.1)*+$('speed').value;if(time>data.duration+.5)time=0;show();}last=now;requestAnimationFrame(tick);}
load();requestAnimationFrame(tick);
</script></html>'''


def main() -> None:
    groups = {}
    durations = set()
    for mode in ("stationary", "moving"):
        manifest = json.loads((DIRECTORY / mode / "manifest.json").read_text(encoding="utf-8"))
        durations.add(manifest["duration"])
        captures = [c for c in manifest["captures"] if (mode == "moving" or "frame" in c)]
        if not captures:
            raise ValueError("Run the stationary capture with --sequence")
        grouped = {}
        for capture in captures:
            path = mode + "/" + capture["path"]
            if not (DIRECTORY / path).is_file():
                raise FileNotFoundError(path)
            frame = grouped.setdefault(capture["view"], {}).setdefault(capture["time"], {"time": capture["time"]})
            frame["a" if capture["variant"] == 0 else "b"] = path
        groups[mode] = {}
        for view, frames in grouped.items():
            ordered = sorted(frames.values(), key=lambda frame: frame["time"])
            if any("a" not in frame or "b" not in frame for frame in ordered):
                raise ValueError(f"Missing comparison pair: {mode}/{view}")
            groups[mode][view] = ordered
    if len(durations) != 1:
        raise ValueError("Capture durations disagree")
    data = json.dumps({"duration": durations.pop(), "groups": groups}, ensure_ascii=False)
    output = DIRECTORY / "reload_preview.html"
    output.write_text(PAGE.replace("__DATA__", data), encoding="utf-8")
    print(f"ROCKET_PREVIEW_BUILD_PASS {output}")


if __name__ == "__main__":
    main()

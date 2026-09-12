"""Build an offline original/refined comparison and complete equipment ledger."""
import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'test_output/equipment_refinement/preview'
manifest = json.loads((ROOT / 'assets/equipment_refined/manifest.json').read_text(encoding='utf-8'))
captures = json.loads((OUT / 'captures.json').read_text())
rows = []
for entry in manifest['entries']:
    jobs = [job for job in manifest['textures'] if entry['key'] in job['owners']]
    pending = [job for job in jobs if job['status'] == 'pending']
    approved = [job for job in jobs if job['status'] == 'approved']
    entry['texture_progress'] = f'{len(approved)} / {len(jobs)}'
    entry['status'] = '貼圖處理中' if pending else ('已套用／畫面已檢查' if entry.get('visual_review') else '待遊戲畫面複驗')
    rows.append(f"<tr><td><button class=jump data-key='{html.escape(entry['key'])}'>{html.escape(entry['key'])}</button></td><td>{html.escape(str(entry['name']))}</td><td>{entry['texture_progress']}</td><td>{entry['status']}</td></tr>")
template = Path(__file__).with_name('preview.html').read_text(encoding='utf-8')
gallery = []
for image in sorted(OUT.glob('game_*.png')) + sorted(OUT.glob('motion_*.png')):
    gallery.append(f'<figure><figcaption>{html.escape(image.stem)}</figcaption><img loading=lazy src="{image.name}" alt="{html.escape(image.stem)}"></figure>')
template = template.replace('__GALLERY__', ''.join(gallery))
template = template.replace('__CAPTURES__', json.dumps(captures, ensure_ascii=False)).replace('__ROWS__', '\n'.join(rows))
(OUT / 'index.html').write_text(template, encoding='utf-8')
print('EQUIPMENT_HTML_PASS captures=', len(captures))

lines = ['# 裝甲與武器細修對應表', '', '28 套裝甲、47 把武器；保留原版輪廓與配色，沿用原 UV、骨骼與換彈拆件。160 張細修貼圖、12 張原特效遮罩、1 張原生 2048 貼圖。表中分母包含保留素材，所以新圖數量不必等於來源數量。WHITE DRILL 與 Spreader 已補回原 Unity 雙貼圖材質。', '', '| ID | 裝備 | 已檢視新貼圖／來源 | 進度 |', '|---|---|---|---|']
for e in manifest['entries']:
    lines.append(f"| {e['key']} | {e['name']} | {e['texture_progress']} | {e['status']} |")
(ROOT / 'docs/art/EQUIPMENT_REFINEMENT_TABLE.md').write_text('\n'.join(lines)+'\n', encoding='utf-8')

"""Build Fortune's offline visual review from actual Godot captures."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'test_output/fortune_refinement'
files = json.loads((OUT / 'captures.json').read_text())
assert all((OUT / name).is_file() for name in files)
template = Path(__file__).with_name('preview.html').read_text(encoding='utf-8-sig')
(OUT / 'index.html').write_text(template.replace('__FILES__', json.dumps(files)), encoding='utf-8')
print('FORTUNE_HTML_PASS images=', len(files))

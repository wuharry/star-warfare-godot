"""Build an offline comparison from actual Godot captures, not concept renders."""
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
out = ROOT / 'test_output/armor_rework'
manifest = json.loads((out / 'capture_manifest.json').read_text(encoding='utf-8'))
for frame in manifest['frames']:
    assert (out / (frame['name'] + '.png')).is_file(), frame
template = Path(__file__).with_name('preview.html').read_text(encoding='utf-8')
assert len(manifest['clip_durations']) == 5
(out / 'index.html').write_text(template.replace('__DURATIONS__', json.dumps(manifest['clip_durations'])), encoding='utf-8')
for source, target in [('original_turn_03','original'),('viper_turn_03','refined'),('game_stage_1','stage_1'),('game_stage_3','stage_3')]:
    shutil.copyfile(out / (source + '.png'), ROOT / 'docs/art/armor_rework' / (target + '.png'))
print('VIPER_PREVIEW_PASS frames=' + str(len(manifest['frames'])))

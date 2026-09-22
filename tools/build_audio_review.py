"""Build an offline review catalogue; source audio and game bindings stay intact."""
import hashlib
import json
import os
import re
import shutil
import struct
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/audio/non_original_review'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def wav_info(path):
    info = {}
    with path.open('rb') as f:
        header = f.read(12)
        if header[:4] != b'RIFF' or header[8:] != b'WAVE':
            return {'format_note': '非標準 RIFF WAV，需瀏覽器確認相容性'}
        while chunk := f.read(8):
            if len(chunk) != 8:
                break
            kind, size = struct.unpack('<4sI', chunk)
            if kind == b'fmt ':
                raw = f.read(size)
                fmt, channels, rate, byte_rate, align, bits = struct.unpack('<HHIIHH', raw[:16])
                info.update(channels=channels, sample_rate=rate, bits=bits, format=fmt)
            elif kind == b'data':
                info['duration'] = round(size / byte_rate, 3) if 'byte_rate' in locals() and byte_rate else None
                break
            else:
                f.seek(size, 1)
            if size % 2:
                f.seek(1, 1)
    return info


def category(name):
    name = name.lower()
    for label, pattern in [
        ('換彈／槍械操作', r'reload|chamber|empty|magazine'),
        ('彈殼', r'casing'), ('腳步', r'footstep|flip flop'),
        ('受擊／碰撞', r'hit|impact|gore|splat|crate'),
        ('武器／爆炸', r'laser|rifle|pistol|shotgun|sniper|smg|gun|weapon|explo|firework'),
        ('生物／人聲', r'creature|monster|orc|beast|voice|vox|crowd|walla'),
        ('機械／介面', r'mech|machine|turret|sonar|warning|button|radio|beep'),
        ('環境／其他', r'.'),
    ]:
        if re.search(pattern, name):
            return label


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / '.gdignore').touch()
    sources, rows = [], []
    code = [(p.relative_to(ROOT).as_posix(), p.read_text(encoding='utf-8'))
            for p in (ROOT / 'scripts').rglob('*.gd')]

    def add(path, source, original, kind):
        relative = path.relative_to(ROOT).as_posix()
        refs = [p for p, text in code if relative in text]
        if '/weapon_shots/' in relative:
            refs += [p for p, text in code if 'non_original/weapon_shots/%s.wav' in text]
        identity = hashlib.sha256((source + '/' + original).encode()).hexdigest()[:20]
        rows.append(dict(id=identity, name=Path(original).name, source=source,
                         original=original, path=relative,
                         url=Path(os.path.relpath(path, OUT)).as_posix(),
                         kind=kind, category=category(original), refs=sorted(set(refs)),
                         bytes=path.stat().st_size, sha256=digest(path), **wav_info(path)))

    archives = [ROOT / 'sfx_pack.zip',
                *sorted((ROOT / 'assets').glob('Sonniss.com-GDC2026-GameAudioBundle*.zip')),
                *sorted(ROOT.glob('Sonniss.com-GDC2024-GameAudioBundle*.zip'))]
    for archive in archives:
        if not archive.exists():
            continue
        pack = archive.stem
        destination = OUT / 'packs' / pack
        destination.mkdir(parents=True, exist_ok=True)
        count = 0
        documents = []
        with zipfile.ZipFile(archive) as z:
            for member in z.infolist():
                extension = Path(member.filename).suffix.lower()
                if member.is_dir() or extension not in {'.wav', '.txt', '.pdf', '.xlsx'}:
                    continue
                # A flat, hashed filename avoids traversal and Windows long paths.
                key = hashlib.sha256(member.filename.encode()).hexdigest()[:20]
                target = destination / (key + extension)
                if not target.exists() or target.stat().st_size != member.file_size:
                    temporary = target.with_suffix(target.suffix + '.partial')
                    with z.open(member) as src, temporary.open('wb') as dst:
                        shutil.copyfileobj(src, dst)
                    temporary.replace(target)
                if extension == '.wav':
                    add(target, pack, member.filename, '合成音效' if pack == 'sfx_pack' else '外部素材包')
                    count += 1
                else:
                    documents.append({'name': member.filename, 'url': target.relative_to(OUT).as_posix()})
        sources.append(dict(name=pack, archive=archive.relative_to(ROOT).as_posix(), count=count, documents=documents))
        print(f'{pack}: {count} audio files', flush=True)
    for directory, source in [('docs/audio/lentikula_sfx', 'Lentikula'), ('assets/audio/non_original', '遊戲現用／原版剪輯')]:
        for path in sorted((ROOT / directory).rglob('*.wav')):
            add(path, source, path.relative_to(ROOT / directory).as_posix(),
                '原版錄音剪輯' if 'weapon_shots' in path.parts else ('合成音效' if source == 'Lentikula' else '外加音效'))
    groups = {}
    for row in rows:
        groups.setdefault(row['sha256'], []).append(row['id'])
    for row in rows:
        row['duplicates'] = [key for key in groups[row['sha256']] if key != row['id']]
    data = dict(version=1, sources=sources, items=rows,
                scope='下載的 sfx_pack、目前可用的 Sonniss ZIP、Lentikula、assets/audio/non_original。排除原生 APK 音訊；原版剪輯單獨標示。',
                usage_note='引用資訊來自 GDScript 路徑掃描，包含機槍動態路徑；代表程式引用，不保證當前場景正在播放。')
    (OUT / 'catalog.json').write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    template = Path(__file__).with_name('audio_review_template.html').read_text(encoding='utf-8')
    (OUT / 'index.html').write_text(template.replace('__CATALOG__', json.dumps(data, ensure_ascii=False).replace('</', '<\\/')), encoding='utf-8')

    # 同步輸出至 docs/audio/lentikula_sfx/index.html，讓開啟任一工作區 HTML 皆可檢視全部 756 首音效
    lentikula_dir = ROOT / 'docs/audio/lentikula_sfx'
    lentikula_data = json.loads(json.dumps(data))
    for r in lentikula_data['items']:
        target_abs = ROOT / r['path']
        r['url'] = os.path.relpath(target_abs, lentikula_dir).replace('\\', '/')
    for s in lentikula_data['sources']:
        for d in s['documents']:
            doc_abs = OUT / d['url']
            d['url'] = os.path.relpath(doc_abs, lentikula_dir).replace('\\', '/')
    (lentikula_dir / 'index.html').write_text(template.replace('__CATALOG__', json.dumps(lentikula_data, ensure_ascii=False).replace('</', '<\\/')), encoding='utf-8')

    print(f'Total: {len(rows)}; duplicate files: {sum(bool(r["duplicates"]) for r in rows)}', flush=True)


if __name__ == '__main__':
    build()

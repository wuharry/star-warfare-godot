"""Build offline armor art/runtime comparison from measured current manifest."""
import argparse
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DESCRIPTIONS = {
    'hydra': 'Hydra保留黃綠大型面甲與藍綠装甲，中央單鏡頭相機、縮短藍色下巴。',
    'strike': 'Strike採最新頭盔的雙青色縱向冠線與小點，保留青面甲與鋼藍裝甲。',
    'titan': 'Titan採連續金色全罩面甲、鋼藍护框與厚甲，兩側前臂各映射三個金點。',
    'atom': 'Atom以真正原版四部件與五張UV貼圖為基底，轉譯C-08身甲及指定新版頭盔；初版保持原幾何。',
    'pegasus': 'Pegasus以真正原版四部件與五張UV貼圖為基底，轉譯C-09白灰裝甲、深色V面甲及藍色細節；初版保持原幾何。',
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--armor', choices=['hydra', 'strike', 'titan', 'atom', 'pegasus'], required=True)
    slug = parser.parse_args().armor
    work = ROOT / f'docs/art/{slug}_runtime_v1'
    config = json.loads((work / 'runtime_config.json').read_text())
    if config.get('head_refinement'):
        revision = config['active_helmet_revision']
        raise SystemExit(f'The first-integration review template assumes unchanged UVs. Open revisions/{revision}/index.html for the active helmet review.')
    manifest = json.loads((work / 'manifest.json').read_text())
    source = json.loads((work / 'build/source.json').read_text())
    inputs = json.loads((work / 'generation_inputs.json').read_text())
    head = next(r for r in inputs if r['selected'] and r['label'] == 'head')
    part = manifest['geometry']['parts'][f"ArmorHead_{config['runtime_id']:02}"]
    topology = manifest['topology']
    # All captures, geometry and five maps influence this digest. A hand-only
    # or shape-only revision must invalidate offline preview image caches.
    revision = manifest['capture_summary']['sha256'][:12]
    relative = lambda path: os.path.relpath(ROOT / path, work).replace('\\', '/')
    maps = {config['parts'][name][sid]: relative(row['texture'].removeprefix('res://'))
            for name, record in source['parts'].items() for sid, row in enumerate(record['surfaces'])}
    metrics = (f"{topology['triangles']} triangles · 28原骨架 · 四部件／五surfaces／五貼圖 · "
               f"{manifest['uv_summary']['original_coordinate_count']}原UV，0改動 · "
               f"頭部最大局部位移 {part['max_displacement_fraction_of_smallest_dimension']*100:.2f}% · "
               f"各軸尺寸差最大 {max(part['dimension_delta_fraction'])*100:.2f}% · 真正原版總上限20%")
    tokens = {'__NAME__': config['name'], '__DESIGN_ID__': config['design_id'], '__SLUG__': slug,
              '__DESCRIPTION__': DESCRIPTIONS[slug], '__METRICS_TEXT__': metrics,
              '__BODY_REF__': relative(manifest['design_authority']['path']),
              '__HEAD_REF__': relative(manifest['helmet_design_authority']['path']),
              '__REVISION__': revision, '__HEAD_PROMPT__': relative(head['prompt']),
              '__RESIDUALS__': '尚待美術評價：' + '；'.join(manifest['residuals']),
              '__SOURCE_MAPS__': json.dumps(maps)}
    template = Path(__file__).with_name('review_template.html').read_text()
    for token, value in tokens.items():
        template = template.replace(token, value)
    assert '__' not in template, 'Unexpanded template token'
    (work / 'index.html').write_text(template, encoding='utf-8')
    readme = f"""# {config['name']} · {config['design_id']} runtime v1

{DESCRIPTIONS[slug]} 本輪已套到遊戲模型，仍待使用者美術評價。對應原版ID {config['runtime_id']}，原節點 {config['original_node_ids']}；不改裝甲數值、技能、存檔ID或背包。

{metrics}。幾何來自真正原版skin-space source；身體手腳保持原數據。GLB交換格式會將權重正規化，但SCN保留原16-bit量化權重，GLB每個原三角形UV、bone名稱、正規化權重身份另行驗證。

交付：assets/armors/{slug}_v1/{slug}.scn、{slug}.glb與五張原生1254² diffuse；build/{slug}_master.blend內嵌全部原生PNG。原版13檔快照與節點buffer索引位於 revisions/original_source_v1，原來源、生成失敗稿、完整實送prompt、不可變參照SHA都保留。

驗收：15個實際待機／跑動／換彈姿勢、9個GLB回讀姿勢、30個實際匯入頭圖像素（RGB容差0.05）、5張全GLB RGB精確相同、Blender原source／rig／UV核對、實際SCN raw buffers、64張正常ANGLE／Direct3D11擷取。正式擷取使用獨立user://{slug}_v1_capture_profile.json，真實存檔前後SHA相同。完整報告與來源SHA在 manifest.json；20%不是概念圖像素相似度。原來源若有越界UV，只接受與原始座標逐值相同的繼承樣本，詳列 inherited_out_of_range_uv，不改UV或放寬幾何／像素門檻。

後續必要prompt基底：docs/art/armor_style_unification_v1/armor_runtime_integration_prompt.txt；每次實際送出的完整提示詞在 prompts/，包含此基底。新頭盔迭代仍須依latest design authority與actual UV semantics，不把後腦畫成前額、也不在mirrored UV每半邊畫一個完整中央鏡頭。

尚待美術評價：{'；'.join(manifest['residuals'])}

共用管線位於 tools/armor_runtime_v1：adopt.py --armor={slug} → Blender build.py -- --armor={slug} → Godot正常import → compile.gd -- --armor={slug} → glb_unique_joints.py --armor={slug} → 正常import → validate_scene.gd／tests/armor_runtime_v1_test.tscn／roundtrip.tscn -- --armor={slug} → Blender載入 build/{slug}_master.blend 後执行validate_delivery.py -- --armor={slug}，以及validate_glb_images.py → ANGLE capture.tscn -- --armor={slug} → measure.py／provenance.py／review.py。禁止手改engine import metadata。
"""
    (work / 'README.md').write_text(readme, encoding='utf-8')
    print(slug.upper() + '_REVIEW_PASS offline current art / actual source / UV / 15-view comparison')


if __name__ == '__main__':
    main()

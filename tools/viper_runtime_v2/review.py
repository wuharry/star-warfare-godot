"""Build the offline review page without rewriting the canonical armor gallery."""
import json
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
WORK=ROOT/'docs/art/viper_runtime_v2'


def main():
    source=json.loads((WORK/'build/source.json').read_text())
    labels={'ArmorHead_00':['head'],'ArmorBody_00':['body','shoulder'],'ArmorHand_00':['hand'],'ArmorFoot_00':['foot']}
    maps={labels[name][sid]: '../../../'+row['texture'].removeprefix('res://')
          for name,p in source['parts'].items() for sid,row in enumerate(p['surfaces'])}
    template=Path(__file__).with_name('review_template.html').read_text(encoding='utf-8')
    (WORK/'index.html').write_text(template.replace('__SOURCE_MAPS__',json.dumps(maps)),encoding='utf-8')
    revision=ROOT/'docs/art/original_armors_v1/revisions/c01_game_proportions_20261002'
    (revision/'index.html').write_text('''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Viper 比例稿與遊戲素材</title><style>body{background:#111b25;color:#edf3f7;font:17px system-ui;max-width:1100px;margin:40px auto;padding:20px}a{color:#8cd5ff}img{width:100%;height:auto}figure{margin:30px 0}</style><h1>Viper 比例探索稿</h1><p>這兩張是先前的比例概念稿。遊戲素材已另行製作，原版模型與 UV 才是遊戲比例／貼圖位置的權威。</p><p><a href="../../../viper_runtime_v2/index.html">開啟最新版頭盔＋原版／遊戲素材比較 ↗</a></p><figure><figcaption>第一稿</figcaption><img src="viper_game_sheet_v1.png" alt="Viper 第一稿"></figure><figure><figcaption>第二稿</figcaption><img src="viper_game_sheet_v2.png" alt="Viper 第二稿"></figure></html>''',encoding='utf-8')
    study={'comparison_page':'../viper_runtime_v2/index.html','link_label':'新版 Viper／原版／UV／遊戲動作比較 ↗',
           'latest_variant':'viper_runtime_v2_concept_match_v8','status':'runtime_integrated_pending_user_art_review',
           'scope':'full_concept_armor_repaint_four_modular_game_parts_five_diffuse_maps_local_chest_abdomen_uv_inherited_head_v7_uv_original_skin',
           'note':'整套以指定鋼藍／炭黑裝甲與紫色面甲為設計基準；身體僅調整32/221個胸腹UV（14.48%），肩甲與四肢UV保持原版。頭盔沿用v7：18/130個面甲UV（13.85%）；全套50/667（7.50%）。UV座標及分區數量不變，20%為修改座標占比。含原版、修改前v7、指定稿、UV與遊戲動作／關卡比較。'}
    path=ROOT/'docs/art/original_armors_v1/c01_breakwater.json'
    data=json.loads(path.read_text(encoding='utf-8'));data['helmet_studies']=study
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    gallery=ROOT/'docs/art/original_armors_v1/index.html';html=gallery.read_text(encoding='utf-8')
    pattern=r'(<script id="catalog" type="application/json">)(.*?)(</script>)'
    match=re.search(pattern,html,re.S); catalog=json.loads(match.group(2))
    for row in catalog:
        if row.get('design_id')=='C-01':row['helmet_studies']=study
    html=html[:match.start(2)]+json.dumps(catalog,ensure_ascii=False,separators=(',',':'))+html[match.end(2):]
    gallery.write_text(html,encoding='utf-8')
    print('VIPER_REVIEW_PASS existing canonical assets retained; C-01 runtime comparison linked')

if __name__=='__main__':main()

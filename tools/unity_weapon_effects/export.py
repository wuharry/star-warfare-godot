"""Export original weapon VFX data without modifying Unity sources.

Requires the workspace's existing PyYAML. Mesh decoding uses the existing
Unity YAML converter. Serialized animation and emitter curves are preserved.
"""
from __future__ import annotations
import argparse, hashlib, json, re, shutil, sys
from pathlib import Path
import yaml
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'yaml_mesh_converter'))
import convert as unity

WEAPONS = {
 'gun11': ['Effect/Projectile','Effect/update_effect/effect_explosion_001','rpg/rpg-21_FiringSound.wav','rpg/rpg-21_boom.wav'],
 'gun12': ['Effect/Projectile','Effect/update_effect/effect_explosion_001','rpg/rpg-24_FiringSound.wav','rpg/rpg-24_boom.wav'],
 'gun13': ['Effect/Projectile','Effect/update_effect/effect_explosion_001','rpg/rpg-31_FiringSound.wav','rpg/rpg-31_boom.wav'],
 'gun30': ['Effect/BlackStar/DAN','Effect/update_effect/effect_explosion_001','rpg/rpg-31_FiringSound.wav','rpg/rpg-31_boom.wav'],
 'gun14': ['Effect/GrenadeShot','Effect/update_effect/effect_explosion_001','gl/grenade_launcher_fire.wav','gl/grenade_launcher_boom.wav'],
 'gun15': ['Effect/GrenadeShot','Effect/update_effect/effect_explosion_001','gl/grenade_launcher_fire.wav','gl/grenade_launcher_boom.wav'],
 'gun16': ['Effect/GrenadeShot','Effect/update_effect/effect_explosion_001','gl/grenade_launcher_fire.wav','gl/grenade_launcher_boom.wav'],
 'gun41': ['Effect/GrenadeShot','Effect/update_effect/effect_explosion_001','gl/grenade_launcher_fire.wav','gl/grenade_launcher_boom.wav'],
 'gun45': ['SW2_Effect/HotWing_Bullet','SW2_Effect/HotWing_Trajectory','gl/grenade_launcher_fire.wav','gl/grenade_launcher_boom.wav'],
 'gun22': ['Effect/LightBow_Shot','Effect/update_effect/effect_explosion_004','specialweapon/lightbow_shot.wav',''],
 'gun29': ['Effect/Trinity/Bow_Shot','Effect/update_effect/effect_explosion_004','specialweapon/lightbow_shot.wav',''],
 'gun44': ['Effect/update_effect/effect_thearrow_attack','Effect/update_effect/effect_explosion_004','specialweapon/lightbow_shot.wav',''],
 'gun23': ['Effect/update_effect/effect_fist_attack_002','Effect/update_effect/effect_explosion_004','specialweapon/energy_glove_fire.wav',''],
 'gun36': ['Effect/update_effect/effect_arrow_t','Effect/update_effect/effect_explosion_005','diablo/nailgun_fire.wav',''],
 'gun42': ['Effect/update_effect/effect_arrow_t_purple','Effect/update_effect/effect_explosion_005','diablo/nailgun_fire.wav',''],
 'gun33': ['Effect/update_effect/effect_sword_flying_001','Effect/LaserHit','light_sword/windblade.wav',''],
 'gun37': ['Effect/PingPongShot','Effect/update_effect/effect_explosion_004','diablo/black_disk_fire01.wav','rpg/rpg-31_boom.wav'],
}
EXTRA = ['Effect/TrackingGrenadeShot','Effect/TrackingRobot','Effect/SatanMachine/joke_force']

def documents(path):
 text=path.read_text(encoding='utf-8-sig')
 ids=re.findall(r'^--- !u!\d+ &(-?\d+)',text,re.M)
 clean=re.sub(r'^%.*\n','',text,flags=re.M)
 clean=re.sub(r'--- !u!\d+ &-?\d+','---',clean)
 return {i: d for i,d in zip(ids,yaml.load_all(clean,Loader=yaml.CSafeLoader))}

class Exporter:
 def __init__(self,root,out):
  self.root,self.out=root,out
  self.index=unity.GuidIndex(root)
  self.data={'weapons':WEAPONS,'prefabs':{},'meshes':{},'materials':{},'animations':{},'sources':{}}
  out.mkdir(parents=True,exist_ok=True)
 def source(self,p):
  name=p.relative_to(self.root).as_posix()
  self.data['sources'][name]=hashlib.sha256(p.read_bytes()).hexdigest()
  return name
 def texture(self,p):
  if p is None:return ''
  self.source(p);shutil.copy2(p,self.out/p.name);return p.name
 def material(self,guid):
  if guid in self.data['materials']:return
  p=self.index.resolve(guid);m=unity.parse_material(p,self.index)
  raw=next(iter(documents(p).values()))['Material']
  if m.shader_name == 'builtin':
   shader_id = raw['m_Shader']['fileID']
   if shader_id not in (200, 203):
    raise ValueError(f'Unsupported built-in weapon shader {shader_id}: {p}')
   m.shader_name = 'Particles/Additive' if shader_id == 200 else 'Particles/Alpha Blended'
   m.blend_mode = 'additive' if shader_id == 200 else 'alpha'
   m.cull_disabled = True
   m.unshaded = True
   m.color = unity._material_colors(p.read_text()).get('_TintColor', (1,1,1,1))
  self.data['materials'][guid]={'source':self.source(p),'texture':self.texture(m.diffuse_source),'overlay':self.texture(m.overlay_source),
   'shader':m.shader_name,'blend':m.blend_mode,'color':m.color,'unshaded':m.unshaded,'cull_disabled':m.cull_disabled,
   'overlay_color':m.overlay_color,'overlay_multiplier':m.overlay_multiplier,'base_uses_uv2':m.base_uses_uv2,'raw':raw.get('m_SavedProperties',{})}
 def mesh(self,guid):
  if guid in self.data['meshes']:return
  p=self.index.resolve(guid);m=unity.parse_mesh(p)
  raw=next(iter(documents(p).values()))['Mesh']
  self.data['meshes'][guid]={'source':self.source(p),'positions':m.positions,'normals':m.normals,'uv':m.uvs,'uv2':m.uv2s,'surfaces':[s.indices for s in m.submeshes],'skin':raw.get('m_Skin',[]),'bindposes':raw.get('m_BindPose',[])}
 def prefab(self,name):
  p=self.root/'Resources'/(name+'.prefab');docs=documents(p)
  objects={};nodes=[]
  for fid,doc in docs.items():
   kind,body=next(iter(doc.items()))
   if kind=='GameObject':objects[fid]={'object':body,'components':{}}
  for fid,doc in docs.items():
   kind,body=next(iter(doc.items()))
   go=str(body.get('m_GameObject',{}).get('fileID',0))
   if go in objects:objects[go]['components'].setdefault(kind,[]).append(body)
  for go,obj in objects.items():
   c=obj['components'];t=c['Transform'][0]
   tid=next(fid for fid,d in docs.items() if d.get('Transform') is t)
   record={'id':tid,'name':obj['object']['m_Name'],'active':obj['object']['m_IsActive'], 'parent':str(t['m_Father']['fileID']),
    'position':list(t['m_LocalPosition'].values()),'rotation':list(t['m_LocalRotation'].values()),'scale':list(t['m_LocalScale'].values()),'components':{}}
   for kind,items in c.items():
    if kind in ['MeshRenderer','SkinnedMeshRenderer','ParticleSystemRenderer','ParticleRenderer','TrailRenderer']:
     for b in items:
      for ref in b.get('m_Materials',[]):
       if ref.get('guid'):self.material(ref['guid'])
    if kind in ['MeshFilter','SkinnedMeshRenderer']:
     for b in items:
      ref=b.get('m_Mesh',{})
      if ref.get('guid'):self.mesh(ref['guid'])
    if kind=='Animation':
     for b in items:
      for ref in [b.get('m_Animation',{})]+b.get('m_Animations',[]):
       if ref.get('guid'):
        ap=self.index.resolve(ref['guid']);self.source(ap)
        self.data['animations'][ref['guid']]=next(iter(documents(ap).values()))['AnimationClip']
    if kind=='MonoBehaviour':
     for b in items:
      ref=b.get('m_Script',{})
      if ref.get('guid'):
       sp=self.index.resolve(ref['guid']);self.source(sp);b['script_name']=sp.stem
    if kind not in ['Transform','Rigidbody','BoxCollider','SphereCollider','CapsuleCollider','Pipeline']:
     record['components'][kind]=items
   record['component_ids']={kind:[fid for fid,d in docs.items() if d.get(kind) is body] for kind,items in c.items() for body in items if kind == 'ParticleSystem'}
   nodes.append(record)
  self.data['prefabs'][name]={'source':self.source(p),'nodes':nodes}
 def run(self):
  for name in sorted({p for w in WEAPONS.values() for p in w[:2]}|set(EXTRA)):self.prefab(name)
  # Verify exact original audio bytes, independent of existing lookup fallbacks.
  sounds={s for w in WEAPONS.values() for s in w[2:] if s}
  sounds.update(['diablo/black_disk_fire02.wav']+[f'diablo/black_disk_bounce0{i}.wav' for i in range(1,4)])
  for sound in sorted(sounds):
   p=self.root/'Resources'/'Audio'/sound
   if not p.exists():
    p=next(q for q in (self.root/'Resources'/'Audio').rglob('*') if q.is_file() and q.as_posix().lower().endswith('/'+sound.lower()))
   self.source(p)
   target=self.out/'audio'/sound;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
  def references(value):
   if isinstance(value,dict):return {k:str(v) if k=='fileID' else references(v) for k,v in value.items()}
   if isinstance(value,list):return [references(v) for v in value]
   return value
  (self.out/'effects.json').write_text(json.dumps(references(self.data),separators=(',',':'))+'\n',encoding='utf-8')
  print(json.dumps({k:len(v) for k,v in self.data.items()}))

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--assets-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();Exporter(a.assets_root,a.output).run()

// Use an isolated headless Edge on localhost:19444.
import {writeFile} from 'node:fs/promises';
const tab=await(await fetch('http://localhost:19444/json/new?about:blank',{method:'PUT'})).json();
const ws=new WebSocket(tab.webSocketDebuggerUrl);
await new Promise(resolve=>ws.addEventListener('open',resolve,{once:true}));
let id=0;const pending=new Map();
ws.onmessage=event=>{const m=JSON.parse(event.data);if(pending.has(m.id)){const {resolve,reject}=pending.get(m.id);pending.delete(m.id);m.error?reject(m.error):resolve(m.result)}};
const send=(method,params={})=>new Promise((resolve,reject)=>{pending.set(++id,{resolve,reject});ws.send(JSON.stringify({id,method,params}))});
const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value};

const {readFile,mkdir}=await import('node:fs/promises');
const root=new URL('../../',import.meta.url);
const out=new URL('test_output/equipment_refinement/review/',root);await mkdir(out,{recursive:true});
const manifest=JSON.parse(await readFile(new URL('assets/equipment_refined/manifest.json',root),'utf8'));
const mode=process.argv[2]||'textures';
let jobs;
if(mode==='textures'){
 const {existsSync}=await import('node:fs');
 jobs=manifest.textures.filter(j=>j.status==='pending'&&existsSync(new URL(j.output.slice(6),root))).map(j=>({key:j.source.split('/').pop(),source:j.source.slice(6),output:j.output.slice(6)}));
}else{
 jobs=manifest.entries.map(e=>({key:e.key+' '+e.name,source:'test_output/equipment_refinement/preview/'+e.key+'_original_front.png',output:'test_output/equipment_refinement/preview/'+e.key+'_refined_front.png'}));
}
if(mode==='armors')jobs=jobs.filter(j=>j.key.startsWith('armor_'));
if(mode==='weapons')jobs=jobs.filter(j=>j.key.startsWith('gun'));
if(mode==='gallery'){const {readdir}=await import('node:fs/promises');const names=(await readdir(new URL('test_output/equipment_refinement/preview/',root))).filter(n=>/^(game_|motion_).*\.png$/.test(n));jobs=[];for(let i=0;i<names.length;i+=2)jobs.push({key:names[i]+' / '+(names[i+1]||names[i]),source:'test_output/equipment_refinement/preview/'+names[i],output:'test_output/equipment_refinement/preview/'+(names[i+1]||names[i])});}
if(mode==='armor_sides')jobs=manifest.entries.filter(e=>e.kind==='armor').map(e=>({key:e.key+' '+e.name,source:'test_output/equipment_refinement/preview/'+e.key+'_refined_side.png',output:'test_output/equipment_refinement/preview/'+e.key+'_refined_rear.png'}));
await writeFile(new URL(mode+'_jobs.json',out),JSON.stringify(jobs,null,2));
await send('Page.enable');await send('Emulation.setDeviceMetricsOverride',{width:1440,height:840,deviceScaleFactor:1,mobile:false});
try{
 for(let start=0;start<jobs.length;start+=4){
 const group=jobs.slice(start,start+4);
 const content=`<!doctype html><meta charset="utf-8"><style>body{margin:0;background:#152029;color:white;font:14px system-ui;display:grid;grid-template-columns:1fr 1fr}section{height:420px}p{margin:4px}div{display:flex}img{width:350px;height:380px;object-fit:contain}</style>`+group.map(j=>`<section><p>${j.key} | ${mode==='armor_sides'?'refined side / rear':mode==='gallery'?'game capture':'original / refined'}</p><div><img src="${new URL(j.source,root).href}"><img src="${new URL(j.output,root).href}"></div></section>`).join('');
 const file=new URL(mode+'_'+Math.floor(start/4)+'.html',out);await writeFile(file,content);
 await send('Page.navigate',{url:file.href});await new Promise(r=>setTimeout(r,150));
 const ok=await evaluate(`Promise.all([...document.images].map(i=>i.complete?Promise.resolve(i.naturalWidth>0):new Promise(r=>{i.onload=()=>r(true);i.onerror=()=>r(false)})))`);
 if(!ok.every(Boolean))throw Error('missing image '+start);
 const shot=await send('Page.captureScreenshot',{format:'png'});await writeFile(new URL(mode+'_'+Math.floor(start/4)+'.png',out),Buffer.from(shot.data,'base64'));
 }
 console.log('REVIEW_SHEETS',mode,jobs.length,Math.ceil(jobs.length/4));
}finally{await send('Browser.close');ws.close()}

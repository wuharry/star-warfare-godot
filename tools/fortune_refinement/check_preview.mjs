// Use an isolated headless Edge on localhost:19444.
import {writeFile} from 'node:fs/promises';
const tab=await(await fetch('http://localhost:19444/json/new?about:blank',{method:'PUT'})).json();
const ws=new WebSocket(tab.webSocketDebuggerUrl);
await new Promise(resolve=>ws.addEventListener('open',resolve,{once:true}));
let id=0;const pending=new Map();
ws.onmessage=event=>{const m=JSON.parse(event.data);if(pending.has(m.id)){const {resolve,reject}=pending.get(m.id);pending.delete(m.id);m.error?reject(m.error):resolve(m.result)}};
const send=(method,params={})=>new Promise((resolve,reject)=>{pending.set(++id,{resolve,reject});ws.send(JSON.stringify({id,method,params}))});
const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value};
const assert=(ok,message)=>{if(!ok)throw Error(message)};
const directory=new URL('../../test_output/fortune_refinement/',import.meta.url);
try{
 await send('Page.enable');await send('Emulation.setDeviceMetricsOverride',{width:1500,height:1100,deviceScaleFactor:1,mobile:false});
 await send('Page.navigate',{url:new URL('index.html',directory).href});await new Promise(r=>setTimeout(r,300));
 const results=await evaluate(`Promise.all(files.map(src=>new Promise(r=>{const i=new Image();i.onload=()=>r(i.naturalWidth>0);i.onerror=()=>r(false);i.src=src})))`);
 assert(results.length>=29&&results.every(Boolean),'Missing capture');
 for(const v of ['front','side','rear'])for(const f of ['close','full']){
  const ok=await evaluate(`view.value='${v}';framing.value='${f}';refresh();document.querySelector('#current').src.endsWith('current_${f}_${v}.png')&&document.querySelector('#viper').src.endsWith('viper_${f}_${v}.png')`);assert(ok,'Camera selector failed');
 }
 for(const value of ['original','previous']){
  if(value==='previous'&&!await evaluate("files.includes('previous_close_front.png')"))continue;
  assert(await evaluate(`baseline.value='${value}';refresh();document.querySelector('#before').src.includes('${value}_')`),'Baseline selector failed');
 }
 await evaluate("view.value='front';framing.value='close';refresh();document.querySelector('#current').click()");
 assert(await evaluate("zoom.open&&zoom.querySelector('img').src.endsWith('current_close_front.png')"),'Zoom failed');
 await evaluate('zoom.close()');
 const shot=await send('Page.captureScreenshot',{format:'png'});await writeFile(new URL('browser_preview.png',directory),Buffer.from(shot.data,'base64'));
 console.log('FORTUNE_BROWSER_PASS images='+results.length+' view=true baseline=true zoom=true');
}finally{await send('Browser.close');ws.close()}

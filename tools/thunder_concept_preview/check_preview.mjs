// Connect only to the dedicated isolated preview browser on localhost:19446.
import {writeFile, access} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const directory=new URL(process.argv.includes('--published')?'../../docs/art/thunder_concept_v3/':'../../test_output/thunder_concept_preview/',import.meta.url);
const tab=await(await fetch('http://localhost:19446/json/new?about:blank',{method:'PUT'})).json();
const socket=new WebSocket(tab.webSocketDebuggerUrl);
await new Promise(resolve=>socket.addEventListener('open',resolve,{once:true}));
let id=0;const pending=new Map(),errors=[];
socket.onmessage=event=>{
 const message=JSON.parse(event.data);
 if(message.method==='Runtime.exceptionThrown') errors.push(message.params.exceptionDetails.text);
 if(pending.has(message.id)){const {resolve,reject}=pending.get(message.id);pending.delete(message.id);message.error?reject(message.error):resolve(message.result)}
};
const send=(method,params={})=>new Promise((resolve,reject)=>{pending.set(++id,{resolve,reject});socket.send(JSON.stringify({id,method,params}))});
const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value};
const assert=(ok,message)=>{if(!ok)throw Error(message)};
const settle=()=>new Promise(resolve=>setTimeout(resolve,150));
try{
 await send('Page.enable');await send('Runtime.enable');await send('Network.enable');
 await send('Network.setCacheDisabled',{cacheDisabled:true});
 await send('Emulation.setDeviceMetricsOverride',{width:1440,height:1150,deviceScaleFactor:1,mobile:false});
 await send('Page.navigate',{url:new URL('index.html',directory).href});
 for(let tick=0;tick<40;tick++){if(await evaluate("typeof captures !== 'undefined'"))break;await settle()}
 const stages=await evaluate('Object.keys(captures)');assert(stages.length>0,'No captures');
 const loaded=await evaluate(`Promise.all(Object.entries(captures).flatMap(([stage,data])=>data.frames.map(frame=>new Promise(resolve=>{const image=new Image();image.onload=()=>resolve(image.naturalWidth===frame.width&&image.naturalHeight===frame.height);image.onerror=()=>resolve(false);image.src=stage+'/'+frame.file}))))`);
 assert(loaded.every(Boolean),'Missing or incorrect capture dimensions');
 assert(await evaluate("new Promise(resolve=>{const i=new Image();i.onload=()=>resolve(i.naturalWidth===1145&&i.naturalHeight===1374);i.onerror=()=>resolve(false);i.src='reference.png'})"),'Reference changed or missing');
 for(const stage of stages){
  await evaluate(`$('stage').value=${JSON.stringify(stage)};refresh()`);
  for(const scope of ['full','helmet'])for(const view of ['front','three_quarter','side','rear']){
   await evaluate(`$('scope').value='${scope}';$('view').value='${view}';refresh()`);
   assert(await evaluate(`$('runtime').src.endsWith('${stage}/${scope}_${view}.png')`),'View controls failed');
   assert(await evaluate(`$('reference-frame').classList.contains('helmet-ref')===${scope==='helmet'}`),'Reference crop control failed');
  }
  for(const view of ['three_quarter','side','rear']){
   await evaluate(`$('motion-view').value='${view}';refresh()`);
   assert(await evaluate(`document.querySelectorAll('#motion-gallery img').length===4&&[...document.querySelectorAll('#motion-gallery img')].slice(1).every(i=>i.src.endsWith('_${view}.png'))`),'Motion view controls failed');
  }
  assert(await evaluate("document.querySelectorAll('#game-gallery img').length===2"),'Gameplay gallery incomplete');
 }
 await evaluate("$('reset').click();$('motion-view').value='three_quarter';refresh();$('runtime').click()");
 assert(await evaluate("$('zoom').open&&$('zoom-image').src===$('runtime').src"),'Zoom failed');
 await evaluate("$('zoom-close').click()");
 assert(await evaluate("!$('zoom').open&&$('view').value==='three_quarter'&&$('scope').value==='full'"),'Close/reset failed');
 const links=await evaluate("[...document.querySelectorAll('a[href]')].map(a=>a.href)");
 for(const link of links)if(link.startsWith('file:'))await access(fileURLToPath(link));
 await evaluate("window.scrollTo(0,0)");await settle();
 assert(await evaluate('document.documentElement.scrollWidth<=innerWidth'),'Desktop overflow');
 const desktop=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
 await writeFile(new URL('browser_desktop.png',directory),Buffer.from(desktop.data,'base64'));
 await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});await settle();
 assert(await evaluate('document.documentElement.scrollWidth<=innerWidth'),'Mobile overflow');
 const mobile=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
 await writeFile(new URL('browser_mobile.png',directory),Buffer.from(mobile.data,'base64'));
 assert(!errors.length,'Browser exceptions: '+errors.join(', '));
 const report={status:'PASS',stages,images:loaded.length,reference:true,camera_controls:true,motion_controls:true,zoom:true,local_links:links.length,desktop:'1440x1150',mobile:'390x844',horizontal_overflow:false,browser_errors:errors};
 await writeFile(new URL('browser_report.json',directory),JSON.stringify(report,null,2));
 console.log('THUNDER_PREVIEW_BROWSER_PASS '+JSON.stringify(report));
}finally{await send('Browser.close');socket.close()}

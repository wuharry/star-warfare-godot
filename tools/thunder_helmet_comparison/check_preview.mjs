// Uses only the isolated comparison browser on localhost:19458.
import {writeFile, access} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const directory=new URL('../../docs/art/thunder_helmet_comparison_v5/',import.meta.url);
const tab=await(await fetch('http://localhost:19458/json/new?about:blank',{method:'PUT'})).json();
const socket=new WebSocket(tab.webSocketDebuggerUrl);
await new Promise(resolve=>socket.addEventListener('open',resolve,{once:true}));
let id=0;const pending=new Map(),errors=[];
socket.onmessage=event=>{
 const message=JSON.parse(event.data);
 if(message.method==='Runtime.exceptionThrown')errors.push(message.params.exceptionDetails.text);
 if(pending.has(message.id)){const {resolve,reject}=pending.get(message.id);pending.delete(message.id);message.error?reject(message.error):resolve(message.result)}
};
const send=(method,params={})=>new Promise((resolve,reject)=>{pending.set(++id,{resolve,reject});socket.send(JSON.stringify({id,method,params}))});
const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value};
const assert=(ok,message)=>{if(!ok)throw Error(message)};
const settle=()=>new Promise(resolve=>setTimeout(resolve,150));
try{
 await send('Page.enable');await send('Runtime.enable');await send('Network.enable');
 await send('Network.setCacheDisabled',{cacheDisabled:true});
 await send('Emulation.setDeviceMetricsOverride',{width:1500,height:1150,deviceScaleFactor:1,mobile:false});
 await send('Page.navigate',{url:new URL('index.html',directory).href});
 for(let tick=0;tick<40;tick++){if(await evaluate("typeof captures !== 'undefined'"))break;await settle()}
 const loaded=await evaluate(`Promise.all(Object.entries(captures).flatMap(([stage,data])=>data.frames.map(frame=>new Promise(resolve=>{const image=new Image();image.onload=()=>resolve(image.naturalWidth===frame.width&&image.naturalHeight===frame.height);image.onerror=()=>resolve(false);image.src=stage+'/'+frame.file}))))`);
 assert(loaded.length===60&&loaded.every(Boolean),'Missing or incorrect runtime captures');
 let controlCases=0;
 for(const scope of ['helmet','detail','full','motion','game']){
  await evaluate(`$('scope').value='${scope}';choices()`);
  const views=await evaluate("[...$('view').options].map(o=>o.value)");
  for(const view of views){
   await evaluate(`$('view').value=${JSON.stringify(view)};refresh()`);
   for(const stage of ['sw2','prototype'])assert(await evaluate(`$('${stage}-image').src.endsWith('${stage}/${view}')`),'Comparison controls failed');
   controlCases++;
  }
 }
 await evaluate("$('reset').click();$('sw2-image').click()");
 assert(await evaluate("$('zoom').open&&$('zoom-image').src===$('sw2-image').src"),'Zoom failed');
 await evaluate("$('close').click()");
 assert(await evaluate("!$('zoom').open&&$('view').value==='helmet_three_quarter.png'&&$('scope').value==='helmet'"),'Close/reset failed');
 await evaluate("document.querySelector('[data-copy=prototype]').click()");await settle();
 assert(await evaluate("$('command').textContent.endsWith('-Helmet prototype')"),'Variant launch command failed');
 const links=await evaluate("[...document.querySelectorAll('a[href]')].map(a=>a.href)");
 for(const link of links)if(link.startsWith('file:'))await access(fileURLToPath(link));
 const references=await evaluate(`Promise.all(['reference.png','annotated.png'].map(src=>new Promise(resolve=>{const i=new Image();i.onload=()=>resolve(i.naturalWidth>0);i.onerror=()=>resolve(false);i.src=src})))`);
 assert(references.every(Boolean),'Missing reference images');
 await evaluate('window.scrollTo(0,0)');await settle();
 assert(await evaluate('document.documentElement.scrollWidth<=innerWidth'),'Desktop overflow');
 const desktop=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
 await writeFile(new URL('browser_desktop.png',directory),Buffer.from(desktop.data,'base64'));
 await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});await settle();
 assert(await evaluate('document.documentElement.scrollWidth<=innerWidth'),'Mobile overflow');
 const mobile=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
 await writeFile(new URL('browser_mobile.png',directory),Buffer.from(mobile.data,'base64'));
 assert(!errors.length,'Browser exceptions: '+errors.join(', '));
 const report={status:'PASS',images:loaded.length,control_cases:controlCases,zoom:true,reset:true,launch_command:true,local_links:links.length,desktop:'1500x1150',mobile:'390x844',horizontal_overflow:false,browser_errors:errors};
 await writeFile(new URL('browser_report.json',directory),JSON.stringify(report,null,2)+'\n');
 console.log('THUNDER_HELMET_BROWSER_PASS '+JSON.stringify(report));
}finally{await send('Browser.close');socket.close()}

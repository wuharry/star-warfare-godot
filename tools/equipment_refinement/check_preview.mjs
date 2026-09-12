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
const directory=new URL('../../test_output/equipment_refinement/preview/',import.meta.url);
try{
 await send('Page.enable');await send('Page.navigate',{url:new URL('index.html',directory).href});
 await new Promise(resolve=>setTimeout(resolve,500));
 const count=await evaluate("data.length");
 assert(count===75,'Incomplete capture catalog');
 assert(await evaluate("document.querySelectorAll('tbody tr').length===75"),'Incomplete equipment table');
 const images=await evaluate(`Promise.all(data.flatMap(e=>['original','refined'].flatMap(v=>['front','side','rear'].map(a=>new Promise(resolve=>{const i=new Image();i.onload=()=>resolve(i.naturalWidth===800&&i.naturalHeight===900);i.onerror=()=>resolve(false);i.src=e.key+'_'+v+'_'+a+'.png'})))))`);
 assert(images.every(Boolean),'Missing or invalid preview image');
 for(const kind of ['armor','weapon','all']){
  assert(await evaluate(`document.getElementById('kind').value='${kind}';filter();item.length===data.filter(e=>'${kind}'==='all'||e.kind==='${kind}').length`),'Filter failed '+kind);
 }
 const first=await evaluate('item.value');
 await evaluate("document.getElementById('next').click()");
 assert(await evaluate('item.value')!==first,'Next failed');
 await evaluate("document.getElementById('prev').click()");
 assert(await evaluate('item.value')===first,'Previous failed');
 await evaluate("view.value='rear';refresh();document.getElementById('refined').click()");
 assert(await evaluate("zoom.open&&zoom.querySelector('img').src.endsWith('_refined_rear.png')"),'View/zoom failed');
 await evaluate("zoom.click();view.value='front';refresh()");
 const gallery=await evaluate(`Promise.all([...document.querySelectorAll('.gallery img')].map(element=>new Promise(resolve=>{const i=new Image();i.onload=()=>resolve(i.naturalWidth>0);i.onerror=()=>resolve(false);i.src=element.src})))`);
 assert(gallery.length===18&&gallery.every(Boolean),'Missing gameplay/motion captures');
 assert(await evaluate(`[...document.querySelectorAll('.jump')].every(button=>{button.click();return item.value===button.dataset.key})`),'Table navigation failed');
 await evaluate("item.selectedIndex=0;refresh();window.scrollTo(0,0)");
 const shot=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
 await writeFile(new URL('browser_preview.png',directory),Buffer.from(shot.data,'base64'));
 console.log(`EQUIPMENT_BROWSER_PASS entries=${count} images=${images.length} filters=true navigation=true zoom=true gallery=18 table_navigation=75`);
}finally{await send('Browser.close');ws.close()}

// Use an isolated headless Chromium instance with --remote-debugging-port=19459.
import {writeFile,access} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const directory=new URL(process.argv.includes('--sample')?'../../test_output/armor_hd_refinement/sample_preview/':'../../docs/art/armor_hd_refinement_v1/',import.meta.url);
const tab=await(await fetch('http://localhost:19459/json/new?about:blank',{method:'PUT'})).json();
const socket=new WebSocket(tab.webSocketDebuggerUrl);
await new Promise(resolve=>socket.addEventListener('open',resolve,{once:true}));
let id=0;const pending=new Map(),errors=[];
socket.onmessage=event=>{const m=JSON.parse(event.data);if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails.text);if(pending.has(m.id)){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result)}};
const send=(method,params={})=>new Promise((resolve,reject)=>{pending.set(++id,{resolve,reject});socket.send(JSON.stringify({id,method,params}))});
const evaluate=async expression=>{const result=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));return result.result.value};
const assert=(ok,message)=>{if(!ok)throw Error(message)};
const settle=()=>new Promise(resolve=>setTimeout(resolve,150));
try{
 await send('Page.enable');await send('Runtime.enable');await send('Network.enable');await send('Network.setCacheDisabled',{cacheDisabled:true});
 await send('Emulation.setDeviceMetricsOverride',{width:1500,height:1150,deviceScaleFactor:1,mobile:false});
 await send('Page.navigate',{url:new URL('index.html',directory).href});
 for(let tick=0;tick<40;tick++){if(await evaluate("typeof captures!=='undefined'"))break;await settle()}
 const loaded=await evaluate(`Promise.all(captures.flatMap(item=>item.frames.map(frame=>new Promise(resolve=>{const image=new Image();image.onload=()=>resolve(image.naturalWidth===frame.width&&image.naturalHeight===frame.height);image.onerror=()=>resolve(false);image.src='sets/'+item.key+'/'+frame.file}))))`);
 assert(loaded.length>0&&loaded.every(Boolean),'Missing or malformed screenshots');
 const keys=await evaluate('captures.map(item=>item.key)');
 if(!process.argv.includes('--sample'))assert(keys.length===28&&loaded.length===324,'Incomplete full collection');
 let cases=0;
 for(const key of keys)for(const framing of ['full','close'])for(const view of ['front','side','rear']){
  const valid=await evaluate(`$('armor').value='${key}';$('framing').value='${framing}';$('view').value='${view}';refresh();$('after').src.endsWith('sets/${key}/current_${framing}_${view}.png')&&($('before-figure').hidden||$('before').src.endsWith('sets/${key}/baseline_${framing}_${view}.png'))`);
  assert(valid,'Selector failed');cases++;
 }
 const rows=await evaluate("[...document.querySelectorAll('#mapping button')].map(button=>button.dataset.armor)");
 assert(JSON.stringify(rows)===JSON.stringify(keys),'Incomplete mapping table');
 await evaluate("document.querySelector('#mapping button').click();$('reset').click();$('after').click()");
 assert(await evaluate("$('zoom').open&&$('zoom-image').src===$('after').src"),'Zoom failed');
 await evaluate("$('close').click();$('references').open=true");
 assert(await evaluate("!$('zoom').open&&$('framing').value==='close'&&$('view').value==='front'"),'Close/reset failed');
 const links=await evaluate("[...document.querySelectorAll('a[href]')].map(a=>a.href)");
 for(const link of links)if(link.startsWith('file:'))await access(fileURLToPath(link));
 await evaluate('window.scrollTo(0,0)');await settle();
 assert(await evaluate('document.documentElement.scrollWidth<=innerWidth'),'Desktop overflow');
 const desktop=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});await writeFile(new URL('browser_desktop.png',directory),Buffer.from(desktop.data,'base64'));
 await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});await settle();
 assert(await evaluate('document.documentElement.scrollWidth<=innerWidth'),'Mobile overflow');
 const mobile=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});await writeFile(new URL('browser_mobile.png',directory),Buffer.from(mobile.data,'base64'));
 assert(!errors.length,'Browser exceptions: '+errors.join(', '));
 const report={status:'PASS',images:loaded.length,armor_sets:keys.length,control_cases:cases,mapping:true,zoom:true,reset:true,local_links:links.length,desktop:'1500x1150',mobile:'390x844',horizontal_overflow:false,browser_errors:errors};
 await writeFile(new URL('browser_report.json',directory),JSON.stringify(report,null,2)+'\n');console.log('ARMOR_HD_BROWSER_PASS '+JSON.stringify(report));
}finally{await send('Browser.close');socket.close()}

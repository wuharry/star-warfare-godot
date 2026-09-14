// Offline HTML smoke test using an isolated local Chrome profile and CDP.
// Run: node docs/art/thunder_mk_comparison_v1/check_preview.mjs
import {spawn} from 'node:child_process';
import {mkdtemp,readFile,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
const profile=await mkdtemp(join(tmpdir(),'thunder-preview-'));
const browser=spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',['--headless=new','--no-first-run','--no-default-browser-check','--disable-background-networking','--remote-debugging-address=127.0.0.1','--remote-debugging-port=0','--user-data-dir='+profile,'about:blank'],{stdio:['ignore','ignore','pipe']});
let stderr='';browser.stderr.on('data',x=>stderr+=x);
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
let ws;
try{
 let port;
 for(let i=0;i<100;i++){try{port=(await readFile(join(profile,'DevToolsActivePort'),'utf8')).split('\n')[0];break;}catch{}if(browser.exitCode!==null)throw Error('Chrome exited: '+stderr);await sleep(100);}
 if(!port)throw Error('No CDP port: '+stderr);
 const tab=await(await fetch('http://127.0.0.1:'+port+'/json/new?about:blank',{method:'PUT'})).json();
 ws=new WebSocket(tab.webSocketDebuggerUrl);
 await new Promise((resolve,reject)=>{ws.addEventListener('open',resolve,{once:true});ws.addEventListener('error',reject,{once:true})});
 let seq=0;const pending=new Map();const errors=[];
 ws.onmessage=event=>{const msg=JSON.parse(event.data);if(msg.method==='Runtime.exceptionThrown')errors.push(msg.params);if(pending.has(msg.id)){const job=pending.get(msg.id);pending.delete(msg.id);clearTimeout(job.timer);msg.error?job.reject(Error(JSON.stringify(msg.error))):job.resolve(msg.result)}};
 const send=(method,params={})=>new Promise((resolve,reject)=>{const id=++seq;const timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP timeout: '+method))},15000);pending.set(id,{resolve,reject,timer});ws.send(JSON.stringify({id,method,params}))});
 const evaluate=async expression=>{const result=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(result.exceptionDetails)throw Error(JSON.stringify(result.exceptionDetails));return result.result.value};
 const check=(condition,message)=>{if(!condition)throw Error(message)};
 await send('Runtime.enable');await send('Page.enable');
 await send('Emulation.setDeviceMetricsOverride',{width:1440,height:1250,deviceScaleFactor:1,mobile:false});
 await send('Page.navigate',{url:new URL('index.html',import.meta.url).href});
 for(let i=0;i<50;i++){if(await evaluate('typeof window.previewReady !== "undefined"'))break;await sleep(100);}
 const loaded=await evaluate('window.previewReady');
 check(loaded?.length===7&&loaded.every(r=>r.ok),'Image load failure '+JSON.stringify(loaded));
 check(await evaluate("document.querySelector('#image-b').getAttribute('src')===studies.b.helmet.src && document.querySelector('[data-study=b][data-version=helmet]').getAttribute('aria-pressed')==='true' && document.querySelector('#prompt-b').getAttribute('href')===studies.b.helmet.prompt"),'Default B helmet failed');
 for(const [study,versions] of [['a',['source','candidate']],['b',['source','candidate','helmet']]])for(const version of versions){
  check(await evaluate(`document.querySelector('[data-study="${study}"][data-version="${version}"]').click();document.querySelector('#image-${study}').getAttribute('src')===studies.${study}.${version}.src && document.querySelector('#full-${study}').getAttribute('href')===studies.${study}.${version}.src && document.querySelector('[data-study="${study}"][data-version="${version}"]').getAttribute('aria-pressed')==='true' && document.querySelectorAll('[data-study="${study}"][aria-pressed=true]').length===1`),'Switch failed '+study+version);
  if(study==='b')check(await evaluate(`document.querySelector('#prompt-b').hidden===!studies.b.${version}.prompt && (!studies.b.${version}.prompt || document.querySelector('#prompt-b').getAttribute('href')===studies.b.${version}.prompt)`),'B prompt failed '+version);
 }
 await evaluate("document.querySelector('#gray').click()");
 check(await evaluate("document.body.classList.contains('gray')"),'Grayscale failed');
 await evaluate("document.querySelector('#gray').click();document.querySelector('[data-zoom=a]').click()");
 check(await evaluate("document.querySelector('#zoom').open&&document.querySelector('#zoom-image').src.endsWith('a_mk2_mk1_palette.png')"),'Zoom failed');
 await send('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});
 await send('Input.dispatchKeyEvent',{type:'keyUp',key:'Escape',code:'Escape',windowsVirtualKeyCode:27});
 check(await evaluate("!document.querySelector('#zoom').open"),'Escape failed');
 for(const version of ['helmet','candidate']){
  await evaluate(`select('b','${version}');document.querySelector('[data-zoom=b]').click()`);
  check(await evaluate(`document.querySelector('#zoom').open && document.querySelector('#zoom-image').src.endsWith(studies.b.${version}.src) && document.querySelector('#zoom-image').alt===studies.b.${version}.alt`),'B zoom failed '+version);
  await evaluate("document.querySelector('#close').click()");
  check(await evaluate("!document.querySelector('#zoom').open"),'Close button failed');
 }
 await evaluate("select('a','source');select('b','source');document.querySelector('#reset').click()");
 check(await evaluate("document.querySelector('[data-study=a][data-version=candidate]').getAttribute('aria-pressed')==='true' && document.querySelector('[data-study=b][data-version=helmet]').getAttribute('aria-pressed')==='true' && document.querySelector('#image-b').getAttribute('src')===studies.b.helmet.src && !document.querySelector('#prompt-b').hidden && document.querySelector('#prompt-b').getAttribute('href')===studies.b.helmet.prompt"),'Reset failed');
 await evaluate('Promise.all([...document.querySelectorAll(".frame img")].map(i=>i.decode()))');
 const desktop=await send('Page.captureScreenshot',{format:'png'});
 await writeFile(new URL('browser_desktop.png',import.meta.url),Buffer.from(desktop.data,'base64'));
 await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
 check(await evaluate('document.documentElement.scrollWidth<=window.innerWidth'),'Mobile horizontal overflow');
 const mobile=await send('Page.captureScreenshot',{format:'png'});
 await writeFile(new URL('browser_mobile.png',import.meta.url),Buffer.from(mobile.data,'base64'));
 check(errors.length===0,'Browser JS errors '+JSON.stringify(errors));
 console.log('THUNDER_HTML_PASS images=7 switches=5 prompts=true grayscale=true zooms=3 escape=true reset=true desktop=1440x1250 mobile=390x844');
 await send('Emulation.setDeviceMetricsOverride',{width:1440,height:1250,deviceScaleFactor:1,mobile:false});
 await send('Page.navigate',{url:new URL('runtime.html',import.meta.url).href});
 for(let i=0;i<50;i++){if(await evaluate('document.querySelectorAll("img").length===7 && document.readyState==="complete"'))break;await sleep(100);}
 const runtimeImages=await evaluate('Promise.all([...document.images].map(async i=>{await i.decode();return {src:i.getAttribute("src"),ok:i.naturalWidth>0}}))');
 check(runtimeImages.length===7&&runtimeImages.every(i=>i.ok),'Runtime image load failed');
 check(runtimeImages.filter(i=>i.src.startsWith('runtime/')).length===5,'Runtime must display five actual game captures');
 const links=await evaluate('[...document.querySelectorAll("a[href]")].map(a=>a.href).filter(s=>s.startsWith("file:"))');
 for(const link of links)await readFile(new URL(link));
 const runtimeDesktop=await send('Page.captureScreenshot',{format:'png'});
 await writeFile(new URL('runtime/browser_desktop.png',import.meta.url),Buffer.from(runtimeDesktop.data,'base64'));
 await send('Emulation.setDeviceMetricsOverride',{width:390,height:844,deviceScaleFactor:1,mobile:true});
 check(await evaluate('document.documentElement.scrollWidth<=window.innerWidth'),'Runtime mobile horizontal overflow');
 check(errors.length===0,'Runtime browser JS errors '+JSON.stringify(errors));
 console.log('THUNDER_RUNTIME_HTML_PASS images=7 actual_captures=5 links=true desktop=1440x1250 mobile=390x844');
 await send('Browser.close');
}finally{if(ws)ws.close();if(browser.exitCode===null)browser.kill('SIGTERM');console.log('Isolated Chrome profile retained: '+profile);}

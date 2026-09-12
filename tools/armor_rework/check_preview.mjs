// Run against an isolated headless Edge instance on localhost:19444.
import {writeFile} from 'node:fs/promises';
const tab=await(await fetch('http://localhost:19444/json/new?about:blank',{method:'PUT'})).json();
const ws=new WebSocket(tab.webSocketDebuggerUrl);
await new Promise(resolve=>ws.addEventListener('open',resolve,{once:true}));
let id=0;const pending=new Map();
ws.onmessage=event=>{const message=JSON.parse(event.data);if(pending.has(message.id)){const{resolve,reject}=pending.get(message.id);pending.delete(message.id);message.error?reject(message.error):resolve(message.result)}};
const send=(method,params={})=>new Promise((resolve,reject)=>{pending.set(++id,{resolve,reject});ws.send(JSON.stringify({id,method,params}))});
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,returnByValue:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value};
const assert=(value,message)=>{if(!value)throw Error(message)};
try{
 await send('Page.enable');await send('Page.navigate',{url:new URL('../../test_output/armor_rework/index.html',import.meta.url).href.replace('/tools/test_output/','/test_output/')});
 await sleep(800);
 assert(await evaluate("document.getElementById('after').naturalWidth===800"),'Initial refined image missing');
 for(const mode of ['turn','gun00_0','gun00_1','gun00_2','gun11_0','gun11_1']){
  await evaluate(`document.getElementById('mode').value=${JSON.stringify(mode)};document.getElementById('mode').dispatchEvent(new Event('change'));document.getElementById('frame').value=15;document.getElementById('frame').dispatchEvent(new Event('input'))`);
  await sleep(120);
  assert(await evaluate("document.getElementById('after').naturalWidth===800"),mode+' frame missing');
 }
 await evaluate("document.getElementById('play').click()");await sleep(350);
 assert(await evaluate("Number(document.getElementById('frame').value)!==15"),'Playback did not advance');
 await evaluate("document.getElementById('play').click()");const paused=await evaluate("document.getElementById('frame').value");await sleep(200);
 assert(paused===await evaluate("document.getElementById('frame').value"),'Pause did not hold');
 await evaluate("document.getElementById('after').click()");assert(await evaluate("document.getElementById('zoom').open"),'Zoom missing');
 await evaluate("document.getElementById('close').click();document.getElementById('mode').value='turn';document.getElementById('mode').dispatchEvent(new Event('change'));document.getElementById('frame').value=3;document.getElementById('frame').dispatchEvent(new Event('input'))");
 await sleep(200);
 assert(await evaluate("[...document.querySelectorAll('.shots img')].every(i=>i.naturalWidth>0)"),'Game or motion image missing');
 const shot=await send('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});
 await writeFile(new URL('../../test_output/armor_rework/browser_preview.png',import.meta.url).pathname.replace(/^\/([A-Z]:)/,'$1').replace('/tools/test_output/','/test_output/'),Buffer.from(shot.data,'base64'));
 console.log('VIPER_BROWSER_PASS modes=6 play_pause=true scrub=true zoom=true');
}finally{await send('Browser.close');ws.close()}

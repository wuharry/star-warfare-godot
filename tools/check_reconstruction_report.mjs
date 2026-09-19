// Run against an isolated headless Chrome on port 19470 (closes that instance).
// Checks the offline evidence viewer; Godot behavior has separate scene tests.
import {access, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

const directory = new URL('../docs/reconstruction_v1/', import.meta.url);
const tab = await (await fetch('http://localhost:19470/json/new?about:blank', {method: 'PUT'})).json();
const socket = new WebSocket(tab.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener('open', resolve, {once: true});
  socket.addEventListener('error', reject, {once: true});
});
let sequence = 0;
const requests = new Map(), errors = [];
socket.onmessage = event => {
  const message = JSON.parse(event.data);
  if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails.text);
  const request = requests.get(message.id);
  if (!request) return;
  requests.delete(message.id);
  message.error ? request.reject(message.error) : request.resolve(message.result);
};
const send = (method, params = {}) => new Promise((resolve, reject) => {
  requests.set(++sequence, {resolve, reject});
  socket.send(JSON.stringify({id: sequence, method, params}));
});
const evaluate = async expression => {
  const result = await send('Runtime.evaluate', {expression, returnByValue: true, awaitPromise: true});
  if (result.exceptionDetails) throw Error(JSON.stringify(result.exceptionDetails));
  return result.result.value;
};
const assert = (condition, message) => {if (!condition) throw Error(message);};
const settle = () => new Promise(resolve => setTimeout(resolve, 100));
const waitFor = async expression => {
  for (let i = 0; i < 100; i++) {
    if (await evaluate(expression)) return;
    await settle();
  }
  throw Error('Timed out: ' + expression);
};
const change = async (id, value, event = 'change') => evaluate(`$('${id}').value=${JSON.stringify(value)};$('${id}').dispatchEvent(new Event('${event}'))`);
const screenshot = async name => {
  const result = await send('Page.captureScreenshot', {format: 'png', captureBeyondViewport: false});
  await writeFile(new URL(name, directory), Buffer.from(result.data, 'base64'));
};
try {
  await send('Page.enable');
  await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', {width: 1500, height: 1100, deviceScaleFactor: 1, mobile: false});
  await send('Page.navigate', {url: new URL('index.html', directory).href});
  await waitFor("document.readyState === 'complete' && document.querySelectorAll('#game-cards .card').length === 3");
  const counts = {};
  await evaluate("document.querySelector('[data-tab=data]').click()");
  for (const game of ['sw1', 'sw2', 'com']) {
    await change('data-game', game);
    const indices = await evaluate("[...$('data-set').options].map(o=>o.value)");
    counts[game] = indices.length;
    for (const index of indices) {
      await change('data-set', index);
      assert(await evaluate("$('data-table').tBodies[0].rows.length === Math.min(100, active.rows.length)"), 'Data table failed: ' + index);
    }
  }
  assert(counts.sw1 === 76 && counts.sw2 === 227 && counts.com === 40, 'Source tables incomplete');
  await change('data-game', 'com');
  await change('data-search', 'Assault', 'input');
  assert(await evaluate("$('data-table').tBodies[0].rows.length === 1 && $('data-table').textContent.includes('8000')"), 'Applied armor search/price missing');
  await change('data-search', 'NO_SUCH_RECONSTRUCTION_ENTRY', 'input');
  assert(await evaluate("$('data-table').tBodies[0].rows.length === 0 && $('next').disabled"), 'Empty data search failed');
  await change('data-game', 'sw2');
  await change('data-set', await evaluate("report.datasets.findIndex(d=>d.game==='sw2'&&d.name==='MissionList_MissionAll')"));
  await evaluate("$('next').click()");
  assert(await evaluate("$('data-table').tBodies[0].rows[0].cells[0].textContent === '100' && !$('prev').disabled"), 'Data pagination failed');
  await evaluate("$('prev').click()");

  const mediaFilters = {};
  for (const kind of ['audio', 'ui']) {
    await evaluate(`document.querySelector('[data-tab=${kind}]').click()`);
    mediaFilters[kind] = {};
    for (const game of ['sw1', 'sw2', 'com', 'all']) {
      await change(kind + '-game', game);
      mediaFilters[kind][game] = await evaluate(`$('${kind}-list').children.length`);
      assert(await evaluate(`$('${kind}-list').children.length === report.media.filter(r=>r.type==='${kind}'&&('${game}'==='all'||r.game==='${game}')).length`), 'Media game filter failed');
    }
    await change(kind + '-search', 'NO_SUCH_RECONSTRUCTION_ENTRY', 'input');
    assert(await evaluate(`$('${kind}-list').children.length===0`), 'Empty media search failed');
    await change(kind + '-search', '', 'input');
  }
  const images = await evaluate(`Promise.all(report.media.filter(r=>r.type==='ui').map(r=>new Promise(resolve=>{
    const image=new Image();image.onload=()=>resolve({name:r.name,width:image.naturalWidth,height:image.naturalHeight});image.onerror=()=>resolve({name:r.name,width:0});image.src=local(r.target);
  })))`);
  assert(images.length === 29 && images.every(i=>i.width>0&&i.height>0), 'UI images missing');
  const audioSamples = [];
  await evaluate("document.querySelector('[data-tab=audio]').click()");
  for (const [game, name] of [['com', 'UI_buy'], ['com', 'sfx_amour_heal_01'], ['sw1', null], ['sw2', null]]) {
    await change('audio-game', game);
    await change('audio-search', name ?? '', 'input');
    await evaluate("$('audio-list').firstElementChild.click();$('audio-player').preload='metadata';$('audio-player').load()");
    await waitFor("$('audio-player').readyState >= 1 || $('audio-player').error !== null");
    assert(await evaluate("$('audio-player').error===null && $('audio-player').duration>0"), 'Browser cannot decode selected original audio');
    audioSamples.push(await evaluate("({name:$('audio-title').textContent,duration:$('audio-player').duration})"));
  }
  const links = await evaluate("[...document.querySelectorAll('a[href]')].map(a=>a.href)");
  for (const link of links) if (link.startsWith('file:')) await access(fileURLToPath(link));
  for (const viewport of [{width:1500,height:1100,mobile:false}, {width:390,height:844,mobile:true}]) {
    await send('Emulation.setDeviceMetricsOverride', {...viewport,deviceScaleFactor:1});
    for (const kind of ['overview','data','audio','ui']) {
      await evaluate(`document.querySelector('[data-tab=${kind}]').click();window.scrollTo(0,0)`);
      await settle();
      assert(await evaluate('document.documentElement.scrollWidth <= innerWidth'), 'Horizontal overflow: ' + viewport.width + '/' + kind);
      if (kind==='overview') await screenshot(viewport.mobile?'browser_mobile.png':'browser_desktop.png');
    }
  }
  assert(errors.length === 0, 'Browser exceptions: ' + errors.join(', '));
  const result = {status:'PASS', source_tables:counts, mapped_armor_table_extra:1, media_filters:mediaFilters,
    ui_images_loaded:images.length,audio_samples:audioSamples,local_links:links.length,
    search:true,pagination:true,viewports:['1500x1100','390x844'],horizontal_overflow:false,browser_errors:errors};
  await writeFile(new URL('browser_report.json', directory), JSON.stringify(result,null,2)+'\n');
  console.log('SOURCE_REPORT_BROWSER_PASS ' + JSON.stringify(result));
} finally {
  await send('Browser.close');
  socket.close();
}

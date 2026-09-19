// Start an isolated headless Chrome instance on port 19469 before running.
// This checks the static concept gallery, not in-game model integration.
import {access, readFile, writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

const directory = new URL('./', import.meta.url);
const catalog = JSON.parse(await readFile(new URL('catalog.json', directory), 'utf8'));
const entries = await Promise.all(catalog.map(item => readFile(new URL(`entries/armor_${String(item.id).padStart(2, '0')}.json`, directory), 'utf8').then(JSON.parse)));
const tab = await (await fetch('http://localhost:19469/json/new?about:blank', {method: 'PUT'})).json();
const socket = new WebSocket(tab.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.addEventListener('open', resolve, {once: true});
  socket.addEventListener('error', reject, {once: true});
});
let messageId = 0;
const pending = new Map();
const errors = [];
socket.onmessage = event => {
  const message = JSON.parse(event.data);
  if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails.text);
  if (!pending.has(message.id)) return;
  const request = pending.get(message.id);
  pending.delete(message.id);
  message.error ? request.reject(message.error) : request.resolve(message.result);
};
const send = (method, params = {}) => new Promise((resolve, reject) => {
  pending.set(++messageId, {resolve, reject});
  socket.send(JSON.stringify({id: messageId, method, params}));
});
const evaluate = async expression => {
  const result = await send('Runtime.evaluate', {expression, returnByValue: true, awaitPromise: true});
  if (result.exceptionDetails) throw Error(JSON.stringify(result.exceptionDetails));
  return result.result.value;
};
const assert = (condition, message) => {if (!condition) throw Error(message);};
const settle = () => new Promise(resolve => setTimeout(resolve, 150));
const waitFor = async expression => {
  for (let tick = 0; tick < 80; tick++) {
    if (await evaluate(expression)) return;
    await settle();
  }
  throw Error('Timed out: ' + expression);
};
const screenshot = async name => {
  const shot = await send('Page.captureScreenshot', {format: 'png', captureBeyondViewport: false});
  await writeFile(new URL(name, directory), Buffer.from(shot.data, 'base64'));
};

try {
  await send('Page.enable');
  await send('Runtime.enable');
  await send('Network.enable');
  await send('Network.setCacheDisabled', {cacheDisabled: true});
  await send('Emulation.setDeviceMetricsOverride', {width: 1500, height: 1150, deviceScaleFactor: 1, mobile: false});
  await send('Page.navigate', {url: new URL('index.html', directory).href});
  await waitFor("document.readyState === 'complete'");

  // Load every concept and all three original views, including lazy gallery images.
  const imagePaths = [...new Set(['references/thunder_style.png', ...catalog.flatMap(item => [item.image, ...Object.values(item.references)])])];
  const images = await evaluate(`Promise.all(${JSON.stringify(imagePaths)}.map(path => new Promise(resolve => {
    const image = new Image();
    image.onload = () => resolve({path, width: image.naturalWidth, height: image.naturalHeight});
    image.onerror = () => resolve({path, width: 0, height: 0});
    image.src = path;
  })))`);
  assert(catalog.length === 28 && images.length === 113, 'Incomplete concept/reference collection');
  assert(images.every(image => image.width > 0 && image.height > 0), 'Missing concept/reference image');
  for (const entry of entries) {
    const image = images.find(candidate => candidate.path === entry.image);
    assert(image.width === entry.dimensions[0] && image.height === entry.dimensions[1], `Image dimensions changed: ${entry.name}`);
  }

  await waitFor("Array.isArray(window.concepts) && window.concepts.length === 28");
  const visibleIds = () => evaluate("[...document.querySelectorAll('#gallery .card')].filter(card => !card.hidden).map(card => Number(card.dataset.id))");
  const expectedIds = catalog.map(item => item.id);
  assert(JSON.stringify(await visibleIds()) === JSON.stringify(expectedIds), 'Initial gallery is incomplete or out of order');
  const search = async value => evaluate(`document.querySelector('#search').value=${JSON.stringify(value)};document.querySelector('#search').dispatchEvent(new Event('input', {bubbles:true}))`);
  const group = async value => evaluate(`document.querySelector('#group').value=${JSON.stringify(value)};document.querySelector('#group').dispatchEvent(new Event('change', {bubbles:true}))`);
  await search('vIpEr');
  assert(JSON.stringify(await visibleIds()) === '[0]', 'Case-insensitive name search failed');
  await search('NO_SUCH_ARMOR_9e8b');
  assert((await visibleIds()).length === 0, 'Empty search state failed');
  await search('');
  const filterCases = [];
  for (const value of ['sw', 'com', 'all']) {
    await group(value);
    const expected = expectedIds.filter(id => value === 'all' || (value === 'sw' ? id <= 20 : id >= 21));
    const actual = await visibleIds();
    assert(JSON.stringify(actual) === JSON.stringify(expected), 'Group filter failed: ' + value);
    filterCases.push({group: value, count: actual.length});
  }
  await group('com');
  await search('Viper');
  assert((await visibleIds()).length === 0, 'Search did not combine with group filter');
  await group('all');
  await search('');

  let dialogCases = 0;
  let viewCases = 0;
  const localLinks = new Set();
  for (const item of catalog) {
    await evaluate(`document.querySelector('button[data-open="${item.id}"]').click()`);
    assert(await evaluate("document.querySelector('#viewer').open"), 'Dialog did not open: ' + item.name);
    assert(await evaluate(`document.querySelector('#viewer-name').textContent.includes(${JSON.stringify(item.name)})`), 'Wrong dialog title: ' + item.name);
    const conceptSource = await evaluate("document.querySelector('#concept-image').src");
    assert(conceptSource === new URL(item.image, directory).href, 'Wrong concept selected: ' + item.name);
    for (const view of ['original', 'helmet', 'rear', 'style']) {
      await evaluate(`document.querySelector('#reference-view').value='${view}';document.querySelector('#reference-view').dispatchEvent(new Event('change', {bubbles:true}))`);
      const expected = new URL(view === 'style' ? 'references/thunder_style.png' : item.references[view], directory).href;
      assert(await evaluate(`document.querySelector('#reference-image').src === ${JSON.stringify(expected)} && document.querySelector('#concept-image').src === ${JSON.stringify(conceptSource)}`), 'Reference view failed: ' + item.name + '/' + view);
      viewCases++;
    }
    const links = await evaluate("['#download','#prompt'].map(selector => document.querySelector(selector).href)");
    assert(links[0] === new URL(item.image, directory).href && links[1] === new URL(item.prompt, directory).href, 'Wrong selected armor links: ' + item.name);
    links.forEach(link => localLinks.add(link));
    await evaluate("document.querySelector('#close').click()");
    assert(await evaluate("!document.querySelector('#viewer').open"), 'Dialog did not close');
    dialogCases++;
  }
  await evaluate("document.querySelector('button[data-open=\"5\"]').click();document.querySelector('#next').click()");
  assert(await evaluate("document.querySelector('#viewer-name').textContent.includes('Atom')"), 'Next armor did not skip Thunder');
  await evaluate("document.querySelector('#prev').click()");
  assert(await evaluate("document.querySelector('#viewer-name').textContent.includes('Titan')"), 'Previous armor failed');
  const selectedConcept = await evaluate("document.querySelector('#concept-image').src");
  await evaluate("document.querySelector('#close').click();document.querySelector('#style-open').click()");
  assert(await evaluate(`document.querySelector('#viewer').open && document.querySelector('#reference-view').value === 'style' && document.querySelector('#reference-image').src.endsWith('/references/thunder_style.png') && document.querySelector('#concept-image').src === ${JSON.stringify(selectedConcept)}`), 'Thunder style comparison did not preserve the selected armor');
  await send('Input.dispatchKeyEvent', {type: 'keyDown', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27});
  await send('Input.dispatchKeyEvent', {type: 'keyUp', key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27});
  await settle();
  assert(await evaluate("!document.querySelector('#viewer').open"), 'Escape did not dismiss dialog');

  const pageLinks = await evaluate("[...document.querySelectorAll('a[href]')].map(link => link.href)");
  pageLinks.forEach(link => localLinks.add(link));
  for (const link of localLinks) if (link.startsWith('file:')) await access(fileURLToPath(link));
  await evaluate('window.scrollTo(0,0)');
  await settle();
  const cardGeometry = await evaluate("[...document.querySelectorAll('.art-button img')].map(image => ({width:image.getBoundingClientRect().width,height:image.getBoundingClientRect().height}))");
  assert(cardGeometry.length === 28 && cardGeometry.every(box => box.width > 0 && Math.abs(box.height / box.width - 1.25) < 0.02), 'Gallery image boxes ignore the intended 4:5 ratio, causing blank space');
  assert(await evaluate('document.documentElement.scrollWidth <= innerWidth'), 'Desktop horizontal overflow');
  await screenshot('browser_desktop.png');

  await send('Emulation.setDeviceMetricsOverride', {width: 390, height: 844, deviceScaleFactor: 1, mobile: true});
  await settle();
  assert(await evaluate('document.documentElement.scrollWidth <= innerWidth'), 'Mobile horizontal overflow');
  await screenshot('browser_mobile.png');
  await evaluate("document.querySelector('button[data-open=\"10\"]').click()");
  await settle();
  assert(await evaluate("document.querySelector('#viewer').scrollWidth <= document.querySelector('#viewer').clientWidth && document.documentElement.scrollWidth <= innerWidth"), 'Mobile dialog horizontal overflow');
  await screenshot('browser_mobile_dialog.png');
  await evaluate("document.querySelector('#close').click()");
  assert(!errors.length, 'Browser exceptions: ' + errors.join(', '));
  const report = {
    status: 'PASS', armor_sets: catalog.length, images_loaded: images.length,
    image_dimensions_match: true, gallery_boxes_4_by_5: true, search: true, filters: filterCases,
    combined_search_filter: true, dialog_cases: dialogCases, reference_view_cases: viewCases,
    next_previous: true, thunder_style_shortcut: true, escape_close: true,
    local_links: localLinks.size, desktop: '1500x1150', mobile: '390x844',
    horizontal_overflow: false, browser_errors: errors,
    scope: 'Static concept-gallery behavior; this does not test in-game integration.'
  };
  await writeFile(new URL('browser_report.json', directory), JSON.stringify(report, null, 2) + '\n');
  console.log('THUNDER_STYLE_GALLERY_BROWSER_PASS ' + JSON.stringify(report));
} finally {
  await send('Browser.close');
  socket.close();
}

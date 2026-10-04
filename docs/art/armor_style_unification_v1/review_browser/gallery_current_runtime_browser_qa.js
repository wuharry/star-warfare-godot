const fs = require('fs'), path = require('path'), url = require('url'), crypto = require('crypto');
const {chromium} = require('C:/Users/whw88/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
(async () => {
  const root = path.resolve(__dirname, '../../../..');
  const gallery = path.join(root, 'docs/art/original_armors_v1');
  const html = path.join(gallery, 'index.html');
  const hash = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
  const read = f => JSON.parse(fs.readFileSync(f, 'utf8'));
  const base = url.pathToFileURL(html).href;
  const catalog = JSON.parse(fs.readFileSync(html, 'utf8').match(/<script id="catalog" type="application\/json">([\s\S]*?)<\/script>/)[1]);
  const specs = [['C-03', 'tank', 'helmet_refinement_v6', 2], ['C-04', 'hydra', 'original_integration_v2_head', 3], ['C-05', 'strike', 'original_integration_v3_head', 4], ['C-06', 'titan', 'original_integration_v2_head', 5]];
  const loaderFile = path.join(root, 'scripts/game/armor_visuals.gd');
  const loaderBlock = fs.readFileSync(loaderFile, 'utf8').match(/const REWORKED_SCENES := \{([\s\S]*?)\}/)[1];
  const loaderScenes = Object.fromEntries(Array.from(loaderBlock.matchAll(/(\d+):\s*"([^"]+)"/g), m => [Number(m[1]), m[2]]));
  const report = {status: 'RUNNING', scope: 'C03–C06 current runtime IDs, links, sources, 20% engineering badge and latest helmet references only; no runtime art approval', gallery_sha256: hash(html), loader_sha256: hash(loaderFile), checks: [], errors: []};
  let browser;
  try {
    browser = await chromium.launch({executablePath: 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: true});
    const page = await browser.newPage({viewport: {width: 1440, height: 1100}});
    page.on('pageerror', e => report.errors.push(String(e)));
    for (const [id, name, variant, runtimeId] of specs) {
      const item = catalog.find(c => c.design_id === id), source = read(path.join(gallery, item.source_file));
      for (const key of ['runtime_delivery', 'helmet_studies', 'helmet_art']) {
        if (JSON.stringify(source[key]) !== JSON.stringify(item[key])) throw Error(id + ' embedded/source mismatch: ' + key);
      }
      const d = item.runtime_delivery, s = item.helmet_studies, opt = d.style_optimization;
      if (d.uv_limit !== .2 || d.engineering_status !== 'PASS' || d.art_review_status !== 'pending_user_review' || s.latest_variant !== variant || opt.latest_variant !== variant) throw Error(id + ' stage or status mismatch');
      if (s.style_comparison_page !== '../armor_style_unification_v1/index.html#' + name || d.comparison_page !== s.comparison_page) throw Error(id + ' comparison route');
      const manifestFile = path.resolve(gallery, d.manifest), manifest = read(manifestFile);
      const expectedScene = 'assets/armors/' + name + '_v1/' + name + '.scn';
      if (d.runtime_id !== runtimeId || item.legacy_id !== runtimeId || manifest.runtime_id !== runtimeId || manifest.design_id !== id || d.scene !== expectedScene || loaderScenes[runtimeId] !== 'res://' + expectedScene) throw Error(id + ' gallery/manifest/loader runtime ID mapping mismatch');
      const selected = manifest.generation.filter(g => g.selected);
      const prompts = opt.prompt_set.map(p => path.resolve(gallery, p));
      if (selected.length !== 5 || JSON.stringify(prompts.slice().sort()) !== JSON.stringify(selected.map(g => path.resolve(root, g.prompt.path)).sort())) throw Error(id + ' current selected prompt set');
      if (selected.find(g => g.label === 'head').variant !== variant) throw Error(id + ' current head generation');
      if (name === 'titan' && selected.find(g => g.label === 'hand').variant !== 'original_integration_v2_hand') throw Error('Titan latest hand missing');
      const linked = [d.comparison_page, d.manifest, s.style_comparison_page.split('#')[0], s.mandatory_style_prompt, opt.verification, opt.baseline, ...opt.prompt_set].map(p => path.resolve(gallery, p));
      for (const f of linked) if (!fs.existsSync(f)) throw Error(id + ' missing source link ' + f);
      if (read(path.resolve(gallery, opt.verification)).status !== 'PASS') throw Error(id + ' current strict helper status');
      await page.goto(base + '#' + id);
      await page.waitForSelector('.catalog-card[data-id="' + id + '"][aria-pressed="true"]');
      const badge = await page.locator('#image-status').textContent();
      if (badge !== '已套用遊戲 · 20% 驗收通過') throw Error(id + ' incorrect visible badge ' + badge);
      const mapping = await page.locator('#mapping').textContent();
      if (!mapping.includes(item.legacy_name) || !mapping.includes(id)) throw Error(id + ' mapping');
      const href = await page.locator('#helmet-studies-link').getAttribute('href');
      if (href !== d.comparison_page) throw Error(id + ' visible runtime link');
      const view = item.helmet_art ? 'helmet_reference' : 'concept';
      await page.locator('#view-tabs [data-view="' + view + '"]').click();
      await page.waitForFunction(() => {const i = document.querySelector('#result-image'); return i.complete && i.naturalWidth > 0;});
      const displayed = await page.locator('#result-image').evaluate(i => ({src: i.src, w: i.naturalWidth, h: i.naturalHeight}));
      const expected = item.helmet_art?.path || item.images.concept;
      const actualFile = url.fileURLToPath(displayed.src), expectedFile = path.resolve(gallery, expected);
      if (path.resolve(actualFile) !== expectedFile) throw Error(id + ' reference URI mismatch');
      if (item.helmet_art && hash(actualFile) !== item.helmet_art.sha256) throw Error(id + ' reference SHA mismatch');
      if (name === 'tank' && (expected !== '../tank_runtime_v1/approved_helmet_reference.png' || !item.helmet_art.previous_reference)) throw Error('Tank newest user reference/history missing');
      if (name === 'tank' && path.resolve(root, item.helmet_art.source_repo_path) !== expectedFile) throw Error('Tank portable source_repo_path mismatch');
      await page.locator('#result-image-button').click();
      await page.waitForFunction(() => document.querySelector('#image-dialog').open && document.querySelector('#full-image').complete && document.querySelector('#full-image').naturalWidth > 0);
      const zoom = await page.locator('#full-image').evaluate(i => i.src);
      if (path.resolve(url.fileURLToPath(zoom)) !== expectedFile) throw Error(id + ' zoom reference source mismatch');
      await page.locator('#close-dialog').click();
      report.checks.push({id, armor: name, runtime_id_mapping: {catalog: d.runtime_id, original_legacy: item.legacy_id, manifest: manifest.runtime_id, loader: runtimeId, scene: loaderScenes[runtimeId], status: 'PASS'}, current_head_variant: variant, selected_native_generations: Object.fromEntries(selected.map(g => [g.label, g.variant])), source_sha256: hash(path.join(gallery, item.source_file)), manifest_sha256: hash(manifestFile), runtime_href: href, shared_href: s.style_comparison_page, engineering_badge: badge, art_review_status: d.art_review_status, reference: {path: expected, sha256: hash(actualFile), dimensions: [displayed.w, displayed.h], zoom: 'PASS'}, current_prompt_files: opt.prompt_set, source_links: 'PASS'});
    }
    if (report.errors.length) throw Error(report.errors.join('; '));
    report.status = 'PASS';
  } catch (e) {report.status = 'FAIL'; report.failure = String(e); process.exitCode = 1;}
  finally {
    if (browser) await browser.close();
    fs.writeFileSync(path.join(__dirname, 'gallery_current_runtime_browser_validate.json'), JSON.stringify(report, null, 2) + '\n');
    console.log(JSON.stringify({status: report.status, checks: report.checks.length, errors: report.errors, failure: report.failure}));
  }
})().catch(e => {console.error(String(e)); process.exitCode = 1;});

// The browser smoke test of the docs site (design D16). `moonx scripts/site.mbtx test` serves the
// built `_site/` with `scripts/serve-site.mbtx --no-watch --port 4174`, gives the origin in
// SITE_ORIGIN and the base path of the tree in SITE_BASE, and runs this file with the pinned Node.
// The checks cover client code that no other test runs: the islands and the Rabbita link capture.
import { chromium, type Page } from 'playwright';

const origin = process.env.SITE_ORIGIN ?? 'http://127.0.0.1:4174';
const base = process.env.SITE_BASE ?? '/moon-lander/';
const site = `${origin}${base}`;
const overview = `${site}docs/design/overview/`;
const failures: string[] = [];
const check = (ok: boolean, message: string) => {
  if (!ok) failures.push(message);
};

// The server compiles its script before it listens, so wait for the first answer.
async function waitForSite(timeoutMs: number) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    try {
      if ((await fetch(site)).ok) return;
    } catch {
      // Not listening yet.
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`${site} did not answer in ${timeoutMs} ms`);
}

async function searchFor(page: Page, query: string) {
  await page.fill('#search-input', query);
  await page.waitForSelector('#site-search .search-results:not([hidden]) li', { timeout: 5000 });
}

// The path and the anchor of a URL. A search result of an API item ends with an anchor.
const pathAndHash = (url: string | URL) => {
  const u = new URL(url);
  return u.pathname + u.hash;
};

await waitForSite(180_000);
const browser = await chromium.launch();
const errors: string[] = [];
try {
  const page = await browser.newPage();
  page.on('pageerror', (e) => errors.push(`${page.url()}: ${e.message}`));

  await page.goto(site);
  check((await page.title()) === 'Moon-Lander', 'the landing page title is "Moon-Lander"');


  // Landing and branding belong to this consumer, including the temporary API-index adapter.
  check((await page.locator('h1').count()) === 1, 'the landing page has one main heading');
  check((await page.locator('#landing-title').innerText()).includes('Land anywhere.'), 'the landing headline is present');
  check((await page.locator('.ml-install code').innerText()) === 'moon add moonrockz/moon-lander', 'installation uses no stale release pin');
  const brand = page.locator('.site-header .brand');
  check((await brand.innerText()).trim() === 'Moon-Lander', 'the brand has one accessible project title');
  check((await brand.locator('img').getAttribute('alt')) === '', 'the adjacent header icon is decorative');
  for (const selector of ['.brand img', '.ml-art img']) {
    await page.locator(selector).evaluate((img: HTMLImageElement) => img.decode());
    const src = await page.locator(selector).getAttribute('src');
    check(src?.startsWith(base) === true, selector + ' uses the active tree');
  }
  const favicon = await page.locator('link[rel="icon"]').getAttribute('href');
  check(favicon === base + 'assets/brand/favicon.ico', 'the favicon follows the active tree');
  check((await page.request.get(origin + favicon)).ok(), 'the favicon is served');
  const published = await (await page.request.get(site)).text();
  check(!published.includes('moon-lander-route://'), 'no compatibility marker reaches published HTML');
  check((await page.request.get(site + 'docs/assets/brand/')).status() === 404, 'brand notes are not documentation pages');
  const apiAction = page.getByRole('link', { name: 'Explore the API', exact: true });
  check((await apiAction.getAttribute('href')) === base + 'api/', 'the API action points to the generated index');
  await apiAction.click();
  check(new URL(page.url()).pathname === base + 'api/', 'the landing API action navigates');
  await page.goto(site);
  const packageLinks = await page.locator('.ml-card').evaluateAll(links => links.map(link => link.getAttribute('href')!));
  for (const name of ['config', 'logging', 'hosting', 'mediator', 'actors']) {
    check(packageLinks.includes(base + 'docs/packages/' + name + '/'), 'landing links to ' + name);
  }
  for (const href of packageLinks) check((await page.request.get(origin + href)).ok(), 'package guide resolves: ' + href);

  // The landing and docs use the shared Smithy palettes, including readable text and controls.
  for (const [theme, palette] of [
    ['light', ['#f9fafb', '#ffffff', '#111827', '#4f46e5']],
    ['dark', ['#0f1014', '#17181f', '#e5e7eb', '#a5b4fc']],
  ] as const) {
    await page.evaluate(t => localStorage.setItem('site-theme', t), theme);
    for (const route of ['', 'docs/design/overview/']) {
      await page.goto(site + route);
      const tokens = await page.evaluate(() => ['--page-bg', '--surface', '--page-fg', '--accent']
        .map(name => getComputedStyle(document.documentElement).getPropertyValue(name).trim().toLowerCase()));
      check(JSON.stringify(tokens) === JSON.stringify(palette), theme + ' palette applies to ' + route);
      const contrasts = await page.evaluate(selectors => {
        const rgba = (color: string) => color.match(/[\d.]+/g)!.map(Number);
        const luminance = (color: string) => {
          const linear = rgba(color).slice(0, 3).map(value => {
            value /= 255;
            return value <= .04045 ? value / 12.92 : ((value + .055) / 1.055) ** 2.4;
          });
          return linear[0] * .2126 + linear[1] * .7152 + linear[2] * .0722;
        };
        const contrast = (a: string, b: string) => {
          const x = luminance(a), y = luminance(b);
          return (Math.max(x, y) + .05) / (Math.min(x, y) + .05);
        };
        const background = (element: Element): string => {
          const color = getComputedStyle(element).backgroundColor;
          const values = rgba(color);
          if (values.length === 3 || values[3] === 1) return color;
          return element.parentElement ? background(element.parentElement) : 'rgb(255,255,255)';
        };
        return selectors.flatMap(selector => [...document.querySelectorAll(selector)].map(element => ({
          selector,
          text: contrast(getComputedStyle(element).color, background(element)),
        })));
      }, route === '' ?
        ['.ml-home h1', '.ml-lead', '.ml-card p', '.ml-card-link', '.ml-eyebrow', '.ml-facts', '.ml-install p', '.ml-button'] :
        ['.brand', '.docs-article p', '.docs-sidebar a']);
      for (const sample of contrasts) check(sample.text >= 4.5, theme + ' text contrast ' + sample.selector + ': ' + sample.text.toFixed(2));
      if (route === '') {
        await page.getByRole('link', { name: 'Read the docs', exact: true }).focus();
        await page.keyboard.press('Shift+Tab');
        await page.keyboard.press('Tab');
        const focus = await page.locator(':focus-visible').evaluate(element => {
          const style = getComputedStyle(element);
          const rgb = (color: string) => color.match(/[\d.]+/g)!.slice(0, 3).map(Number);
          const lum = (color: string) => {
            const values = rgb(color).map(v => { v /= 255; return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; });
            return values[0] * .2126 + values[1] * .7152 + values[2] * .0722;
          };
          const a = lum(style.outlineColor), b = lum(getComputedStyle(document.body).backgroundColor);
          return { width: parseFloat(style.outlineWidth), style: style.outlineStyle, contrast: (Math.max(a,b)+.05)/(Math.min(a,b)+.05) };
        });
        check(focus.width >= 2 && focus.style !== 'none' && focus.contrast >= 3, theme + ' keyboard focus is visible');
        const border = await page.locator('.ml-button:not(.ml-primary)').first().evaluate(element => {
          const style = getComputedStyle(element);
          const lum = (color: string) => {
            const values = color.match(/[\d.]+/g)!.slice(0,3).map(Number).map(v => { v /= 255; return v <= .04045 ? v / 12.92 : ((v+.055)/1.055) ** 2.4; });
            return values[0]*.2126 + values[1]*.7152 + values[2]*.0722;
          };
          const a=lum(style.borderTopColor), b=lum(style.backgroundColor);
          return (Math.max(a,b)+.05)/(Math.min(a,b)+.05);
        });
        check(border >= 3, theme + ' essential button border has contrast');
      }
    }
  }
  await page.evaluate(() => localStorage.removeItem('site-theme'));
  for (const [colorScheme, background] of [['dark', '#0f1014'], ['light', '#f9fafb']] as const) {
    await page.emulateMedia({ colorScheme });
    await page.goto(site);
    const actual = await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--page-bg').trim().toLowerCase());
    check(actual === background, 'system theme follows the ' + colorScheme + ' preference');
  }
  await page.emulateMedia({ colorScheme: null });
  await page.goto(site);

  // Search: Enter and a click open the first result, and a query without a match says so.
  await searchFor(page, 'layer');
  const first = await page.locator('.search-results li a').first().getAttribute('href');
  check(first !== null && first.startsWith(base), `the first result for "layer" is below ${base}: ${first}`);
  await page.press('#search-input', 'Enter');
  await page.waitForURL((url) => pathAndHash(url) === first, { timeout: 5000 }).catch(() => {});
  check(pathAndHash(page.url()) === first, `Enter opens the first result ${first}, not ${page.url()}`);
  await page.goto(site);
  await searchFor(page, 'layer');
  await page.locator('.search-results li a').first().click();
  await page.waitForURL((url) => pathAndHash(url) === first, { timeout: 5000 }).catch(() => {});
  check(pathAndHash(page.url()) === first, `a click opens the first result ${first}, not ${page.url()}`);
  await page.goto(site);
  await searchFor(page, 'zzzqqq');
  check((await page.textContent('.search-empty')) === 'No results', 'a query without a match shows "No results"');

  // Theme: the control cycles system, light, dark, and a stored choice paints from the start.
  const toggle = page.locator('.theme-toggle');
  const themes: string[][] = [];
  for (const theme of ['system', 'light', 'dark']) {
    await page.waitForSelector(`.theme-toggle[aria-label="Theme: ${theme}"]`, { timeout: 2000 }).catch(() => {});
    themes.push([
      (await toggle.getAttribute('aria-label')) ?? '',
      await page.evaluate(() => document.documentElement.dataset.theme ?? 'system'),
    ]);
    await toggle.click();
  }
  check(
    JSON.stringify(themes) ===
      JSON.stringify([['Theme: system', 'system'], ['Theme: light', 'light'], ['Theme: dark', 'dark']]),
    `the theme control cycles system, light, dark: ${JSON.stringify(themes)}`,
  );
  await page.evaluate(() => localStorage.setItem('site-theme', 'dark'));
  await page.goto(`${site}docs/`, { waitUntil: 'commit' });
  await page.waitForSelector('link[rel="stylesheet"]', { state: 'attached' });
  check(
    (await page.evaluate(() => document.documentElement.dataset.theme)) === 'dark',
    'a stored dark theme is set before the stylesheet loads',
  );
  await page.evaluate(() => localStorage.removeItem('site-theme'));

  // The Design overview: the status banner and a diagram.
  await page.goto(overview);
  check(
    (await page.locator('.status-banner').textContent())?.trim() === 'Proposed — not implemented',
    'the Design overview shows the "Proposed — not implemented" banner',
  );
  check((await page.locator('figure.diagram svg').count()) > 0, 'the Design overview has a diagram as an SVG');

  // The feed.
  const feed = await page.request.get(`${site}articles/atom.xml`);
  check(feed.ok(), 'the Atom feed is served');
  const parsed = await page.evaluate(
    (xml) => !new DOMParser().parseFromString(xml, 'application/xml').querySelector('parsererror'),
    await feed.text(),
  );
  check(parsed, 'the Atom feed parses as XML');

  // No horizontal scroll on a phone.
  const phone = await browser.newPage({ viewport: { width: 390, height: 844 } });
  phone.on('pageerror', (e) => errors.push(`${phone.url()}: ${e.message}`));
  for (const path of ['', 'docs/design/overview/']) {
    await phone.goto(`${site}${path}`);
    check(
      await phone.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
      `${base}${path} has no horizontal scroll at 390 px`,
    );
  }
  await phone.close();

  // The copy button of a code block.
  const copyContext = await browser.newContext({ permissions: ['clipboard-read', 'clipboard-write'] });
  const copyPage = await copyContext.newPage();
  copyPage.on('pageerror', (e) => errors.push(`${copyPage.url()}: ${e.message}`));
  await copyPage.goto(overview);
  const block = copyPage.locator('.prose .code-block').first();
  const copy = block.locator('.copy-button');
  check((await copy.count()) === 1, 'a code block of the Design overview has one copy button');
  if ((await copy.count()) === 1) {
    check((await copy.getAttribute('data-tooltip')) === 'Copy', 'the copy button tooltip says "Copy"');
    const code = (await block.locator('code').innerText()).replace(/\n$/, '');
    await copy.click();
    await copyPage.waitForSelector('.copy-button[data-tooltip="Copied"]', { timeout: 2000 }).catch(() => {});
    check((await copy.getAttribute('data-tooltip')) === 'Copied', 'the tooltip says "Copied" after a click');
    check(
      (await copyPage.evaluate(() => navigator.clipboard.readText())) === code,
      'the copy button puts the text of the code block on the clipboard',
    );
  }
  await copyContext.close();

  // Without JavaScript the docs page keeps its sidebar, its content and plain links.
  const plain = await browser.newContext({ javaScriptEnabled: false });
  const plainPage = await plain.newPage();
  await plainPage.goto(site);
  check((await plainPage.locator('#landing-title').count()) === 1, 'without JavaScript the landing content shows');
  check((await plainPage.locator('.ml-art img').count()) === 1, 'without JavaScript the mascot shows');
  check((await plainPage.locator('.ml-card').count()) === 6, 'without JavaScript package guide links show');
  check((await plainPage.locator('.ml-install code').innerText()) === 'moon add moonrockz/moon-lander', 'without JavaScript installation text shows');
  await plainPage.getByRole('link', { name: 'Explore the API', exact: true }).click();
  check(new URL(plainPage.url()).pathname === base + 'api/', 'without JavaScript the API action navigates');
  await plainPage.goto(overview);
  check((await plainPage.locator('.docs-sidebar a').count()) > 0, 'without JavaScript the sidebar has links');
  check((await plainPage.locator('.docs-article h1').count()) === 1, 'without JavaScript the content shows');
  await plainPage.locator('.site-links a', { hasText: 'Articles' }).click();
  check(new URL(plainPage.url()).pathname === `${base}articles/`, 'without JavaScript a main link navigates');
  await plain.close();

  // One API page: the item anchor, a source link, and a search that opens an API item.
  const apiPage = `${site}api/moonrockz/notebooks/`;
  await page.goto(apiPage);
  check((await page.locator('[id="CellKind"]').count()) === 1, 'the notebooks API page has the #CellKind anchor');
  check(
    (await page.locator('.api-source a[href^="https://github.com/moonrockz/moon-lander/blob/"]').count()) > 0,
    'the notebooks API page has a source link on GitHub',
  );
  await page.goto(site);
  await searchFor(page, 'CellKind');
  await page.press('#search-input', 'Enter');
  const apiItem = `${base}api/moonrockz/notebooks/#CellKind`;
  await page.waitForURL((url) => pathAndHash(url) === apiItem, { timeout: 5000 }).catch(() => {});
  check(pathAndHash(page.url()) === apiItem, `a search for "CellKind" opens ${apiItem}, not ${page.url()}`);
  const apiPhone = await browser.newPage({ viewport: { width: 390, height: 844 } });
  apiPhone.on('pageerror', (e) => errors.push(`${apiPhone.url()}: ${e.message}`));
  await apiPhone.goto(apiPage);
  check(
    await apiPhone.evaluate(() => document.documentElement.scrollWidth <= innerWidth),
    `${base}api/moonrockz/notebooks/ has no horizontal scroll at 390 px`,
  );
  await apiPhone.close();

  check(errors.length === 0, `no page errors: ${errors.join('; ')}`);
} finally {
  await browser.close();
}

if (failures.length) {
  for (const f of failures) console.error(`FAIL: ${f}`);
  process.exit(1);
}
console.log('site browser smoke test passed');

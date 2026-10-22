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
  await plainPage.goto(overview);
  check((await plainPage.locator('.docs-sidebar a').count()) > 0, 'without JavaScript the sidebar has links');
  check((await plainPage.locator('.docs-article h1').count()) === 1, 'without JavaScript the content shows');
  await plainPage.locator('.site-links a', { hasText: 'Articles' }).click();
  check(new URL(plainPage.url()).pathname === `${base}articles/`, 'without JavaScript a main link navigates');
  await plain.close();

  // Task 10.10 adds the API page check here.

  check(errors.length === 0, `no page errors: ${errors.join('; ')}`);
} finally {
  await browser.close();
}

if (failures.length) {
  for (const f of failures) console.error(`FAIL: ${f}`);
  process.exit(1);
}
console.log('site browser smoke test passed');

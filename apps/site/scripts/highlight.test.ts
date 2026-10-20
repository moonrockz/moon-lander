import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { highlightDir, highlightHtml } from './highlight.ts';

test('known languages become dual-theme Shiki blocks', async () => {
  for (const lang of ['moonbit', 'mbt', 'toml', 'json', 'yaml', 'shell', 'typescript']) {
    const { html, warnings } = await highlightHtml(`<p>x</p><pre><code class="language-${lang}">let a = 1 &lt; 2\n</code></pre>`);
    assert.match(html, /^<p>x<\/p><pre class="shiki shiki-themes github-light github-dark"/, lang);
    assert.match(html, /--shiki-dark:/, lang);
    assert.match(html, /--shiki-light:/, lang);
    assert.deepEqual(warnings, [], lang);
  }
});

test('unknown languages stay plain with a warning', async () => {
  const source = '<pre><code class="language-cobol">MOVE A</code></pre>';
  const { html, warnings } = await highlightHtml(source);
  assert.equal(html, source);
  assert.deepEqual(warnings, ['unknown language `cobol`']);
});

test('text, plaintext and txt stay plain without a warning', async () => {
  for (const lang of ['text', 'plaintext', 'txt']) {
    const source = `<pre><code class="language-${lang}">a b</code></pre>`;
    const { html, warnings } = await highlightHtml(source);
    assert.equal(html, source);
    assert.deepEqual(warnings, []);
  }
});

test('highlightDir rewrites html files and names the file in each warning', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'site-'));
  mkdirSync(join(dir, 'docs'));
  writeFileSync(join(dir, 'docs', 'index.html'), '<pre><code class="language-json">{"a": 1}</code></pre>');
  writeFileSync(join(dir, 'index.html'), '<pre><code class="language-cobol">MOVE A</code></pre>');
  const warnings = await highlightDir(dir);
  assert.match(readFileSync(join(dir, 'docs', 'index.html'), 'utf8'), /class="shiki/);
  assert.deepEqual(warnings, ['index.html: unknown language `cobol`']);
});

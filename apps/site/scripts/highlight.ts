// Highlights the fenced code blocks of the built site with Shiki, for the light and the dark theme.
// It is the only TypeScript step of `scripts/site.mbtx build` (design D6).
//
// Usage: `bun apps/site/scripts/highlight.ts <site dir>`. Each warning is printed as
// `warning: <file>: unknown language `<lang>``. A warning does not fail the build.
import { createHighlighter } from 'shiki';
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';

const languages = ['moonbit', 'json', 'shellscript', 'toml', 'yaml', 'typescript', 'javascript'];
const aliases: Record<string, string> = {
  mbt: 'moonbit',
  shell: 'shellscript',
  sh: 'shellscript',
  bash: 'shellscript',
  console: 'shellscript',
  ts: 'typescript',
  js: 'javascript',
};
// Languages that mean "no highlighting": left as plain blocks, without a warning.
const plain = ['text', 'plaintext', 'txt'];
const themes = { light: 'github-light', dark: 'github-dark' };
// The block form that cmark writes for a fence with a language.
const block = /<pre><code class="language-([^"]+)">([\s\S]*?)<\/code><\/pre>/g;

let highlighter: Awaited<ReturnType<typeof createHighlighter>> | undefined;
async function shiki() {
  highlighter ??= await createHighlighter({ themes: Object.values(themes), langs: languages });
  return highlighter;
}

function unescape(text: string) {
  return text.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'").replaceAll('&amp;', '&');
}

/** Highlight every fenced code block in one HTML string. */
export async function highlightHtml(html: string) {
  const h = await shiki();
  const warnings: string[] = [];
  const out = html.replace(block, (whole: string, lang: string, code: string) => {
    if (plain.includes(lang)) return whole;
    const id = aliases[lang] ?? lang;
    if (!languages.includes(id)) {
      warnings.push(`unknown language \`${lang}\``);
      return whole;
    }
    return h.codeToHtml(unescape(code), { lang: id, themes, defaultColor: false });
  });
  return { html: out, warnings };
}

function htmlFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return htmlFiles(path);
    return name.endsWith('.html') ? [path] : [];
  });
}

/** Highlight all HTML files below `dir`. Returns the warnings, each with its file name. */
export async function highlightDir(dir: string) {
  const warnings: string[] = [];
  for (const file of htmlFiles(dir)) {
    const result = await highlightHtml(readFileSync(file, 'utf8'));
    writeFileSync(file, result.html);
    for (const w of result.warnings) warnings.push(`${relative(dir, file)}: ${w}`);
  }
  return warnings;
}

if (import.meta.main) {
  const dir = process.argv[2];
  if (!dir) {
    console.error('Usage: bun apps/site/scripts/highlight.ts <site dir>');
    process.exit(2);
  }
  for (const w of await highlightDir(dir)) console.warn(`warning: ${w}`);
}

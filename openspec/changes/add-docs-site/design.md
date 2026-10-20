# Design: Add the docs site

Labels: "Owner" marks a decision of the project owner (2026-10-20). "Call" marks a
decision of the author of this change. The owner can change a Call without a change
to the Owner decisions. "Model" means finos/morphir-moonbit at commit 32ab9d7, and
paths that start with `site/` below `apps/morphir-site/` in the model are written
as `morphir-site/...`. Requirements are in `specs/docs-site/spec.md`.

## Context

See proposal.md (Why).

- Moon-Lander has no `docs/`, no `apps/`, no site and no deploy workflow. `moon.work`
  lists `.`, `pkgs/lander`, `pkgs/notebooks` and `tests`. CI
  (`.github/workflows/ci.yml:11-12`) has `contents: read` only.
- `scripts/validate-packages.mbtx:21` already treats `pkgs` and `apps` as member
  roots. `scripts/test.mbtx:44-90` proves that the workspace test skips a package
  whose `supported_targets` excludes the target.
- `moonbitlang/async` is `0.22.5` in `tests/moon.mod:6` and in every task script
  (for example `scripts/versions.mbtx:15-17`). Version `0.22.5` has an HTTP server
  (`Server::run_forever`, `src/http/server.mbt:292`), `fs.mtime`
  (`src/fs/pkg.generated.mbti:32`) and a gzip `Encoder`
  (`src/gzip/pkg.generated.mbti:26`).
- `pkgs/notebooks` has `README.md` and three `examples.mbt.md` files with
  `mbt check` blocks (`pkgs/notebooks/examples.mbt.md:16`), which `moon test` runs.
- `moon doc` (moon `0.10.15`, the pin) without `--serve`, run in
  `pkgs/notebooks`, writes `_build/doc/<owner>/<module>/<package path>/` below the
  workspace root. Each package directory has `package_data.json`,
  `module_index.json`, `resource.json`, `README.md`, `_sidebar.md`, `members.md`
  and `*.mbt.html` source pages. `_build/` is in `.gitignore`.
- `package_data.json` has `name`, `traits`, `errors`, `types`, `typealias`,
  `values` and `misc`. Each item has `name`, `docstring` (Markdown with a leading
  newline), `signature` and `loc` (`path`, `file`, `line`, `column`). Types, errors
  and traits also have `methods` (same item shape) and `impls`; traits also have
  `object_type_info`. `loc.path` is the package path and `loc.file` is a file name
  in the package directory, for example `navigation.mbt`.
- A `signature` is plain text with embedded links, for example
  `fn[N : <a href="moonrockz/notebooks#Node">Node</a>] at(root : N, ...) -> N?`.
  Only the `<a href="...">` and `</a>` tags are markup. The other `<`, `>` and `&`
  characters are not escaped (`-> N?`, `&<a ...>MimeTyped</a>`). A link target is
  `<package path>#<item>`, and it can name a package outside the workspace, such
  as `moonbitlang/core/builtin#Eq`.
- `module_index.json` is a tree `{ name, package, childs }`. Each `package` lists
  the item names, impls and method names of one package.
- The `moon doc` JSON format is not documented.
- Bun is not pinned yet. `add-configuration-core` task 1.2 (bead `lander-4us.2.1`)
  pins it. Moonbase pins `bun = "1.4.3"` (`Moonbase/.config/mise/config.toml:6`).
- The model site has these parts, which this design ports:

| Part | Model source |
| --- | --- |
| Package split and targets | `morphir-site/README.md:23-31`; `supported_targets` in `content/moon.pkg:13`, `views/moon.pkg:13`, `site/moon.pkg:18`, `generate/moon.pkg:11`, `check/moon.pkg:10`, `islands/moon.pkg:9`; `model/moon.pkg` has none (all targets) |
| Configuration | `site/site.json:1-20`; `base_path` check `model/config.mbt:94-110`; `href` `model/config.mbt:295-302` |
| Routes | `route[1:] + "index.html"` in `site/outputs.mbt:16-18`; `doc_route` `model/routes.mbt:4-22`; article names `model/routes.mbt:35-49` |
| Layout and islands | `views/layout.mbt:14-16` (theme before paint), `:24-29` (empty mount), `:73` (`data-base`), `:96-104` (islands script) |
| Island entry | `islands/main.mbt:6-7` (`base_path` from `data-base`), `:22-40` (mounts) |
| Theme | `islands/theme.mbt:1-49`; tokens `assets/site.css:1-18`; Shiki colors `assets/site.css:59-61` |
| Search | `islands/search.mbt:24-45` (no `rabbita/http`, no `@json`), `:143-148` (`escape=true`); index `site/feed.mbt:68`; `model/search.mbt:83` |
| Mermaid | `content/mermaid.mbt:17-53` (SVG or client fallback); fallback script `views/layout.mbt:58-70`, `scripts/build.ts:41-42` |
| Sources | `git ls-files --cached --others --exclude-standard` in `generate/generate.mbt:36-53`; `docs/superpowers/` rejected in `site/sources.mbt:52-55` and `site/pages.mbt:189-195` |
| Drafts | `site/pages.mbt:59-63` |
| Links | `site/links.mbt:119` |
| Sidebar | `site/nav.mbt:153-159`; rules `docs/WRITING_FOR_THE_SITE.md:59-73` |
| Built-site check | `site/check.mbt:60-113` |
| Build steps | `scripts/build.ts:17-31` (islands, gzip budget), `:33-36` (generate), `:38-39` (highlight) |
| Highlighting | `scripts/highlight.ts:5-10` (languages, aliases, themes), `:23-36` |
| Preview server | `scripts/serve.ts:18-39`, watch `:49-56` |
| Link-capture guard | `scripts/link-escape.test.ts:1-4`, scanner `:13-37` |
| Browser test | `scripts/browser-test.ts:1-134` |
| Tasks | `.config/mise/config.toml:295-306`, `:308-315`, `:326-329` |
| Workflows | `.github/workflows/site.yml:1-36`, `site-build.yml:1-67`, `ci.yml:379-383` |
| Writing guide | `docs/WRITING_FOR_THE_SITE.md:1-155` |

## Goals / Non-Goals

**Goals:**

- Port the model site with the smallest set of changes that fit Moon-Lander rules
  (moonx orchestration, `moonbitlang/async`, four-target checks).
- Support the docs style of Owner decision 5 with build-time HTML passes, not with
  client code.
- Keep every MoonBit example on the site compiled by `moon test`.

**Non-Goals:**

- A general site generator for other repositories. `apps/site` serves this
  repository only.
- Any change to the content model of the model site beyond the items in Decisions.

## Decisions

### D1. A Rabbita docs tool in `apps/site` only

Owner: land a Rabbita static docs site like the model, for user docs and articles.
Rabbita is allowed only in the unpublished module `apps/site`. It is a docs tool,
not a framework UI package. The published library stays UI-free.

Call: `scripts/validate-packages.mbtx` fails when a module other than `apps/site`
imports `moonbit-community/rabbita`. This turns the Owner rule into a check.
Alternative: a rule in `AGENTS.md` only. Rejected: a rule without a check drifts.

### D2. Module and package split

Call: the module `moonrockz/moon-lander-site` in `apps/site/moon.mod`, version
`0.1.0`, with `preferred_target = "native"` as in the model (`moon.mod:13`). It is
a `moon.work` member, so `scripts/versions.mbtx` checks its version against the
root `moon.mod`. It is not published, as `tests/` is not.

| Package | Content | `supported_targets` |
| --- | --- | --- |
| `model` | `SiteConfig`, routes, `Problem`, search entries and search, API items and signature parts (D21) | none (all four) |
| `content` | front matter, Markdown, anchors, HTML passes (D8 to D11) | `native` |
| `views` | Rabbita components for each page kind | `native` |
| `site` | sources to outputs, links, sidebar, feed, search index, API pages, site check | `native` |
| `generate` | executable: reads the repository, writes `_site/` | `native` |
| `check` | executable: checks a built `_site/` | `native` |
| `assemble` | executable: puts the version trees together for a deploy (D22) | `native` |
| `islands` | executable: client islands | `js` |

This copies the model split (`morphir-site/README.md:23-31`). The pure `model`
package runs on all four targets, so `mise run test` on `wasm` and `wasm-gc` still
tests site code. `views` keeps
`warnings = "-alert_experimental-alert_xss_vulnerable"` (`views/moon.pkg:15`)
because `raw` uses `inner_html` for reviewed HTML.

### D3. Dependency versions

Call:

| Module | Version | Reason |
| --- | --- | --- |
| `moonbit-community/rabbita` | `0.16.5` | Moonbase uses it (`Moonbase/apps/web/moon.mod:21`). It is the newest in the registry index. The model uses `0.16.3`. One Rabbita version across moonrockz repositories is easier to support. |
| `moonbitlang/async` | `0.22.5` | The workspace pin. The model uses `0.22.4`. Rabbita `0.16.5` asks for `0.22.4`; the resolver must select `0.22.5` (risk R1). |
| `moonbit-community/cmark` | `0.4.12` | Same as the model; newest in the index. |
| `bobzhang/beautiful_mermaid` | `0.2.0` | Same as the model; newest in the index. |
| `moonbitlang/x` | `0.5.5` | Same as the task scripts. |
| `moonrockz/expect` | `0.6.1` | Same as `tests/moon.mod`. |
| npm `shiki` | `4.5.0` | Same as the model (`package.json:12-16`). |
| npm `playwright` | `1.64.1` | Same as the model. |

The model's npm `mermaid` package is not used (D9).

### D4. Content layout and configuration

Call: content lives at the repository root, as in the model: `docs/` for user docs,
`site/site.json`, `site/pages/index.html` and `site/articles/`.

```json
{
  "title": "Moon-Lander",
  "description": "An application framework for MoonBit.",
  "base_path": "/moon-lander/",
  "site_url": "https://moonrockz.github.io/moon-lander/",
  "repo_url": "https://github.com/moonrockz/moon-lander",
  "packages": ["notebooks"],
  "api": ["pkgs/lander", "pkgs/notebooks"],
  "nav": [
    { "group": "Design", "items": ["design/"] },
    { "group": "Packages", "items": ["packages/"] },
    { "group": "Contribute", "items": ["WRITING_FOR_THE_SITE.md"] }
  ]
}
```

Call: the dated posts are "Articles" at `/articles/` with the feed at
`/articles/atom.xml`. The model calls them "Blog" (`site.json` has no key;
`views/layout.mbt:90-94`, `:126`). Owner decision 1 says "articles", so the name
follows it. `pkgs/lander` gets a package page when it has a README (bead
`lander-4us.6`). The `api` key lists the module directories that get API pages
(D21). `base_path` is the site root; a versioned build adds the tree path to it
(D22).

### D5. Routes

Call: keep the model routes. Each route is a directory with `index.html`
(`site/outputs.mbt:16-18`), so GitHub Pages serves `/x/` without a rewrite rule.
`SiteConfig::href` adds the base path to every route (`model/config.mbt:295-302`).
The root `<html>` element carries `data-base` (`views/layout.mbt:73`), and the
islands read it (`islands/main.mbt:6-7`), so islands build links with the base path
and need no build-time constant.

Call: a versioned build (D22) puts every route below a tree base path, such as
`/moon-lander/next/` or `/moon-lander/v/0.1/`. The top-level route names `v`,
`next` and `latest` are reserved for trees, and a source route that uses one fails
the build.

### D6. Orchestration with moonx

Owner: moonx orchestrates. `scripts/site.mbtx` and a serve script use
`moonbitlang/async/process` and are exposed as `build:site`, `dev:site`,
`test:site` and `check:site`. Bun bundles the islands and runs Shiki only. Do not
copy `build.ts` or `serve.ts` as the orchestrator.

Call: `scripts/site.mbtx` has the subcommands `build [--main] [--tree <tree>]`,
`check`, `test` and `assemble` (D22).
`build` runs these steps in order and stops at the first failure with a non-zero
exit code:

1. `bun install --frozen-lockfile --cwd apps/site`.
2. `moon build --target js --release islands` in `apps/site`.
3. `bun build <islands.js> --minify --format esm --target browser --outdir _site/assets`.
   This replaces the model's `checkedBuild` helper (`scripts/build.ts:20-24`).
4. The gzip size check of `_site/assets/islands.js` with `moonbitlang/async/gzip`
   (D13).
5. `moon doc` in each module directory of the `api` key of `site/site.json` (D21).
6. `moon run --target native --release generate -- --root . --out _site [--main]`
   (`scripts/build.ts:33-36`). `generate` reads the `moon doc` output below
   `_build/doc/`.
7. `bun apps/site/scripts/highlight.ts _site`: the only TypeScript step, ported from
   `scripts/highlight.ts`.

`check` runs `moon run --target native check -- --dir _site --root .`; the root
gives the check the `moon doc` output for the docstring warnings of D21. `test` runs
`moon test` for the site packages, installs Chromium with the Playwright CLI, and
runs the browser test with the pinned Node (D16).

Call: `scripts/serve-site.mbtx` serves `_site/` with `moonbitlang/async/http` and
copies the rules of `scripts/serve.ts:18-39`: a path outside the base redirects to
the base, a path that leaves the directory gives 403, a directory serves its
`index.html`, and a missing file gives 404. It polls the `mtime` of files below
`docs/`, `site/`, `apps/site/`, the listed package directories and the `api` module
directories every 500 ms and
runs `moonx scripts/site.mbtx build` after a change. `moonbitlang/async` has no
file watch API, so polling is the portable choice.

The pure parts of both scripts (argument parsing, the step list, path mapping, the
redirect rule) are functions with tests, run by `mise run test:scripts`.

### D7. Theming

Call: port the model theme. CSS tokens on `:root`, dark tokens under
`@media (prefers-color-scheme: dark)` for `:root:not([data-theme="light"])` and
under `:root[data-theme="dark"]` (`assets/site.css:1-18`). An inline script sets
`data-theme` from `localStorage` before the first paint (`views/layout.mbt:14-16`).
The toggle island cycles `system`, `light`, `dark` (`islands/theme.mbt:17-23`).
Shiki writes both themes as CSS variables and the stylesheet selects one
(`scripts/highlight.ts:33`, `assets/site.css:59-61`).

Call: the palette comes from the spec explainer page (foil-gold accent, neutral
grays, the layer colors `--s0` to `--s8`). The site uses system font stacks and
no web fonts, so pages make no third-party request.

### D8. Docs building blocks

Owner: pages mix short prose in run order with tables, compiled code examples,
diagrams and small visual assets. The site must support tables, highlighted code,
Mermaid or SVG diagrams, callouts and status badges, and a layer-stack figure.

Call: each block is a build-time feature with no client code.

| Block | Author writes | Build output |
| --- | --- | --- |
| Table | GitHub Markdown table | `<table>` from cmark |
| Code | fenced block with a language | Shiki HTML, both themes |
| Diagram | ` ```mermaid ` block | inline SVG in `figure.diagram` (D9) |
| Image or SVG asset | relative image link | copied file (`site/links.mbt:112-119`) |
| Callout | `> [!NOTE]` and the other GitHub alert kinds | `aside.callout.<kind>` with a label |
| Status | `status: proposed` front matter | banner and sidebar badge |
| Layer stack | ` ```layers ` block, one `name \| detail` line for each layer | `figure.layer-stack` with an `ol` |

Callouts use the GitHub alert syntax, so a package README shows the same callout
on GitHub. A ` ```layers ` block shows as plain text on GitHub, which is
acceptable. Callouts and layer stacks are HTML passes over the cmark output, like
the Mermaid pass (`content/mermaid.mbt:17-53`). The `status` key accepts only
`proposed`; a later change can add values.

### D9. Mermaid at build time only

Call: render Mermaid with `beautiful_mermaid` at build time and fail the build when
a diagram does not render. Do not ship a client fallback.

The model falls back to `pre.mermaid` and loads `mermaid.min.js` on that page
(`content/mermaid.mbt:44-46`, `views/layout.mbt:58-70`, `scripts/build.ts:41-42`).
That needs the npm `mermaid` package and a large client script, and the output then
depends on the browser. When `beautiful_mermaid` cannot draw a diagram, the author
draws an SVG file and links it as an image.

### D10. Compiled code examples

Call: a MoonBit example that a reader can copy lives in a `.mbt.md` file inside a
package, where `moon test` compiles and runs its `mbt check` blocks. Package pages
come from `README.md` or `README.mbt.md` as in the model
(`docs/WRITING_FOR_THE_SITE.md:100-114`). A user guide with code is a
`README.mbt.md` chapter below the package that it documents.

In other pages, the `content` package checks the Markdown source: a fence whose
info string starts with `moonbit` or `mbt` must have the word `notest` after the
language. The Design overview uses `moonbit notest`, because its API does not
exist yet. Highlighting maps `mbt` to `moonbit` (`scripts/highlight.ts:6`).
Alternative: copy examples into `docs/` and test them with a generated harness, as
the model does for Scheme (`docs/WRITING_FOR_THE_SITE.md:116-150`). Rejected: moon
already tests `.mbt.md`, so a second extractor adds code without benefit.

### D11. Search

Call: keep the model search. The build writes `search-index.json`
(`site/feed.mbt:68`, `site/outputs.mbt:140`). The island loads it on the first
key press with `fetch` and `JSON.parse` through one `extern "js"` function, and
opens pages with `location.assign` (`islands/search.mbt:24-49`). The island does
not use `rabbita/http`, `rabbita/nav` or `@json`: the model notes that they triple
the bundle size (`islands/search.mbt:26-27`, `:48`). An external search service is
not used.

Call: the index also has one entry for each API item and method (D21): the name,
the package path, the first sentence of the docstring and the item anchor URL.

### D12. Island pitfalls

Call: carry the model's three island rules as requirements and tests.

- Rabbita prevents the default action of each `<a>` click and sends the URL to the
  router. Islands have no router, so each `@html.a` in `islands/` must pass
  `escape=true` (`islands/search.mbt:143-148`,
  `scripts/link-escape.test.ts:1-4`). Call: port the scanner
  (`scripts/link-escape.test.ts:13-37`) to a pure MoonBit function in `site`, with
  the model's six cases as unit tests, and a native test that scans
  `apps/site/islands/*.mbt`. The guard then runs in `mise run test` without Bun.
- An empty mount element uses `inner_html("")`, so no hydration comment goes into
  it (`views/layout.mbt:24-29`).
- Islands read the base path from `data-base` (D5).

### D13. Islands budget

Call: the model budget, a 25 KB gzip target with a warning and a 27 KB failure
(`scripts/build.ts:25-31`). The islands are the five of the model (search, theme,
menu, copy, "On this page" marker) and the version switcher (D22). The switcher is
small, so the model size is a fair start.

### D14. Links and the built-site check

Call: keep both layers. The build resolves each link and anchor and fails on a
broken one (`site/links.mbt:119`). An `api:` link (D21) to an unknown package,
item or method also fails the build. `check:site` then checks the output: internal
links, titles, the feed and forbidden paths (`site/check.mbt:60-113`). The second
layer catches errors in templates and the highlight step, which the first layer
does not see. External links are not checked, so the build does not need the
network.

### D15. Agent planning documents

Call: keep the model rule. The generator reads the file list from
`git ls-files --cached --others --exclude-standard` (`generate/generate.mbt:36-53`).
That list obeys `.git/info/exclude`, where `AGENTS.md` puts `docs/superpowers/`. A
`docs/superpowers/` file in the list fails the build
(`site/sources.mbt:52-55`), and a built file below that path fails `check:site`
(`site/check.mbt:107-111`). The tracked `.gitignore` does not change. The writing
guide tells authors to add the line to `.git/info/exclude`.

### D16. Browser smoke test

Call: keep one Playwright test, Chromium only, run by the pinned Node as in the
model (`package.json:10`). The Rabbita link-capture bug shows only in a browser, and
the theme, search and copy behaviors are client code that no other test covers.
The checks are a subset of `scripts/browser-test.ts`: theme cycle (`:43-53`),
search Enter and click (`:25-41`), copy button (`:85-101`), a diagram (`:103-104`),
the feed (`:106-109`), no horizontal scroll at 390 px (`:78-82`), no page errors
(`:124`), the status banner of the Design overview, and one API page
(`/api/moonrockz/notebooks/`) that has the `#CellKind` anchor and a source link. `site.mbtx test` starts
`serve-site.mbtx --no-watch --port 4174`, gives the origin to the test in
`SITE_ORIGIN` and the tree base path in `SITE_BASE` (D22), runs the test, and stops
the server. The test and the preview thus
serve the site the same way.

### D17. Workflows

Call: copy the model split.

- `.github/workflows/site-build.yml`: `workflow_call` with the input `pages`;
  `permissions: contents: read`; one job that uses `./.github/actions/setup`, runs
  `mise run build:site -- --main --tree next`, `mise run check:site` and
  `mise run test:site` (`site-build.yml:1-67`). Only when `pages` is true, it then
  runs `site.mbtx assemble` and `check:site` on the assembled site (D22), and
  uploads it with `actions/upload-pages-artifact`.
- `.github/workflows/site-asset.yml`: `workflow_call` for a future release
  workflow (D22).
- `.github/workflows/site.yml`: on push to `main` and `workflow_dispatch`;
  workflow `permissions: contents: read`; a `build` job that calls
  `site-build.yml` with `pages: true`; a `deploy` job with job-level
  `pages: write` and `id-token: write`, the `github-pages` environment, and
  `concurrency: pages` without cancel (`site.yml:1-36`).
- `.github/workflows/ci.yml`: a `site` job that calls `site-build.yml` with
  `pages: false`, and `ci-ok` needs it. CI keeps `contents: read`.

Call: no change detector and no path filter. The `site` job runs on each pull
request. Moon-Lander has no change detector, and a path-filtered required check
stays pending on other pull requests (`ci.yml:376-378` in the model). If the job
takes more than 10 minutes, a later change adds a detector.

### D18. Versions

Call: `apps/site/moon.mod` has version `0.1.0`, the root version. `versions.mbtx`
checks it as a workspace member. `apps/site/package.json` is private and has the
version `0.1.0`; `versions.mbtx` does not read it, because it is not a MoonBit
module.

### D19. Design overview page

Owner: scaffold now and grow docs with the code. The first content page is a
"Design overview" ported from the spec explainer page, marked "Proposed — not
implemented". User docs pages come as each hosting change is implemented. Bead
`lander-4us.6` covers the framework overview page and article.

Call: port it to Markdown at `docs/design/overview.md` with `status: proposed`, not
as raw HTML. The port uses each building block of D8, so the page is also the test
fixture for them. Its sections follow the source headings: one run start to finish
(Mermaid), minimal setup and defaults, the layer stack (`layers`), where files are
found (table), formats and merge rules, binding, host lifecycle with exit codes
(table), FileTree, and the four changes. Code is `moonbit notest`. The source page
loads Google Fonts; the port does not.

### D20. Writing guide

Call: `docs/WRITING_FOR_THE_SITE.md`, adapted from the model guide
(`docs/WRITING_FOR_THE_SITE.md:1-155`): where content goes, front matter (with
`status`), sidebar rules, links, the building blocks of D8 with one example each,
compiled examples (D10), the `docs/superpowers/` rule (D15), and preview. It is
written in ASD-STE100 and follows the docs style: short sections, tables, examples.

### D21. API reference pages

Owner (2026-10-20): API reference pages are in scope.

Call: the source is the `moon doc` JSON output. `site.mbtx build` runs `moon doc`
in each module directory of the `api` key, and `generate` reads
`package_data.json` and `module_index.json`. The build does not parse `.mbti`
files. Alternative: parse `pkg.generated.mbti`. Rejected: an `.mbti` file has no
docstrings, so the site would need a second source for them.

Call: the `api` key accepts only module directories below `pkgs/`. These are the
published modules `moonrockz/moon-lander` (`pkgs/lander`) and
`moonrockz/notebooks` (`pkgs/notebooks`). `apps/site`, `tests` and any other path
fail the configuration check.

Call: the reader of the JSON is a pure function in `model` that takes the JSON
text and returns typed API items, or a `Problem` that names the file and the key.
A fixture test in `model` has a copy of real `package_data.json` and
`module_index.json` output from the pinned moon. When moon changes the format, the
build fails with that `Problem`, and the fixture test shows the change.

Call: one page for each package at `/api/<package path>/`, where `<package path>`
is the full path, for example `/api/moonrockz/notebooks/` and
`/api/moonrockz/notebooks/dib/`. The sections are Types, Errors, Traits, Type
aliases and Values, in that order. An empty section is not shown. The methods and
impls of an item are below the item.

Call: each item has the anchor `#<name>`, and each method has the anchor
`#<Type>.<method>`, for example `#CellKind` and `#CellKind.equal`. A duplicate
anchor in one page fails the build.

Call: a docstring renders with cmark through the same passes as other pages (D8),
after the leading newline is removed. A signature renders as a code block. A
parser splits the signature into text parts and link parts. It accepts only
`<a href="<package path>#<item>">` and `</a>` as markup and treats every other
character as text, which the view escapes. The raw signature HTML never goes into
the page. A link target in the same package becomes `#<item>`. A target in another
package on the site becomes `<tree base path>api/<package path>/#<item>`, for
example `/moon-lander/api/moonrockz/moon-lander/#version`. A target
outside the site, such as `moonbitlang/core/builtin`, becomes plain text. An
`<a>` tag without an `href`, or one that is not closed, fails the build.
Signatures are not highlighted with Shiki, because the links must stay.

Call: each item and method links to its source on GitHub at the built commit:
`<repo_url>/blob/<commit>/<module directory>/<package subdirectory>/<loc.file>#L<loc.line>`.
The package subdirectory is `loc.path` without the module name. `generate` reads
the commit with `git rev-parse HEAD`.

Call: the package index at `/api/` lists each module and its packages from
`module_index.json`. Each package row has the first paragraph of the package
`README.md` from the `moon doc` output, or no summary when the README is empty.
The header has an "API" link to `/api/`.

Call: an item with an empty docstring still has an entry. `check:site` reads the
same `moon doc` output with the D21 reader and prints a warning for each public
item and method without a docstring, with its package and anchor. The warnings do
not fail the check, so the coverage is visible and the pages can come before the
docstrings. The build itself does not warn, so a main build stays free of
warnings.

Call: a prose page links to an API item with the syntax
`[`@config.bind`](api:moonrockz/moon-lander/config#bind)`. The target is
`api:<package path>` with an optional `#<item>` or `#<Type>.<method>`. The build
turns it into the site route of the API page and anchor. The link text is free.
This uses a standard Markdown link, so cmark needs no extension, and a reader of
the source can see the target.

Call: the hosting packages do not exist yet. Their API pages appear when each
package lands in `pkgs/lander`, with no change to the site. Until then the API
section shows `moonrockz/notebooks` and the root package `moonrockz/moon-lander`.

### D22. Versioned docs

Owner (2026-10-20): the site is versioned. A version is one minor line at
`/v/<minor>/`, for example `/v/0.1/` and `/v/0.2/`. A patch release, for example
`0.1.3`, replaces the docs of its line. The version comes from the root `moon.mod`,
with `scripts/versions.mbtx` as the source of truth. The site root `/moon-lander/`
and `/latest/` show the newest release, and `/next/` tracks `main`. Each release
keeps its built site as a release asset, built with the base path of its tree. The
Pages deploy downloads the assets of the kept versions, adds the `main` build at
`/next/` and the newest release at the root and `/latest/`, and deploys all
together. There is no storage branch and no rebuild from tags. API pages and the
search index are versioned with the rest. Each version tree has its own
`search-index.json`.

Call: `site.mbtx build --tree <tree>` sets the tree. `--tree next` writes to
`_site/next/` with the base path `/moon-lander/next/`. `--tree <minor>` writes to
`_site/v/<minor>/` with the base path `/moon-lander/v/<minor>/`, and fails when
`<minor>` is not the minor line of the root `moon.mod` version. A build without
`--tree` writes to `_site/` with the base path `/moon-lander/`, for local work.

Call: `.github/workflows/site-asset.yml` is a `workflow_call` workflow with
`permissions: contents: read`. It reads the minor line from the root `moon.mod`
through `scripts/versions.mbtx`, runs `build:site -- --main --tree <minor>` and
`check:site`, packs `_site/v/<minor>/` as `site-<minor>.tar.gz`, and uploads it as a
workflow artifact. A future release workflow calls it and attaches the file to the
release. This change does not create that workflow or a release (`AGENTS.md`).

Call: `site.mbtx assemble` runs only in the deploy. It lists the releases with
`gh release list` and selects, for each minor line, the newest release by semantic
version. It downloads `site-<minor>.tar.gz` from each with `gh release download`
and the `GITHUB_TOKEN` with `contents: read`. A selected release without the asset,
or an archive that does not unpack, fails the deploy with the release tag. Each
kept minor line is in the site; a later change can limit the count (risk R13).

Call: the `assemble` executable takes the unpacked trees and the `next` tree and
writes the final site. It copies the newest release tree to `/latest/` and to the
root, and changes the tree base path to the new base path in each `.html`, `.xml`,
`.json` and `.css` file of the copy. Every internal link starts with the tree base
path (D5), so the change is a prefix change. Alternative: redirect pages at the
root and `/latest/`. Rejected: a canonical link must point to a real page.

Call: before the first release, `assemble` copies the `next` tree to the root and
writes no `/latest/` tree. Every root page and every `/next/` page then shows the
banner "Pre-release docs. No version is released yet. These pages show `main`."

Call: banners and canonical links are written by `assemble`, not by the build,
because they depend on later releases. The layout writes an empty
`div.version-banner` element and no canonical link. `assemble` fills the banner on
each page below `/v/<minor>/` that is not the newest release: "You are reading
0.1 docs. The latest is 0.2.", with a link to the same page under `/latest/` when
it exists, or to `/latest/`. A `/next/` page after the first release gets "You are
reading docs for `main`, which is not released. The latest is 0.2." `assemble`
adds `<link rel="canonical">` to the same page under `/latest/` when that page
exists, on each page below `/v/`, `/next/` and the root. Pages work without
JavaScript, because the banner is static HTML.

Call: `assemble` writes `/moon-lander/versions.json` with
`{ "latest": "0.2", "next": true, "versions": ["0.2", "0.1"] }`; `latest` is
`null` before the first release. The layout writes `data-site-root` on `<html>`
next to `data-base`. The switcher island loads `versions.json` from the site root,
and lists `latest`, `next` and each version. On a choice, it sends a `HEAD` request
for the current path below the target tree. It opens that page when the answer is
200, and the target tree root when it is not. The island uses `extern "js"` for
`fetch`, as the search island does (D11).

Call: `check:site` finds `versions.json` at the root of an assembled site and then
checks each tree (the root, `/latest/`, `/next/` and each `/v/<minor>/`) as one
site. Every internal link in a tree must start with the base path of that tree.
The canonical link, the banner link and the switcher data are the only links that
can leave a tree.

## Risks / Trade-offs

- [R1. Rabbita `0.16.5` asks for `moonbitlang/async` `0.22.4`; the workspace pins
  `0.22.5`] → The tracer bullet builds `views` and `islands` with `0.22.5` first. If
  the resolver fails, use the Rabbita version that accepts `0.22.5`, or ask the
  owner before a change to the workspace pin.
- [R2. `beautiful_mermaid` draws a subset of Mermaid] → D9 makes a failure loud.
  The author uses an SVG image. The Design overview diagram is part of the tracer
  test.
- [R3. A Rabbita link without `escape=true` does nothing when clicked] → D12 guard
  test and the browser test click a search result.
- [R4. `mise run lint` may not check native-only and js-only packages] → Task 1
  verifies that `moon check` covers `apps/site` on `native` and `js`, and extends
  `scripts/lint-moonbit.mbtx` if it does not.
- [R5. The islands bundle grows past the budget] → D13 fails the build. Use
  `extern "js"` for browser APIs, as the model does.
- [R6. Bun is not pinned when this change starts] → The tracer bullet needs it.
  Do `add-configuration-core` task 1.2 first, or in the same pull request.
- [R7. GitHub Pages is not set to "GitHub Actions"] → The first deploy fails. The
  owner sets it before the tracer bullet merges.
- [R8. The site job adds time to each pull request (Chromium install)] → Cache the
  Playwright browser directory. Add a detector (D17) if the job passes 10 minutes.
- [R9. The Design overview drifts from the OpenSpec changes] → The page is marked
  proposed. Bead `lander-4us.6` replaces it with user docs from the implemented API.

- [R10. The `moon doc` JSON format is not documented and can change] → The
  toolchain pin in `.config/mise/config.toml` fixes moon. The D21 fixture test fails
  loudly when the shape changes. A moon update changes the fixture in the same pull
  request.
- [R11. The signature HTML form can change] → The D21 parser fails the build on
  markup that it does not know, and parser tests cover the known form.
- [R12. `moon doc` adds time to each build] → The step runs once for each module in
  `api`. If a later `moon doc` run removes the output of an earlier run,
  `site.mbtx` copies each module's JSON to a staging directory below `_build/`
  before the next run.

- [R13. The deploy size and download time grow with each minor line, and the
  newest release is in the site three times] → Each tree is static HTML with no
  large assets. `assemble` prints the size of each tree. If the Pages artifact
  nears its limit, a later change keeps only the newest N lines.
- [R14. A release asset is missing or corrupt] → `assemble` fails the deploy and
  names the release tag. The site stays at the last good deploy.
- [R15. A wrong base path in one version tree] → The tree check of `check:site`
  fails on a link that leaves its tree. A test of the prefix change covers the
  root and `/latest/` copies.
- [R16. There is no release workflow yet] → `site-asset.yml` is ready for it. Task
  group 11 records the dependency. Until a release has the asset, the root shows
  `main` with the pre-release banner.

## Migration Plan

No migration. The site is new. To roll back, revert the change and turn off GitHub
Pages. The library modules do not change. Release assets stay on their releases
after a rollback, so a later deploy can use them again.

## Open Questions

- The landing page text and the mark (`assets/lander-mark.svg`). The owner can
  supply them at any time; a plain text mark works until then.

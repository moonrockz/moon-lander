# Moon-Lander docs site

`moonrockz/moon-lander-site` is a private native consumer of the published
`moonrockz/telescope@0.5.1` package. Telescope supplies the shell, Smithy palette,
Markdown planner, API pages, search, browser controls, checks, serving and version
assembly. The published framework has no site or UI dependency.

## Consumer packages

| Package | Responsibility | Targets |
| --- | --- | --- |
| `policy` | Typed paths, ports, tree prefixes and CLI commands | all four |
| `providers` | Mermaid SVG and layers fence adapters | native |
| `runtime` | Git source policy and calls to the shared native host | native |
| `driver` | Build, check and serve executable | native |
| `assemble` | GitHub release selection, downloads and the shared assembly call | native |

`scripts/highlight.ts` keeps dual-theme Shiki highlighting and the existing rule
that unselected packages in API signatures appear as plain text. The source
preflight rejects untested MoonBit examples and drafts in main builds. These are
consumer policies; common site infrastructure stays in Telescope.

The pinned Telescope release omits `/api/` from content-link route resolution. The landing
source uses the single `moon-lander-route://api-index` compatibility marker.
The native adapter requires a generated API index, resolves the marker using
the active base and checks the finished output. Unknown marker URLs fail. Published
links use ordinary paths and work without JavaScript. Remove this pass
when a pinned Telescope release accepts normal API-index content links.

## Content and assets

| Source | Route |
| --- | --- |
| `docs/<path>.md` or `.html` | `/docs/<path>/` |
| Package READMEs selected in `site/site.json` | `/docs/packages/<name>/` |
| Compiler metadata for the selected `api` modules | `/api/<package path>/` |
| `site/articles/YYYY-MM-DD-slug.md` | `/articles/<slug>/` and the Atom feed |
| `site/pages/index.html` | `/` |
| `site/assets/` | `/assets/` through an explicit static mapping |

Brand originals, prompts and the brand preview stay in `docs/assets/brand/`.
They do not become docs pages. Small deployment copies live in
`site/assets/brand/`; the icon bytes match the originals. The landing page's
`site/assets/landing.css` uses scoped selectors and Telescope's theme tokens.
The header and favicon paths come from `site/site.json`.

Source roots include `tests/` so links to browser consumer examples can resolve
to GitHub. These files do not become pages. The runtime includes only Git-visible
content and rejects a tracked or unexcluded `docs/superpowers/` plan.

## Build and preview

Run from the repository root:

```shell
mise run build:site
mise run check:site
mise run test:site
mise run dev:site
```

The build writes `_site/`. Preview serves
`http://127.0.0.1:4173/moon-lander/`. A MoonBit polling loop rebuilds after source
changes; Telescope owns the loopback server and path containment. Use
`mise run dev:site -- --no-watch --port 4175` for a fixed preview on another port.

`build:site` runs `moon doc` for the selected modules, calls the released host,
measures its shared island bundle, applies highlighting and checks the final
output. Host failures preserve the prior tree. `test:site` runs native consumer
tests, portable CLI policy tests, highlight tests and the browser acceptance
checks against an already built site.
Use `mise run test:site -- --port 4178` when another project uses the default
browser acceptance port, 4174.

The installed shared island bundle measures 24,915 bytes with the task's gzip
measurement, below the 25 KiB warning threshold and 27 KiB limit. No browser editor or gallery is enabled.

## Version trees

Keep the existing task interface:

```shell
mise run build:site -- --main --tree next
mise run check:site -- --tree next
mise run test:site -- --tree next
mise run build:site -- --main --tree 0.7
```

A minor-line build must match the root `moon.mod`. Main lives below `/next/`,
release lines below `/v/<minor>/`, and assembly writes root and `/latest/` copies.
Release discovery remains paginated and skips drafts, prereleases and lines below
`versions.since`. Missing or corrupt site archives fail before deployment.

`assemble` stages supplied trees outside the destination and calls Telescope's
offline assembler. A small metadata pass retains Moon-Lander's banner wording,
canonical policy and missing-page fallback links. Historical assets are copied
byte for byte, without rebuilding the release from source. The existing GitHub
Pages workflow remains the deployment path.

## Migration evidence

The public package compiles on the repository's MoonBit pin without a local
override. Before deleting the old engine, its 72 content routes and all heading
and API anchors matched the shared-host output. SVG marker IDs now have per-block
prefixes to prevent collisions. Consumer fixtures cover root/next bases, content
errors, ignored files, scratch plans and retained version trees.

The build-master review keeps the existing workflow graph. Pull requests and the
merge queue call `site-build.yml` with `pages: false`, and `ci-ok` requires that
job to succeed. Main builds and checks the assembled artifact before the separate
Pages deployment job can write. Release assets keep their minor-line archive name
and read-only build permissions. The Playwright cache still uses the unchanged
`apps/site/bun.lock`; Telescope resolves from the published MoonBit dependency pin.

Telescope 0.5.1 repairs Windows canonical paths and sibling staging. The site
source preflight compares canonical paths with native separators, and test
cleanup restores write access to Git fixture files. The Windows workspace job
verifies this consumer against the actual published dependency.

# Moon-Lander docs site

`moonrockz/moon-lander-site` builds the static docs site of this repository. It is a
docs tool and is not published.

| Package | Content | Targets |
| --- | --- | --- |
| `model` | Site configuration, routes, search entries, build problems, and the `moon doc` reader and signature links of the API pages | all four |
| `content` | Front matter, Markdown, heading anchors and the HTML passes of the building blocks | `native` |
| `views` | Rabbita components for each page kind | `native` |
| `site` | Sources to outputs: pages, links, sidebar, articles, feed, search index and API pages | `native` |
| `generate` | Executable that reads the repository and writes `_site/` | `native` |
| `check` | Executable that checks the links of a built `_site/`, tree by tree when it is assembled, and warns about API items without a docstring | `native` |
| `assemble` | Executable that adds the release trees to a `next` build and writes the versioned site: root, `/latest/`, banners, canonical links and `versions.json` | `native` |
| `islands` | Client islands, bundled with Bun into `_site/assets/islands.js` | `js` |

`scripts/highlight.ts` highlights code blocks with Shiki after `generate`. It is the
only TypeScript step.

## Content

| Source | Route |
| --- | --- |
| `docs/<path>.md` or `.html` | `/docs/<path>/` |
| `site/articles/YYYY-MM-DD-slug.md` | `/articles/slug/`, also in `/articles/atom.xml` |
| `README.md` or `README.mbt.md` of a package in `packages` | `/docs/packages/<name>/` |
| `site/pages/index.html` | `/` |
| `moon doc` output of a module directory in `api` | `/api/<package path>/`, and the index `/api/` |

The sidebar groups come from `nav` in `site/site.json`. Each page below `docs/` must
match a `nav` item, or the build fails.

## API pages

`build:site` runs `moon doc` in each module directory of `api` in `site/site.json`, with
the output below `_build/site-api/<module directory>/`. `generate` reads
`module_index.json` and `package_data.json` and writes one page for each package. The
sections are Types, Errors, Traits, Type aliases and Values; an empty section is not
shown. Each item has the anchor `#<name>`. A method has `#<Type>.<method>`, and a method
of a trait implementation has `#<Type>.<Trait>.<method>`, or `#<Trait>.<Type>.<method>`
below a trait. A signature link to a package on the site goes to its API page; any other
target is plain text. `check:site` prints a warning for each item and method without a
docstring.

## Building blocks

| Block | Write | Build output |
| --- | --- | --- |
| Table | GitHub Markdown table | `<table>` |
| Code | fenced block with a language | Shiki colors for the light and dark themes |
| Diagram | ```` ```mermaid ```` block | inline SVG in `figure.diagram`; a diagram that does not render fails the build |
| Image | relative image link | a copy below the route of the page |
| Callout | `> [!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` or `[!CAUTION]` | `aside.callout.<kind>` with a label |
| Status | `status: proposed` in the front matter | the banner "Proposed — not implemented" and a sidebar badge |
| Layer stack | ```` ```layers ```` block, one `name \| detail` line for each layer | `figure.layer-stack` |

A `moonbit` or `mbt` fence outside a `.mbt.md` file must say `notest`, for example
```` ```moonbit notest ````, because `moon test` does not compile it. Put an example
that a reader can copy in a `.mbt.md` file of its package.

The site configuration is `site/site.json` at the repository root. The landing page
is `site/pages/index.html`. Static assets are in `apps/site/assets/`.

Build, check and preview the site from the repository root:

```shell
mise run build:site
mise run check:site
mise run test:site
mise run dev:site
```

`dev:site` serves the site at `http://127.0.0.1:4173/moon-lander/` and builds it
again after a source file changes.

`check:site` checks the built `_site/`: internal links, page titles, the Atom feed,
and that no file is below `docs/superpowers/`. `test:site` runs the tests of the
site packages and then a Chromium smoke test (`apps/site/scripts/browser-test.ts`)
against `_site/`, served on port 4174, so build the site first.

The output is `_site/`. Each route is a directory with `index.html`, and each link
starts with the `base_path` of `site/site.json`.

## Versions

The deployed site is versioned. CI builds `main` as the `next` tree with
`mise run build:site -- --main --tree next`, so its pages are in `_site/next/` and
each link starts with `/moon-lander/next/`. A release builds the tree of its minor
line with `--tree <minor>`, in `_site/v/<minor>/`, and attaches it as
`site-<minor>.tar.gz`. `--tree` fails for a minor line that is not the line of the
root `moon.mod`. A source page cannot have a route below `v`, `next` or `latest`.

On `main`, `mise run assemble:site` reads the releases with `gh`, downloads the
asset of the newest release of each minor line from `versions.since` in
`site/site.json` on, and writes the root, `/latest/`, the version banners, the
canonical links and `versions.json`. Then `mise run check:site` checks each tree:
a link that leaves its tree fails, except the banner link and the canonical link.
The version switcher in the header reads `versions.json`.

The design is in `openspec/changes/archive/2026-10-22-add-docs-site/design.md`,
and the requirements are in `openspec/specs/docs-site/spec.md`.

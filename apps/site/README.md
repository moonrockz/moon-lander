# Moon-Lander docs site

`moonrockz/moon-lander-site` builds the static docs site of this repository. It is a
docs tool and is not published.

| Package | Content | Targets |
| --- | --- | --- |
| `model` | Site configuration, routes, search entries and build problems | all four |
| `content` | Front matter, Markdown, heading anchors and the HTML passes of the building blocks | `native` |
| `views` | Rabbita components for each page kind | `native` |
| `site` | Sources to outputs: pages, links, sidebar, articles, feed and search index | `native` |
| `generate` | Executable that reads the repository and writes `_site/` | `native` |
| `check` | Executable that checks the links of a built `_site/` | `native` |
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

The sidebar groups come from `nav` in `site/site.json`. Each page below `docs/` must
match a `nav` item, or the build fails.

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

The output is `_site/`. Each route is a directory with `index.html`, and each link
starts with the `base_path` of `site/site.json`. The design is in
`openspec/changes/add-docs-site/design.md`.

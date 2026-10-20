# Proposal: Add the docs site

## Why

Moon-Lander has no place for user docs or articles. The hosting and configuration
changes add a large public API, and the owner wants that API explained in short
pages that mix prose with tables, compiled code, diagrams and small figures.
finos/morphir-moonbit already builds such a site with Rabbita
(`apps/morphir-site`, commit 32ab9d7). This change ports that model now, so that
the docs can grow with the code. The owner also wants API reference pages on the
same site (2026-10-20), so that prose pages can link to each public item, and
versioned docs, so that a user of an older release can read the docs and API of
that release.

## What Changes

- Add the unpublished workspace module `apps/site` (`moonrockz/moon-lander-site`,
  version `0.1.0`). It is a static site generator for the docs, and it uses Rabbita
  only to render HTML at build time and to run small client islands. It is not a
  framework UI package. The published library stays free of UI code.
- Split `apps/site` into the packages `model`, `content`, `views`, `site`,
  `generate`, `check` and `islands`, as in the model, and add `assemble` for the
  versioned deploy. Each package declares the
  targets that it supports, so `mise run check` on `wasm`, `wasm-gc`, `js` and
  `native` continues to pass.
- Add `site/site.json` with the base path `/moon-lander/`, `site/pages/index.html`
  for the landing page, `site/articles/` for dated articles, and `docs/` for user
  docs. Each route is written as `route/index.html`.
- Give the site the building blocks of the docs style: tables, highlighted code,
  Mermaid diagrams rendered to SVG at build time, SVG images, callouts, status
  badges and a layer-stack figure.
- Add client islands for the theme toggle (system, light, dark), the search box,
  the mobile menu, the copy buttons, the "On this page" marker and the version
  switcher, with a size budget.
- Add API reference pages for the published packages. The site build runs
  `moon doc` for each module that `site/site.json` lists, and `generate` reads the
  `package_data.json` and `module_index.json` output. Each package gets one page
  at `/api/<package path>/` with docstrings, signatures, item anchors and source
  links. A package index lists the modules and packages. Prose pages link to API
  items with `api:` links, which the link check resolves.
- Add versioned docs. Each minor line has a tree at `/v/<minor>/`, for example
  `/v/0.1/`. `/next/` tracks `main`. The site root and `/latest/` show the newest
  release; before the first release, the root shows `main` with a pre-release
  banner. Each release keeps its built site as a release asset, and the Pages
  deploy puts the kept versions together with no rebuild. A version switcher, a
  banner on older versions and canonical links to `/latest/` help readers.
- Add the reusable workflow `site-asset.yml` that builds the site asset of one
  minor line. A future release workflow calls it. This change does not create a
  release or a release workflow.
- Add a search index, an Atom feed for articles, link and anchor checks, a check
  of the built site, and one browser smoke test.
- Add moonx task scripts `scripts/site.mbtx` and `scripts/serve-site.mbtx` that use
  `moonbitlang/async`. Expose them as the mise tasks `build:site`, `dev:site`,
  `test:site` and `check:site`. Bun is only a tool that bundles the islands and runs
  Shiki for highlighting.
- Add the workflows `site-build.yml` (reusable: build, check, test) and `site.yml`
  (deploy to GitHub Pages from `main`). Pull requests build and test the site
  through CI and do not deploy. CI stays read-only.
- Add the first content page, "Design overview", ported from the spec explainer
  page and marked "Proposed — not implemented".
- Add `docs/WRITING_FOR_THE_SITE.md`, the guide for authors.
- Add a narrow exception to `AGENTS.md`, the `openspec/config.yaml` context and the
  `README.md` "no UI packages" text: Rabbita is allowed only in `apps/site`.

## Capabilities

### New Capabilities

- `docs-site`: the generation, content rules, client behavior, checks and
  deployment of the Moon-Lander docs site.

### Modified Capabilities

None.

## Out of scope

Call: these items are not part of this change.

- Preview deploys for pull requests. Pull requests build and test the site only.
- A release workflow and the first release. `AGENTS.md` says to ask before a
  release is cut. This change only adds the reusable step that a release workflow
  calls.
- A storage branch for old versions, and a rebuild of old versions from tags.
- Translations and other languages (i18n).
- A custom domain, analytics, cookies, comments and third-party fonts or scripts.
- A client-side Mermaid renderer. A diagram that does not render at build time
  fails the build (design D9).
- A workbench or playground page such as Morphir's `/try/`.
- User docs for the hosting and configuration API. Each hosting change adds its
  pages when it is implemented. The bead `lander-4us.6` covers the framework
  overview page and article.
- Any UI package in the published library, and any change to Moonbase.
- API pages from `.mbti` files, and API pages for packages that do not exist yet.
  The hosting packages get API pages when they land (design D21).

## Impact

- New: `apps/site/` (MoonBit module, `package.json`, `bun.lock`, assets, Bun
  scripts for bundling and highlighting), `site/`, `docs/`,
  `scripts/site.mbtx`, `scripts/serve-site.mbtx`, `.github/workflows/site.yml`,
  `.github/workflows/site-build.yml`, `.github/workflows/site-asset.yml`.
- Reads at build time: the `moon doc` output below `_build/doc/` for the modules
  `pkgs/lander` and `pkgs/notebooks`. Its JSON format is not documented; the
  toolchain pin and fixture tests guard it.
- Changed: `moon.work` (new member), `.config/mise/config.toml` (four tasks),
  `.github/workflows/ci.yml` (site job in `ci-ok`), `.gitignore` (`_site/`),
  `AGENTS.md`, `README.md`, `openspec/config.yaml`.
- Dependencies of `apps/site` only: `moonbit-community/rabbita@0.16.5`,
  `moonbit-community/cmark@0.4.12`, `bobzhang/beautiful_mermaid@0.2.0`,
  `moonbitlang/async@0.22.5`, `moonbitlang/x@0.5.5`, `moonrockz/expect@0.6.1`;
  npm `shiki` and `playwright`. The library modules get no new dependency.
- Tools: Bun, pinned by `add-configuration-core` task group 1
  (bead `lander-4us.2.1`).
- Repository setting: GitHub Pages must use "GitHub Actions" as its source.
- Releases: each future release must carry the asset `site-<minor>.tar.gz`. The
  deploy reads release assets with `contents: read` only.

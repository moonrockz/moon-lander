# Tasks: add-docs-site

Epic: lander-4us.7

Each group is one story. The design is in `design.md`. The requirements are in
`specs/docs-site/spec.md`. Run `mise run check` at the end of each group. Run
`mise run format` before each commit. This change needs Bun from
`add-configuration-core` task 1.2 (bead `lander-4us.2.1`); do that task first if it
is still open.

## 1. Tracer bullet: one page built and deployed

Bead: lander-4us.7.1

- [ ] 1.1 Create `apps/site/moon.mod` (`moonrockz/moon-lander-site`, version `0.1.0`, imports of design D3) and the packages `model`, `views` and `generate` with the `supported_targets` of design D2; add `./apps/site` to `moon.work`; verify that `mise run validate` passes and that the resolver selects `moonbitlang/async` `0.22.5` with Rabbita `0.16.5` (risk R1).
- [ ] 1.2 Add `site/site.json` (design D4) and `SiteConfig::parse` with the `base_path` check and `href`; verify the "Bad base path" and "Links use the base path" scenarios with unit tests on all four targets.
- [ ] 1.3 Add a minimal Rabbita `layout` and a `generate` executable that writes `_site/index.html` from `site/pages/index.html` and `_site/assets/site.css`; verify the "Route file" scenario with a native test that reads the output.
- [ ] 1.4 Add a first `scripts/site.mbtx build` that runs `generate` through `moonbitlang/async/process` and exits with a non-zero code on failure, and the mise task `build:site`; verify that `mise run build:site` writes `_site/index.html` and that a failed step gives a non-zero exit code.
- [ ] 1.5 Add `_site/` to `.gitignore`.
- [ ] 1.6 Verify that `mise run lint` checks `apps/site` on `native` and `js` (risk R4); if it does not, extend `scripts/lint-moonbit.mbtx` and its test.
- [ ] 1.7 Add `.github/workflows/site-build.yml` (build and upload when `pages` is true), `.github/workflows/site.yml` (deploy job with job-level `pages: write` and `id-token: write`), and a `site` job in `ci.yml` that `ci-ok` needs (design D17); verify with `mise run lint:yaml`, a green pull request run, and a deploy from `main` that serves `https://moonrockz.github.io/moon-lander/`. The owner sets the Pages source to "GitHub Actions" before the merge (risk R7).

## 2. Build script and local preview

Bead: lander-4us.7.2

- [ ] 2.1 Complete `scripts/site.mbtx build [--main]` with the steps of design D6 except `moon doc` (Bun install, islands build, Bun bundle, gzip budget, generate, highlight; task 10.1 adds `moon doc`); verify the "Step fails" scenario and that `--main` reaches `generate`.
- [ ] 2.2 Add `apps/site/package.json` (private, `0.1.0`, `shiki` and `playwright` of design D3), `bun.lock`, and `apps/site/scripts/highlight.ts` ported from the model with `mbt` mapped to `moonbit`; verify the "Known language" and "Unknown language" scenarios with a test of `highlightHtml`.
- [ ] 2.3 Add `scripts/serve-site.mbtx` with `moonbitlang/async/http`, the path rules of design D6, `--port`, `--no-watch`, and `mtime` polling that runs the build again; add `dev:site`; verify the "Directory request", "Path outside the base" and "Path escape" scenarios with tests of the pure path function.
- [ ] 2.4 Add `site.mbtx check` and `site.mbtx test` with the tasks `check:site` and `test:site`; add the tests of the pure parts of both scripts to `mise run test:scripts`; verify that `mise run test:scripts` passes.
- [ ] 2.5 Document the four tasks in the `README.md` task table; verify that each documented command runs as written.

## 3. Content pipeline

Bead: lander-4us.7.3

- [ ] 3.1 Add the `content` and `site` packages: source list from `git ls-files --cached --others --exclude-standard`, front matter, Markdown with heading anchors, and `doc_route`; verify the "Locally excluded plans" and "Plan not excluded" scenarios with a fixture repository.
- [ ] 3.2 Add the docs page view, the sidebar from `nav` with the model glob rules, and the "On this page" list; verify the "New page not in nav" scenario.
- [ ] 3.3 Add drafts and the `--main` flag; verify the "Draft in a local build" and "Draft in a main build" scenarios.
- [ ] 3.4 Add package pages from `README.md` and `README.mbt.md` below each listed package; verify the "Package page" and "Two README kinds in one directory" scenarios with `notebooks`.
- [ ] 3.5 Add link and anchor resolution, GitHub links for other repository files, and image copies; verify the "Relative Markdown link", "Missing anchor" and "SVG figure" scenarios.
- [ ] 3.6 Add articles below `site/articles/`, the articles index, the Atom feed at `/articles/atom.xml`, and the search index; verify the "Article route", "Date does not match" and "Date is not real" scenarios and a well-formed feed.

## 4. Theming and islands

Bead: lander-4us.7.4

- [ ] 4.1 Add the CSS tokens of design D7 with the explainer palette, dark tokens for `prefers-color-scheme` and `data-theme`, Shiki color variables, system font stacks, and the theme script before the first paint; verify a views test that the script is in `<head>` before the stylesheet link.
- [ ] 4.2 Add the `islands` package (js only) with the theme toggle, menu, copy buttons and "On this page" marker, empty mounts with `inner_html("")`, and `data-base` on `<html>`; verify a views test of the mount markup and the "Cycle" scenario logic in a unit test of `next_theme`.
- [ ] 4.3 Add the search island with `extern "js"` fetch and `location.assign`, without `rabbita/http`, `rabbita/nav` or `@json` (design D11); verify search ranking with `model` tests on all four targets.
- [ ] 4.4 Port the link-capture scanner to MoonBit with the six model cases, and a native test that scans `apps/site/islands/*.mbt`; verify the "Guard test" scenario with a fixture that has an unescaped anchor.
- [ ] 4.5 Make the gzip budget step warn above 25 KB and fail above 27 KB; verify the "Bundle too large" scenario with a test of the pure size rule.
- [ ] 4.6 Verify the "No JavaScript" scenario: a test of the rendered docs page finds the sidebar, the content and plain `href` values with no island code required.

## 5. Docs building blocks

Bead: lander-4us.7.5

- [ ] 5.1 Render GitHub Markdown tables; verify a table fixture in a `content` test.
- [ ] 5.2 Add the build-time Mermaid pass with `beautiful_mermaid` and no client fallback (design D9); verify the "Diagram renders" and "Diagram does not render" scenarios.
- [ ] 5.3 Add the callout pass for the five GitHub alert kinds; verify the "Warning callout" scenario and that a plain block quote stays a block quote.
- [ ] 5.4 Add the `layers` pass; verify the "Layer stack" and "Bad layer line" scenarios.
- [ ] 5.5 Add `status: proposed` with the banner and the sidebar badge; verify the "Proposed page" and "Unknown status" scenarios.
- [ ] 5.6 Add the MoonBit fence check of design D10; verify the "Untested example in docs" and "Example of a proposed API" scenarios, and the "Tested example" scenario with the `notebooks` README.

## 6. Design overview page

Bead: lander-4us.7.6

- [ ] 6.1 Port the spec explainer page to `docs/design/overview.md` with `status: proposed` and the section order of design D19, using a table, a Mermaid run-order diagram, a `layers` block, callouts and `moonbit notest` code; verify the "Overview marked as proposed" scenario in a `generate` test of the built page.
- [ ] 6.2 Draw any figure that `beautiful_mermaid` cannot render as an SVG file next to the page; verify that `mise run build:site -- --main` passes with no warning.
- [ ] 6.3 Add a short landing page in `site/pages/index.html` that links the Design overview and says that user docs come with each hosting change (bead `lander-4us.6`); verify that `mise run check:site` passes.

## 7. Checks, CI and Pages

Bead: lander-4us.7.7

- [ ] 7.1 Complete the `check` package and executable: internal links, titles, feed XML and the `docs/superpowers/` path; verify the "Broken internal link" scenario with a fixture output directory.
- [ ] 7.2 Add `apps/site/scripts/browser-test.ts` with the checks of design D16 except the API page check (task 10.10), run by the pinned Node against `serve-site.mbtx --no-watch --port 4174`; verify the "Smoke test passes" scenario with `mise run test:site`.
- [ ] 7.3 Make `site-build.yml` run `build:site -- --main`, `check:site` and `test:site`, and cache the Playwright browsers; verify the "Pull request" scenario on a pull request that changes `docs/`.
- [ ] 7.4 Verify after the merge that `main` deploys the site (task 11.10 completes the "Push to main" scenario), and that `ci.yml` and `site-build.yml` keep `contents: read` while only the deploy job has `pages: write` and `id-token: write`.

## 8. Rabbita exception in project rules

Bead: lander-4us.7.8

- [ ] 8.1 Add the narrow exception to `AGENTS.md`: Rabbita is allowed only in the unpublished module `apps/site`, a docs tool; the published library stays UI-free; verify by review that "Do not add UI packages" still holds for every other module.
- [ ] 8.2 Add the same exception to the `context` of `openspec/config.yaml` and to the "No UI packages" text of `README.md`; add `apps/site` to the README layout list; verify with `mise exec -- openspec validate --all --strict`.
- [ ] 8.3 Make `scripts/validate-packages.mbtx` fail when a module other than `apps/site` imports `moonbit-community/rabbita`; verify the "UI import in the library" scenario with a script test and the "Workspace targets" scenario with `mise run check`.

## 9. Writing guide

Bead: lander-4us.7.9

- [ ] 9.1 Write `docs/WRITING_FOR_THE_SITE.md` with the content of design D20 in ASD-STE100, with one example of each building block, and add it to `nav`; verify that `mise run build:site -- --main` and `mise run check:site` pass and the guide's Mermaid example renders as an SVG.
- [ ] 9.2 State in the guide that `docs/superpowers/` goes in `.git/info/exclude` and never in the site; verify that the guide links resolve in the build.

## 10. API reference pages

Bead: lander-4us.7.10

- [ ] 10.1 Add the `api` key to `site/site.json` with `pkgs/lander` and `pkgs/notebooks`, and its check (design D21); add the `moon doc` step to `scripts/site.mbtx build` for each listed module, with a staging copy if a later run removes earlier output (risk R12); verify the "Unpublished module in the API list" scenario and that `mise run build:site` leaves the JSON of both modules below `_build/`.
- [ ] 10.2 Add the pure `moon doc` JSON reader to `model` with typed API items and a `Problem` for a bad shape; add fixtures copied from the pinned moon output of `pkgs/notebooks`; verify the "Fixture shape" and "Format change" scenarios on all four targets.
- [ ] 10.3 Add the signature parser and the link rewrite (same package, other site package, outside the site); verify the "Signature text", "Unknown markup", "Same package" and "Package outside the site" scenarios with unit tests that use real signatures from the fixture.
- [ ] 10.4 Add the API page view and the `generate` output at `/api/<package path>/` with the five sections, no empty section, methods and impls below each item, docstrings through the D8 passes, and the item and method anchors; verify the "Package page", "Empty section" and "Method anchor" scenarios with a `generate` test of the built page.
- [ ] 10.5 Add source links at the built commit from `git rev-parse HEAD`, `loc.path` and `loc.file`; verify the "Source link" scenario with a unit test of the URL function.
- [ ] 10.6 Add the package index at `/api/` from `module_index.json` with README summaries, and the header "API" link; verify the "Index" scenario.
- [ ] 10.7 Add `api:` link resolution to the link pass and fail on an unknown package, item or method; document the syntax in `docs/WRITING_FOR_THE_SITE.md`; verify the "Item link" and "Unknown item" scenarios.
- [ ] 10.8 Add API items and methods to the search index; verify the "API item result" scenario logic with a `model` search test.
- [ ] 10.9 Add the missing-docstring warnings to `check:site`; verify the "Item without a docstring" scenario with a fixture.
- [ ] 10.10 Add the API page check of design D16 to the browser test; verify that `mise run test:site` passes and `mise run check` passes.

## 11. Versioned docs

Bead: lander-4us.7.11

- [ ] 11.1 Add `--tree <tree>` to `site.mbtx build` and `generate`: the tree base path, the output below `_site/<tree path>/`, the minor line check against the root `moon.mod` through `scripts/versions.mbtx`, and the reserved routes `v`, `next` and `latest` (design D22); verify the "Minor line tree", "Reserved route" and "Wrong line" scenarios with tests of the pure functions.
- [ ] 11.2 Make `site-build.yml` and `ci.yml` build with `--tree next`, and give `SITE_BASE` to the browser test; verify that `mise run test:site` passes on a `next` build.
- [ ] 11.3 Add `.github/workflows/site-asset.yml` (`workflow_call`, `contents: read`) that builds, checks and packs `site-<minor>.tar.gz` as a workflow artifact; verify the "Asset build" scenario with a `workflow_dispatch` test run on a branch, and `mise run lint:yaml`.
- [ ] 11.4 Record the dependency: a future release workflow must call `site-asset.yml` and attach `site-<minor>.tar.gz` to the release. Write it in a comment at the top of `site-asset.yml` and in the `README.md` release notes, and make a bead for the release workflow. Do not create a release or a release workflow (`AGENTS.md`); verify by review.
- [ ] 11.5 Add `site.mbtx assemble`: read all releases with `gh api --paginate`, skip drafts, prereleases and minor lines below `versions.since` (add `versions.since` to `site.json`, starting at `0.2`), select the newest release of each minor line, download and unpack each asset, and fail with the release tag on a missing or corrupt asset; pin `gh` in `.config/mise/config.toml` if the runner image does not supply it; verify the "Patch release", "Missing asset", "Release before site assets" and "More than 30 releases" scenarios with tests of the pure selection and a fixture archive.
- [ ] 11.6 Add the `assemble` package: the copies at the root and `/latest/` with the base path prefix change, the pre-release root, the banners, the canonical links and `versions.json`; verify the "No release", "Old version page" and "Page in latest" scenarios with a fixture of two version trees.
- [ ] 11.7 Add the empty `div.version-banner`, `data-site-root` and the version switcher island with `extern "js"` `fetch` and `HEAD` requests; verify the "Page exists" and "Page missing" scenarios with a unit test of the pure target rule, and that the islands stay in the budget of design D13.
- [ ] 11.8 Make the search island load the index of its own tree; verify the "Search in an old version" scenario with a `model` test of the index URL.
- [ ] 11.9 Add the tree check to `check:site` for an assembled site; verify the "Link leaves its tree" scenario with a fixture.
- [ ] 11.10 Make `site-build.yml` run `assemble` and `check:site` on the assembled site before the Pages upload when `pages` is true, with `contents: read`; verify the "Push to main" scenario after the merge: `/moon-lander/` shows the pre-release banner and `/moon-lander/next/` serves the `main` build. Run `mise run check`.

## Workflow follow-up

- Make one bead for each group under one epic, and write the IDs on the `Bead:` lines.
- Archive the change after all groups are done and the site deploys from `main`.

# Tasks

Epic: lander-weo. Group 2 depends on group 1; group 3 depends on group 2;
group 4 depends on groups 2 and 3. The owner approved a small native compatibility
adapter for Telescope 0.4.0's API-index content-link gap; see UI-1 in design.html.

## 1. Prove the released Telescope build

Bead: lander-weo.1

- [x] 1.1 Pin published `moonrockz/telescope@0.5.1` in the private site tool and add a thin native host driver; verify resolution and compilation on the repository's current MoonBit pin without a sibling-worktree override.
- [x] 1.2 Register pure Mermaid and layers fence adapters around the current renderers; verify valid SVG/layer output, unique diagram IDs and source/ordinal diagnostics with focused adapter tests.
- [x] 1.3 Build a real package guide and the notebooks API from current `moon doc` output at `/moon-lander/` and `/moon-lander/next/`; verify `CellKind`, method anchors, source links, header assets and both fence providers through Telescope check.
- [x] 1.4 Measure the released shared island bundle against the existing 25 KiB warning and 27 KiB failure budget, and verify a selected existing code block keeps dual-theme highlighting; record compatibility results in the site tool README before broad migration.

## 2. Move the complete documentation path

Bead: lander-weo.2

- [x] 2.1 Translate the site configuration for the shared host and separate page discovery from explicit static assets; verify package/subpackage guides, articles, feed, API pages and the exclusion of brand metadata and scratch plans using focused content fixtures.
- [x] 2.2 Preserve Moon-Lander's content policies and the Shiki post-pass where required; port behavioral tests for checked examples, plain unknown languages, diagrams, layers, callouts, drafts, status banners and malformed inputs, then verify a complete checked site build.
- [x] 2.3 Capture a local route and declared-anchor inventory with the old generator and compare it with the new output for the same reviewed sources; verify every existing content/API route and anchor remains valid except the changed home heading, without committing the generated inventory or baseline build.
- [x] 2.4 Replace the generic local model, views, planner, checker and islands with shared host calls once parity passes; update generated interfaces, dependency rules and the site tool README, then verify all supported workspace targets remain valid and no published library gains a site/UI dependency.

## 3. Ship the landing page and visual identity

Bead: lander-weo.3

- [x] 3.1 Implement the reviewed landing fragment and scoped local stylesheet with the design's headline, framework description, docs/API actions, installation command and package guide sections; verify every internal action resolves in both project-base and next builds.
- [x] 3.2 Put the optimized mascot derivative and selected icon copies in `site/assets/brand/`, map that unexcluded directory into output assets, configure the header icon and favicon, and verify icon bytes match the originals and asset sizes, labels and URLs work under both bases without publishing the large originals or brand notes as pages.
- [x] 3.3 Extend site browser acceptance for landing content, actual light/dark palette tokens, contrast, stored/system themes, keyboard focus, 390 px layout, image loading and no-script navigation; verify screenshots at desktop/phone widths and both themes.
- [x] 3.4 Update the site writing guide with landing, asset and styling ownership and correct the stale installation text; verify the documented local build/preview commands and links work.

## 4. Preserve preview, version assembly and CI

Bead: lander-weo.4

- [x] 4.1 Route existing build/check/test mise tasks through the new driver and retain the MoonBit watch loop around Telescope serving; update task tests and preview documentation, and verify source changes rebuild at the existing loopback URL with nonzero failure propagation.
- [x] 4.2 Keep paginated release selection and downloads in Moon-Lander, then pass a supplied-tree manifest to shared offline assembly; verify a retained historical-tree fixture preserves binary bytes, base paths, root/latest/next/version routes, canonical links, banners, version selection and per-tree search.
- [x] 4.3 Update site workflow commands, dependency caches and release-asset integration only where required; run the build-master review and verify PRs build/check/test without deployment while main and release asset jobs retain their current permissions and artifact contracts.
- [x] 4.4 Run `mise run format`, `mise run check`, root/next `build:site`, `check:site`, `test:site`, the assembly fixture and strict OpenSpec validation; review the full change with the repository checklist and resolve confirmed findings before marking the group complete.

## Workflow follow-up

- Open implementation pull requests with completed task boxes and real bead IDs.
- Archive this change in the last task group's pull request and validate the archived result.
- After merge, close each completed bead with the PR and merge SHA, close the finished epic and sync the tracker as CONTRIBUTING.md requires.
- Deploy through the existing main-branch workflow. Obtain owner approval separately for any release or publication.

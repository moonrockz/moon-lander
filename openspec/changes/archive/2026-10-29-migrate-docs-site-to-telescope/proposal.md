# Proposal

## Why

Moon-Lander's docs site has a small text-only landing page and a separate gold
theme. Its custom site generator duplicates the shared Telescope toolkit. Use
the new Moon-Lander artwork and Smithy's visual style to give readers a clear
starting point and move common site behavior into Telescope.

## What Changes

- Build the unpublished docs tool on the published `moonrockz/telescope@0.5.1`
  package, with its shared shell, theme, search, navigation and site checks.
- Add a landing page with a large headline, the bunny-and-lander mark, direct
  documentation and API links, installation instructions and package guides.
- Use Smithy's indigo accents and cool neutral surfaces in light and dark modes.
  Use the Moon-Lander icon in the header and as the favicon.
- Preserve docs and API routes, source links, Markdown features, diagrams,
  search, articles and versioned release trees during the migration.
- Keep release selection and downloads in Moon-Lander's MoonBit tasks. Use
  Telescope to assemble the supplied version trees.
- Remove the common generator and browser code that Telescope replaces.

Out of scope: framework API changes, new published modules, a playground or
tutorial engine, changes to Smithy, rebuilding past release
assets, and publishing from a workstation.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `docs-site`: A branded landing page, Smithy palette, header and browser icons,
  source discovery rules for brand assets, and acceptance checks for the site
  migration.

## Tracking

The approved change is tracked by epic `lander-weo`. Its four task groups are
stories `lander-weo.1`, `lander-weo.2`, `lander-weo.3` and `lander-weo.4`, in
dependency order. Keep these stories open until their implementation PRs merge.

## Impact

`apps/site`, `site/site.json`, `site/pages/index.html`, site assets,
`scripts/site.mbtx`, `scripts/serve-site.mbtx`, the mise task configuration and
site build/release workflows. The writing guide and package validation must
describe the smaller site tool. The published framework remains UI-free and
keeps its current dependency graph.

The owner approved the upstream Windows repair and Telescope 0.5.1 publication
as a follow-up. This change pins that real release after public qualification;
Moon-Lander does not copy or patch Telescope source.

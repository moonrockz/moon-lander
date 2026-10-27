## Why

WebKit page loads stall about once in 350 loads on GitHub Linux runners
(bead `lander-4us.22`): `page.goto` waits for `load` until the 15-second test
limit, at a random test. It occurs in the `ci.yml` browser container and on the
plain runner of the release workflow. 1,320 local loads did not reproduce it,
in macOS WebKit and in Linux WebKit of the CI image. The fixture server answered
every page and module request. So a WebKit stall blocks unrelated pull requests
about once in every few runs.

## What Changes

- The pull-request gate (`ci.yml`, `ci-ok`) tests the browser suite in Chromium
  and Firefox only.
- A new workflow runs the browser suite in Chromium, Firefox and WebKit every
  night and on manual trigger, with the same container and failure checks.
- Release validation keeps all three engines: `mise run check` runs the suite in
  Chromium, Firefox and WebKit.
- `scripts/browser.mbtx test` gets `--engines <list>` to select engines. Without
  it, all three engines run. The deliberate-failure checks count the selected
  engines.

## Capabilities

### Modified Capabilities

- `browser-configuration`: the required execution gate.

## Impact

A WebKit-only regression no longer blocks a merge. The nightly run or the next
release run finds it. No library, API or browser behavior changes.

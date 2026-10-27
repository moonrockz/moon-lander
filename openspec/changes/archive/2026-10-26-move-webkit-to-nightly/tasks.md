## 1. Run WebKit nightly and in release validation, not in the PR gate

Bead: lander-4us.46

- [x] 1.1 Add `--engines <list>` to `scripts/browser.mbtx test`: parse each engine once, reject an empty, unknown or repeated engine, run all three without the flag, and count the selected engines in the deliberate-failure checks; test the parse in the script tests.
- [x] 1.2 Run the `ci.yml` browser job with `--engines chromium,firefox`; add a workflow that runs all three engines nightly and on manual trigger in the same pinned container; keep `mise run check` (release validation) on all three engines.
- [x] 1.3 Update the browser guides and the task description; archive this change and validate all specifications strictly.

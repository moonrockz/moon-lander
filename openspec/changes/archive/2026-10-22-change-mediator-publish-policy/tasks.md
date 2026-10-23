# Tasks: change-mediator-publish-policy

Epic: lander-4us.18

This change modifies `pkgs/lander/mediator` only. It adds no import, no
`#cfg` and no per-target file. Run each test on `wasm`, `wasm-gc`, `js` and
`native`. `mise run check` includes `check:mediator`, which fails a target
leg that runs zero mediator tests.

## 1. Publish runs every handler and reports every failure

Bead: lander-4us.18.1

- [x] 1.1 Add `PublishFailure` and the case `MediatorError::PublishFailed(handlers~, failures~)` as in design D1, and the `message` text of design D3; verify a test of `message` for one and for two failures, and a test whose event and handler error hold secret values and whose text holds neither
- [x] 1.2 Change `Topic::publish` so every handler runs one time in add order and the failures are raised as one `PublishFailed` after the last handler; replace the test "publish stops at the first handler that raises" with tests for one failure (position 2 of 3), two failures (positions 2 and 3, in order, each with its original error) and no failure
- [x] 1.3 Verify a topic middleware gets the one combined error from its next step and can catch it: both handlers have run and publish finishes with no error
- [x] 1.4 Verify `Sender::send` still passes a handler error out unchanged (the existing tests stay green, with no change)
- [x] 1.5 Update the publish and errors sections of the package `README.mbt.md` with a runnable example of a publish where one handler fails; verify the example runs in `mise run test` on all four targets
- [x] 1.6 Change the `tests/mediator-acceptance` scenario "Second handler raises" to the new contract and add a scenario "Two handlers raise"; verify the suite passes on all four targets
- [x] 1.7 Run `mise run lint` and commit the changed `pkgs/lander/mediator/pkg.generated.mbti`; verify it shows `PublishFailure` and the new case, and no other API change
- [x] 1.8 Add an `## Unreleased` section to `CHANGELOG.md` that states the breaking behavior change and the new case, and add the mediator to the `0.2.0` section; verify `mise run test:scripts` (the release script tests) still passes and no `## X.Y.Z` heading is added
- [x] 1.9 Run `mise run check`; verify lint, validation, all target tests, `check:mediator` and builds pass

## Workflow follow-up

- Archive this change after it merges.
- The owner decides the `0.3.0` release: a separate pull request changes the version in `moon.mod` and renames `## Unreleased` to `## 0.3.0 - <date>`.

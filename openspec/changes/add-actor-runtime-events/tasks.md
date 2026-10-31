# Tasks: Add actor runtime events

Status: approved on 2026-10-31. Implementation progress is tracked below. Epic
`lander-d0y` holds one story for each group. Each group includes its own tests
and runnable documentation.

## 1. Ion dependency and payload policy

Bead: lander-d0y.1

- [x] 1.1 Add `moonrockz/ion@0.6.0` to `pkgs/actors/moon.mod` and `moonrockz/ion/ion` to the actors package imports; add `moonrockz/ion` to the actors external limit in `scripts/validate-packages.mbtx`, with a package-level check that actors packages import no other Ion package; verify the accept and reject scenarios of the dependency requirement with task script tests and `mise run validate`
- [x] 1.2 Add `PayloadPolicy[M]` to the portable root with `omit`, `ion`, `json` and `encode`, and `omit` as the default; verify an Ion-native protocol (decimal and timestamp), a `derive(ToJson)` protocol through the bridge, a redacting encoder and a wrong-policy compile failure on wasm, wasm-gc, js and native
- [x] 1.3 Document the payload forms and the secret warning in the actors README with compiled examples; verify the README tests and the isolated actors candidate consumer with the Ion dependency

## 2. Runtime event channel and lifecycle events

Bead: lander-d0y.2

Depends on: none; runs in parallel with group 1.

- [x] 2.1 Add `RuntimeEvents` with `new`, `subscribe`, `close` and `subscriber_count` and no public publish, `EventSubscription` with `unsubscribe` and `dropped_count`, and the optional `events` argument of `scope`; verify subscription end at unsubscribe and scope exit, subscribe after close, and a compile failure for an application publish
- [x] 2.2 Publish `Started` and `Ended` from the runtime, with child scopes that use the parent channel and top-level scopes that use only their own; verify lifecycle order, the failed end value, no events for a failed initializer, child actor events, the separate top-level scope and one channel for two scopes, with acknowledgement-based tests on wasm, js and native
- [x] 2.3 Deliver with non-waiting admission in subscription order: drop and count on full, remove on closed, and publish no event about event delivery; verify the slow subscriber, the ended subscriber and the no-feedback scenarios, and that a scope without a channel publishes nothing
- [x] 2.4 Add a runnable example of a test that waits for an `Ended` event instead of polling `status()`; verify it compiles and runs on all runtime targets with `mise run check:actors`

## 3. Undelivered events and payloads

Bead: lander-d0y.3

Depends on: groups 1 and 2.

- [x] 3.1 Publish `Undelivered` with the `Full`, `Closed` and `Discarded` reasons from `try_send`, `reenqueue`, `send` and the mailbox discard path; verify queue order before `Ended` on cancellation, no events for a close snapshot, and closed sends after the end, on wasm, js and native
- [x] 3.2 Add the optional `payload` argument to `start`, `start_with`, `spawn` and `respond`, encode only for an undelivered event with at least one subscription, and give each subscriber an independent copy; verify the no-subscriber encoder count of zero, independent payloads, the default omitted payload and no payload for service closures
- [x] 3.3 Add runnable examples of a dead-letter counter and of a bridge actor that writes events to a logger through `@ion/json.to_json`, in the unpublished acceptance tests; verify the examples and that no published module imports logging for them

## 4. Integration

Bead: lander-d0y.4

Depends on: group 3.

- [ ] 4.1 Compare the acceptance evidence with every requirement of `actor-runtime-events` and the changed dependency requirement; verify each scenario has a test that runs on its stated targets
- [ ] 4.2 Run the local actor benchmark with and without a channel and record the result in the pull request; verify that no benchmark runs in `mise run check` or CI
- [ ] 4.3 Generate and review the `pkg.generated.mbti` files, run `mise run format`, `mise run check` and `mise exec -- openspec validate --all --strict`; verify all pass

## Workflow follow-up

- Keep beads open until their pull requests merge. Include tests and docs in each group's pull request.
- The final group's pull request archives this change. Close the completed stories and epic with the PR and merge SHA, then sync beads as `CONTRIBUTING.md` requires.
- Publication needs a later owner-approved release change. Do not publish from the workstation.

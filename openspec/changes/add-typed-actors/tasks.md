# Tasks: Add local typed actors

Status: approved for implementation. Damian dispatched this change on 2026-10-28.
Epic `lander-25h` holds one story per group. Group 2 also depends on release 0.7.0
(`lander-7ft`), because module and publication integration must follow that release.
Each lasting group includes its own tests and runnable documentation.

## 1. Feasibility spike through the public API

Bead: lander-25h.1

- [x] 1.1 Build an unpublished actor fixture with the existing async pin; compile the ACT-2 counter example and an Ox-style service with two different ask result types, with no dynamic cast; record the compiler and target results in the design
- [x] 1.2 Prove idle actor scope exit, normal parent exit with a live child, and ask wakeup on termination with acknowledgement-based tests on wasm, js and native; verify no actor or waiter remains after the enclosing scope returns
- [x] 1.3 Prove selective receive retains non-matches in order and counts them against bounded capacity; verify scan cancellation, selector error and a blocked matching send without an uncounted stash
- [x] 1.4 Compile the portable policy shape on all four targets and confirm runtime target rejection on wasm-gc; revise the design if any public example or lifetime rule cannot be implemented, before starting group 2
- [x] 1.5 Compile the NAME-1 and DIR-1 named actor and immutable directory examples with no Any or cast; prove distinct addresses across scopes and name reuse, same-type Add/Sub operators and exact-reference removal on all runtime targets

## 2. Standalone module and one state actor

Bead: lander-25h.2

Depends on: group 1.

- [x] 2.1 Add pkgs/actors with the portable root, target-limited runtime, shared version, license and workspace membership; update module/version validation, publication allowlists, packaging inventories, isolated candidate consumers and module guidance; verify mise run validate and the candidate actor consumer checks
- [x] 2.2 Add opaque capacity and count types, enum policies, typed errors and TimeLimit use; verify zero, negative one, one and largest-Int boundaries, constructor privacy and policy tests on all four targets
- [x] 2.3 Implement scope, start, private state, continue/stop, actor references, FIFO send and the thin one-shot ask path needed by the counter; verify the counter, concurrent producers and independent actors on all three runtime targets
- [x] 2.4 Add a minimal runnable README.mbt.md counter and an unpublished acceptance package; compile the example on all runtime targets and verify a wrong-protocol consumer fails compilation
- [x] 2.5 Add scripts/check-actors.mbtx and a mise task using the existing task wrapper; verify nonzero-test checks for root and runtime targets, a deliberate zero-test failure, and mise run check

## 3. Admission, backpressure and cancellation

Bead: lander-25h.3

Depends on: group 2.

- [x] 3.1 Add bounded default capacity 128, explicit unbounded policy and non-waiting admission outcomes; verify full, accepted and closed, including in-flight capacity exclusion and no silent drop
- [x] 3.2 Make admission cancellation-safe and wake blocked producers on close; test both sides of the admission commit point with acknowledgements and verify no stale producer waiter remains
- [x] 3.3 Add queue count and scheduler yielding between bounded batches; verify the count snapshot and progress of another ready actor
- [x] 3.4 Document admission versus processing, ownership of mutable messages and self-send deadlock with runnable examples; run check:actors on all runtime targets

## 4. Receive values, combinators and selective receive

Bead: lander-25h.4

Depends on: group 3.

- [x] 4.1 Add the opaque Receive with receive, select, done, map, zip, zip_with, then and bind on the stack-safe encoding, the ActorContext with own reference, reenqueue and child scope, spawn and join; replace the spike's Inbox; verify finite completion, async work between receives, independent joiners, reenqueue tail order, a full self mailbox, and a compile-failure probe that no public operation takes a message outside a Receive
- [x] 4.2 Add selective receive through select with no uncounted stash; verify oldest match, retained order, arrivals while waiting, selector failure and expiry without removal
- [x] 4.3 Add within, poll, on_closed, recover, receive_loop, receive_all and receive_n, with the loop combinators as one repeat node, and run start through receive_loop; verify time limits, polling on empty and closed mailboxes, recovery without catching cancellation, count limits, state changes and final results through runnable examples that use `<|` for callbacks and method chains for Receive values, on all runtime targets
- [x] 4.4 Add the deterministic test runner for a Receive and a list of messages; verify the README protocol examples with it, document it as the preferred unit-test style, and verify 100,000-step loops of both kinds (state carried forward and result built after the recursive step) on wasm, js and native
- [x] 4.5 Add a moon bench suite for the RECV-1 shapes and a manual mise task for it; verify that mise run check, CI and the release workflow do not run it, record its results in the design, and keep each candidate optimization only when it shows a gain and the stack tests still pass. The pinned compiler rejects async benchmarks in `moon bench` (error 4132), so the suite is the release-mode program `tests/actors-bench` (design TEST-1)
- [x] 4.6 Document the full non-matching bounded mailbox case and recovery choices; verify its timeout acceptance scenarios and run check:actors

## 5. Request/reply and common destinations

Bead: lander-25h.5

Depends on: group 4.

- [x] 5.1 Add Reply, ask and try_ask with a 30-second default, typed finite or indefinite wait policies and one admission-plus-response deadline; verify reply correlation, multiple reply types, duplicate and late replies, timeout while admission is blocked and termination during an indefinite ask
- [x] 5.2 Track pending asks through close, stop, failure and cancellation; verify discarded asks wake promptly, in-flight replies remain possible on close, original causes survive and caller cancellation leaves admitted work intact
- [x] 5.3 Add Subject adapters for references, replies, async queues and custom functions, plus contramap and general destination ask; verify delivery outcomes, no additional queue and custom reply completion
- [x] 5.4 Add runnable protocol and destination examples, wrong-reply compile failures and request-race acceptance tests; verify check:actors on all runtime targets

## 6. Close, drain, child ownership and cleanup

Bead: lander-25h.6

Depends on: group 5.

- [x] 6.1 Complete close with one immutable pending snapshot, drain and cancel; verify in-flight completion versus cancellation, queued-message order, repeated close and wakeup of blocked producers and callers
- [x] 6.2 Complete lifecycle snapshots, initializer readiness, once-only cleanup, cancellation protection and cleanup budgets; verify initializer failure, cleanup timeout and preservation of primary plus cleanup errors
- [x] 6.3 Complete scope failure propagation, context-owned child scopes and closed-scope rejection; verify normal and failed parent exit, sibling cancellation, nested recovery, escaped handles and zero remaining children
- [x] 6.4 Add runnable lifetime and resource examples and document cooperative cancellation limits; run all close, join and cleanup acceptance cases plus check:actors on wasm, js and native

## 7. Serialized services and automatic responders

Bead: lander-25h.7

Depends on: group 6.

- [x] 7.1 Add create and ServiceRef ask/tell over the same runtime; verify serialized async closures, heterogeneous result types, ask failure with later progress, retained prior mutations and tell failure reaching the owner
- [x] 7.2 Add respond and RequestActor without user reply plumbing; verify automatic responses, termination on handler error, release of all pending callers and continued processing after a Result rejection
- [x] 7.3 Add runnable service and responder examples and the shared admission/lifetime cases for both entries; verify the examples and check:actors on all runtime targets

## 8. Names, addresses and algebraic directories

Bead: lander-25h.8

Depends on: group 7.

- [x] 8.1 Add opaque ActorName and typed parse errors in the portable root with runtime re-exports; verify empty, invalid first character, invalid later character, non-ASCII, 1, 128 and 129 character inputs and case-sensitive equality on all four targets
- [x] 8.2 Add per-lifetime ActorAddress and optional scope-named start/spawn; verify address equality, cross-scope uniqueness, duplicate creators running only one initializer, failed startup releasing names after cleanup, closing actors retaining reservations and old refs staying closed after reuse
- [x] 8.3 Add immutable typed Directory empty/of, union, add, remove, difference, membership equality and supported Add/Sub operators; verify identity, associativity, commutativity, idempotence, input preservation, absent removal and exact-address removal with focused property tests on all runtime targets
- [x] 8.4 Add directory name lookup and exact-address resolution; verify duplicate-name behavior, same-address deduplication, removal resolving a name conflict, closed-member retention, explicit refresh after replacement and wrong-protocol compile failures
- [x] 8.5 Add runnable composition, named discovery and name-reuse examples and record the pinned compiler's rejected operator forms; verify composition across scopes does not change actor ownership, removal does not cancel the actor or release its name reservation, old snapshots remain usable after scope exit and check:actors passes on all runtime targets

## 9. Scoped event delivery and integration

Bead: lander-25h.9

Depends on: group 8.

- [x] 9.1 Add Topic, scoped subscriptions, unsubscribe and close; verify subscriber order, snapshot behavior, closed-destination pruning, backpressure, partial delivery and scope cleanup on all runtime targets
- [x] 9.2 Add runnable fan-out and worker-pool examples using subjects and direct send, update the docs index and explain the difference from mediator publish; verify examples compile and docs links pass
- [x] 9.3 Compare acceptance evidence with every row of the design's reference baseline and every actors requirement; verify no required capability is represented only by prose or an unchecked test target
- [ ] 9.4 Generate and review public pkg.generated.mbti files, run mise run format, mise run check and mise exec -- openspec validate --all --strict; verify all pass and isolated candidate consumers use the intended actor archive

## Workflow follow-up

- Beads `lander-25h.1` to `lander-25h.9` follow the group dependencies above.
- Keep beads open until their pull requests merge. Include tests and docs in each group's pull request.
- The final group's pull request archives this change. Close the completed stories and epic with the PR and merge SHA, then sync beads as CONTRIBUTING.md requires.
- Publication needs a later owner-approved release change. Do not publish from the workstation.

# Tasks: Add actor scheduling

Status: approved for implementation on 2026-10-29. Epic `lander-8fh` holds one
story per group. Implementation starts after `add-typed-actors` groups 4 and 6,
as a follow-up goal in the workspace that implements that change.
Each group includes its own tests and runnable documentation.

## 1. Clock boundary and deterministic test clock

Bead: lander-8fh.1

- [ ] 1.1 Spike: prove that a test clock can fire due waits in deadline order and let woken tasks run before the next firing, with the pinned moonbitlang/async on wasm, js and native; record the result in the design and revise CLK-2 before 1.2 if ordering cannot be made deterministic
- [ ] 1.2 Route within, ask deadlines and cleanup budgets through one internal clock with the real clock as default; verify that every add-typed-actors acceptance test still passes on wasm, js and native
- [ ] 1.3 Add TestClock with advance and the clock argument of scope; verify receive time limits and ask deadlines on the test clock, ordered firing with ties in schedule order, and that nothing fires without an advance, also when every task waits
- [ ] 1.4 Add run_script with deliveries and clock advances to the receive test runner; verify a login time-limit example as a unit test with no scope and no real time, and compile the TimeLimit-based test examples in README.mbt.md

## 2. Schedule values

Bead: lander-8fh.2

- [ ] 2.1 Add the opaque Schedule in the portable root with fixed_delay, exponential (doubling up to a maximum), up_to and delays; verify the exponential and limited sequences, a schedule without up_to that keeps repeating, the maximum boundary and constructor privacy on wasm, wasm-gc, js and native
- [ ] 2.2 Document schedules with runnable examples that list their delays; verify the examples compile and run on all four targets

## 3. Scope-owned scheduled and repeated sends

Bead: lander-8fh.3

- [ ] 3.1 Add send_after with Timer and cancel outcomes Stopped and AlreadyFired; verify a send after a delay, cancel before and after admission, scope exit cancellation and closed-scope rejection on the test clock
- [ ] 3.2 Add send_repeated with fixed delay measured from admission; verify count limits, a full mailbox delaying the next send without loss, cancel, scope exit, and a closed target ending the repeated send without a scope failure
- [ ] 3.3 Add runnable examples for session expiry and retries; verify they compile and pass on all runtime targets, and verify no timer task remains after scope exit

## 4. Actor-owned keyed timers

Bead: lander-8fh.4

- [ ] 4.1 Add the internal tagged mailbox entry for keyed timer sends; verify that the add-typed-actors admission, selective-receive and stack tests pass unchanged, and record the local benchmark before and after
- [ ] 4.2 Add Timers[M, K] through the actor context with start_single, start_repeated and cancel, keyed by K : Eq + Hash; verify replacement by key, cancel, that a stale message after replacement or cancel never reaches a receive (also with a waiting select), that send_after messages admitted before cancel stay queued, timers stopping at actor end, and a compile-failure probe for a key of another type
- [ ] 4.3 Add a runnable poller example with keyed timers; verify it on all runtime targets, run check:actors, mise run format, mise run check and mise exec -- openspec validate --all --strict

## Workflow follow-up

- Beads `lander-8fh.1` to `lander-8fh.4` follow the group order above; group 1 depends on `lander-25h.4` and `lander-25h.6`.
- A release follows both changes (`lander-yvv`). It needs a separate owner approval to merge the release PR.
- The last group's pull request archives this change. Close the stories and the epic with the PR and merge SHA, then sync beads, as CONTRIBUTING.md requires.
- Do not publish from a workstation. Releases follow the owner-approved release workflow.

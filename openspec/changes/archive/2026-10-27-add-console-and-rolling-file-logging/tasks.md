# Tasks

The epic is `lander-4us.48`. Each numbered group is one story; its ID is on the
group's `Bead:` line. Each group lands its own tests, compiled
examples, and generated interface updates.

## 1. Prove the native, Node, and Bun path end to end

Bead: lander-4us.48.1

- [x] 1.1 Prove the `logging` plus `logging-hosting-async` split with isolated consumers: portable roots on all four targets, runtime adapters on native/js, logging with no async dependency, and standalone sinks without hosting/config; register the new module, dependency/version validation and tests, and module-layout documentation. Add an unpublished child that writes an event through the existing trait to a console and appended file, then drains before exit; verify Unicode, pipe completion, and errors on native and Node/Bun on Linux, macOS, and Windows.
- [x] 1.2 Prove the console driver's pre-exit callback shape, including native libc exit, first-signal cancellation, and startup failure; verify a final marker is present before each child exits and the existing driver users keep their exit codes.
- [x] 1.3 Prove JS exclusive-create ownership, file size/append/close/delete, stream callbacks, ESM loading, and terminal capability input through the pinned Node adapter build for `pkgs/logging-hosting-async/adapters/node/`; document exact unsupported async APIs and native Auto-color limits, and include only the narrowly evidenced AGENTS.md adapter exception before production sinks depend on it. Record the alternatives and revise the spec first if this module/target split fails the consumer proof.

## 2. Add pure Literate, text, and JSON Lines rendering

Bead: lander-4us.48.2

- [x] 2.1 Add immutable message segments using the existing template parser; verify concatenation equals `message()` for the complete existing template corpus on all four targets, including repeated names and defensive copies, and update the compiled root guide.
- [x] 2.2 Add validated UTC timestamps and pure formatting; test epoch/range boundaries, leap days, milliseconds, text layout, category omission, indented errors, control-character escaping, Literate styles, resets, and plain output snapshots on all four targets; document the fixed layouts and color modes with compiled examples.
- [x] 2.3 Add version-1 JSON Lines rendering with ordered `{name, value}` properties; decode and compare nested values, duplicate names, Unicode, escaped newlines, and error text on all four targets, verify one physical line and no BOM/color, and document the schema and its differences from Serilog JSON.

## 3. Deliver through a bounded console session

Bead: lander-4us.48.3

- [x] 3.1 Add pure typed settings and reports at the `logging-hosting-async` module root and private bounded session state under its native/js runtime package, with one captured timestamp/sequence per event; test every constructor rule on either side of its boundary and verify event/byte budgets include all destination payloads and the in-flight record, with the documented defaults. Construct the log directory from a core absolute path without importing config.
- [x] 3.2 Implement nonblocking newest-drop admission, a single ordered writer, immutable failure reports, observer reentrancy guards, sequence-barrier drain, and idempotent close; use a stalled/failing injected writer to prove bounded memory accounting, visible drops, no recursive failure logging, no log-call raise, and no barrier starvation.
- [x] 3.3 Implement console streams with the proved native/Node adapters; test stderr default, stdout opt-in, independent level filters, forced/plain/Auto colors, `NO_COLOR`, dumb/redirected/unknown terminals, concurrent cooperative producers, and complete Node/Bun pipe output; add a compiled standalone session example and generated interfaces.

## 4. Add rolling text and JSON Lines files

Bead: lander-4us.48.4

- [x] 4.1 Add the pure rolling/retention model and typed stem, policy, byte limit, retained count, period, and sequence; verify daily/size/combined rolls, exact and one-byte-over limits, multibyte UTF-8, oversized whole records, UTC midnight, backward clocks, sequence overflow, restart planning, and unrelated-name exclusion on all four targets; document examples for both formats.
- [x] 4.2 Implement lazy directory/file opening, per-set exclusive ownership, existing-file size/append behavior, successful-action state updates, and normal close; test clean restart, concurrent/stale owners, two isolated formats in one directory, no-event/no-file behavior, permission denial, disk-full and partial-write failures on native, Node, and Bun.
- [x] 4.3 Implement retention only after a replacement opens, using exact parsed owned names and non-link regular files; test keep-newest including active, KeepAll, open failure, deletion failure, and unrelated files/links/directories in temporary directories on Windows, macOS, and Linux; document stale-marker recovery and delivery limits.

## 5. Integrate logging with host shutdown and exit

Bead: lander-4us.48.5

- [x] 5.1 Add a thin opt-in `hosting/logging` bridge over the standalone logging runtime and finalization at the console driver's pre-exit boundary after host reports; compile the usage guide and prove shutdown hooks, stopped callbacks, final reports, configuration/start failure, and skipped hooks on timeout all reach the correct final drain path without changing callers that do not opt in. Keep runtime sink implementation in the lower module.
- [x] 5.2 Bound and protect final drain, preserve primary exit precedence, and map logging-only drain failure to code 1; test normal run, command/usage errors, cancellation, timeout, first SIGINT/SIGTERM and sendable Windows console events using real child processes and existing signal harnesses, including exact final output.
- [x] 5.3 Verify a second signal retains immediate exit without deadlock or a delivery guarantee; document the additional drain-time bound and forced-termination loss, test failed console/file isolation, and verify standalone session cleanup remains usable without the hosting console driver.

## 6. Qualify the complete feature and its consumers

Bead: lander-4us.48.6

- [x] 6.1 Add an application acceptance scenario that fans out to a Literate console and both rolling formats; verify identical captured records, filtering, burst/drop accounting, a small size roll, a fake-clock date roll, retention, restart, and graceful shutdown through the public API on native and Node/Bun.
- [x] 6.2 Extend the existing MoonBit mise checks to reject zero pure/sink acceptance tests, stale adapter output, and runtime parity failures; repeat both isolated consumer dependency checks, run every portable root/formatting/rolling package on all four targets, and verify explicit unsupported-target diagnostics for runtime sink imports. Obtain actual Windows native/Node/Bun and macOS/Linux CI results without replacing runtime proof with a cross-build; keep new modules unpublished.
- [x] 6.3 Run `mise run format`, `mise exec -- openspec validate --all --strict`, and `mise run check`; include generated interfaces and compiled guides, review domain types and I/O boundaries with the repository checklist, and record all remaining limitations before landing.

## Dependencies and PR shape

- Group 1 precedes host adapter work in groups 3 to 5. Group 2 precedes group 3.
- Group 3 and the pure model in group 4 can proceed after their prerequisites;
  the file adapter in group 4 uses group 3's session and reports.
- Group 5 follows groups 1, 3, and 4. Group 6 follows all feature groups.
- A possible review sequence is three PRs: feasibility/rendering, delivery/files,
  and host integration/qualification. Use fewer if each PR stays reviewable.
  All six groups landed in one pull request, organized by these areas.

## Workflow follow-up

- Archive the change in the final implementation PR after all numbered tasks
  are verified. Do not archive the unrelated `add-host-lifecycle` change here.
- After merges, close each group's bead with its PR and merge SHA; close the epic
  only when all stories are closed, then sync the tracker.
- Release preparation and publication require a separate owner request.

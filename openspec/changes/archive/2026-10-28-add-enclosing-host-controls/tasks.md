# Add enclosing-host controls

## 1. Public embedder stop and typed signal read

Bead: lander-dil.1

- [x] 1.1 Add Lifetime::stop_from_embedder, RunOutcome::stop_reason and SignalProbe::read; verify public native/js active-command cancellation, Embedder in hooks and outcome, explicit code and first-reason preservation
- [x] 1.2 Verify exactly-once reverse-order service cleanup and command defers through public APIs; compile the controls on all four targets and update the generated interface and runnable docs

## 2. Console reader ownership and worker acceptance

Bead: lander-dil.2

- [x] 2.1 Add the optional signal reader to native and JS console drivers; verify cancellation and late/finalizer reads use it without installing competing handlers, and unchanged default signal scenarios still pass
- [x] 2.2 Add an unpublished Node parent/worker fixture driven by MoonBit process tasks; verify actual parent SIGINT/SIGTERM publication stops a non-yielding checking worker with true signal reasons and codes 130/143
- [x] 2.3 Verify protected async finalization and draining occur once after cleanup, sticky reads do not escalate, and external listener ownership remains intact; document the enclosing owner's second-signal responsibility in runnable examples
- [x] 2.4 Update public interfaces and isolated consumer fixtures, run formatting, strict OpenSpec validation, focused console checks and mise run check; verify all pass before review and archive

## Workflow follow-up

- Track both groups under one epic before implementation. Keep beads open until merge.
- Archive this change in the final implementation pull request, then close and sync its beads with the PR and merge SHA.
- Publish only in the authorized shared-version release workflow after the independent discovery work is complete.

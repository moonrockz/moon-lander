# Expose portable async composition

## Why

Issue #127 shows that importing the async mediator prevents wasm-gc planning,
even if the application gates every call by target. Sender and basic middleware
only compose async functions. Runtime timeouts and concurrent topics need an
event loop. Embedded dispatch must use the real middleware around the send.

## What Changes

- Expose public typed async sender and before/after/finally composition on all
  four targets without an event-loop dependency in the active package graph.
- Keep timeout and runtime topic operations on their supported targets and
  preserve existing consumers and cancellation behavior.
- Qualify non-suspending embedded sends under `hosting.run_embedded`, and real
  asynchronous native/JS completion, failures and finalization.
- Publish a later verified patch after the running 0.7.1 release.

## Capabilities

### Modified Capabilities
- `mediator-async`: separate portable composition from runtime operations.

## Out of scope

No embedded event loop, fake synchronous dispatch, copied downstream mediator,
unpublished dependency, actor change or weakening of timeout semantics.

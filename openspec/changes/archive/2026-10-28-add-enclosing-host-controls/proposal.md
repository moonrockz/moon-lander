# Add enclosing-host controls

## Why

Morphir's desktop embedder must request shutdown with the actual Embedder reason.
Its CLI evaluator worker must observe the launcher's shared signal reader while
running synchronous code. Published 0.6.0 exposes neither path at the needed boundary.

## What Changes

- Add public `Lifetime::stop_from_embedder(exit_code?)` without exposing arbitrary
  stop reasons or changing the existing requested-stop API.
- Expose the immutable final reason through `RunOutcome::stop_reason()` so a
  public consumer can verify the actual Embedder or Signal result.
- Expose a synchronous read of the existing typed `SignalProbe`.
- Add optional `signals : SignalProbe` to both console drivers. With a supplied
  reader, retain console finalization and exit mapping while the enclosing host
  owns OS listeners and second-signal escalation. With no reader, retain the
  existing installed handlers, listeners and second-signal policy.
- Verify actual parent-to-worker signal delivery, synchronous checks, ordered
  service cleanup and exactly-once finalization through public APIs.

## Capabilities

### New Capabilities

- `enclosing-host-controls`: public embedder stop requests and externally supplied
  console signal readers with explicit ownership, cleanup and exit semantics.

### Modified Capabilities

None. Existing default host and console behavior remains compatible.

## Impact

The hosting lifetime and native/JS console drivers gain additive APIs. Public
interfaces, runnable docs and acceptance fixtures change. No new dependency,
toolchain pin, signal stub or published Node I/O adapter is required. Unpublished
Node worker test fixtures remain outside the published libraries.

Resolves moonrockz/moon-lander#108 and #111 for finos/morphir-moonbit#268.

## Out of scope

Thread-safe calls into the MoonBit runtime, preemption of code that never checks
or yields, a second signal counter inferred from a sticky reader, remoting,
arbitrary stop-reason injection and diagnostic JSON formatting, which has its own
required release change for #112.

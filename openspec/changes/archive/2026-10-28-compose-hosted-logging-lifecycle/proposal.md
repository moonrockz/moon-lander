# Compose hosted logging lifecycle

## Why

Issues #124 and #125 identify two gaps in the published console logging bridge.
An enclosing signal owner cannot supply its probe. A host service cannot close
the actual diagnostic session before a later telemetry stop hook.

## What Changes

- Add optional `signals` to `logging.run` and forward the same probe to the console driver.
- Add `logging.run_with_session`. Its host factory receives the existing opaque
  runtime `Session`, so a diagnostic hosted service can close and drain it.
- Retain unconditional final cleanup, idempotent close and failure reporting.
- Document the accepted-record boundary when a hosted service closes the session.
- Qualify native and JavaScript, including an enclosing parent and a worker
  that polls without yielding. Publish a verified shared patch release.

## Capabilities

### Modified Capabilities

- `logging-sinks`: additive session-aware bridge and enclosing signal composition.

## Out of scope

No downstream workaround, new sink, signal ownership policy, task scheduler,
actor change or logging runtime lifecycle replacement.

# Compose hosted logging lifecycle

## 1. Additive bridge, qualification and patch preparation

Bead: lander-hcs.1

- [x] 1.1 Specify optional probe forwarding, the session-aware entry point and accepted-record boundary; reproduce both missing public APIs
- [x] 1.2 Implement the shared bridge path without changing existing callers or signal ownership; document real hosted close and unconditional cleanup
- [x] 1.3 Verify actual logging drain before telemetry stop, accepted records, repeated close, startup failure, skipped/timed-out hooks and cancellation on native and JavaScript
- [x] 1.4 Verify consuming probes, true StopReason and signal exit precedence through cleanup, including a parent-owned non-yielding JS worker
- [x] 1.5 Qualify the public APIs through isolated registry consumers; prepare shared patch versions, generated interfaces and release notes
- [x] 1.6 Run format, full checks and strict OpenSpec validation; archive this change in its final pull request

Publication remains tracked until the release workflow and independent public
archive checks pass and the Morphir coordinator receives exact proof paths.

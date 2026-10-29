# Expose foreign-safe stop polling

## 1. Shared public stop polling and callback regression

Bead: lander-puj.2

- [x] 1.1 Reproduce the actual JS callback failure and add the public stop_requested methods without changing task-aware checks
- [x] 1.2 Cover real Promise callbacks, same-lifetime application requests, non-yielding signals, first reason, signal exit precedence and task cancellation
- [x] 1.3 Qualify native, non-suspending embedded and isolated candidate consumers; update docs and generated interfaces
- [x] 1.4 Run full checks and strict OpenSpec validation; archive this change in its final pull request

Publication remains tracked by lander-puj.3 through actual approved public archive checksums, fresh consumers and coordinator proof.

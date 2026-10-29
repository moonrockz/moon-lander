# Expose portable async composition

## 1. Portable composition, compatibility and later patch preparation

Bead: lander-puj.1

- [x] 1.1 Reproduce the wasm-gc import planning failure and prove non-suspending public sender/middleware completion under run_embedded on wasm and wasm-gc
- [x] 1.2 Complete the operation-level runtime boundary, preserve existing supported exports and update the public target documentation
- [x] 1.3 Add nonzero four-target acceptance, native/JS real asynchronous success/failure/finalization/cancellation, a genuine JS Promise and timeout compatibility coverage
- [x] 1.4 Verify isolated candidate consumers and the gate reused for public verification, with shared patch versions after 0.7.1 publication; retain actor work and make no downstream edits
- [x] 1.5 Run format, full checks and strict OpenSpec validation; archive this change in its final pull request

Keep publication tracking open through the later release workflow, actual
approved archive checksum matching, fresh public consumers and coordinator proof.

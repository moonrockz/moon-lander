# Tasks

## 1. Repair public download qualification

Bead: `lander-pq1.5`

- [x] 1.1 Add bounded redirect handling for the three public downloads and verify direct success, each supported redirect, missing Location, bad status and a redirect loop with a local HTTP regression.
- [x] 1.2 Match the stock default asset endpoint and SHA256SUM sidecar parser with a focused parser regression, keep the original archive and asset checks, and verify both stock public qualifiers against the original workflow approval map.
- [x] 1.3 Correct the four task descriptions to name eleven libraries without changing task definitions, and update the root README with the published 0.9.0 command verified by the public preflight.
- [x] 1.4 Run format, strict OpenSpec validation, full checks and code review; verify no published package file changed and all eleven local package hashes equal the pre-fix local baseline.

## Workflow follow-up

- Archive this completed tooling change in the reviewed follow-up pull request.
- Before merge and release promotion, verify the Linux CI archive map equals actual artifact 13023517211. macOS and Linux ZIP entry order differs, so a local repack hash is not a replacement for the actual Linux approval.
- After merge, close `lander-pq1.5` with the pull request and merge SHA and sync.
- Keep `lander-pq1.4` open through a fresh workflow-only release run, unchanged approval map, actual GitHub release and independent cold public proof.

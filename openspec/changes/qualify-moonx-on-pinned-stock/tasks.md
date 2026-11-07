# Tasks

## 1. Qualify Moonx on the pinned stock toolchain

Bead: lander-gc9.1

- [x] 1.1 Make `check:moonx` qualify `0.10.20+65efd5b93`, accept only that stock identity in `scripts/check-moonx.mbtx` and `scripts/qualify-moonx-stock.mbtx`, and verify with `mise run test:scripts` (stock identity and stock pin tests).
- [x] 1.2 Remove `check:moonx-stock16`, the task-scoped 0.10.16 and 0.10.17 tools, their CI steps and their uses in `scripts/check.mbtx` and `scripts/check-moonx-release.mbtx`, and verify that `git grep check:moonx-stock16` finds only archived changes.
- [x] 1.3 Regenerate the frozen runtime with `mise run moonx-runtime:generate` and verify with `mise run check:moonx-runtime` and `mise run check:moonx-drift`.
- [ ] 1.4 Run `mise run check:moonx` and `mise run check:moonx-retained` on Linux or macOS, and the Windows CI job, and record the results in the pull request.
- [x] 1.5 Update `pkgs/moonx/GUIDE.md`, `pkgs/moonx/RUNTIME.md`, `README.md` and `CONTRIBUTING.md` for the single stock toolchain, and verify that no current document names stock 0.10.16 for Moonx qualification.

## Workflow follow-up

- Archive the change in the same pull request, then close `lander-gc9.1` and `lander-gc9` after the merge, as "Land a change" in `CONTRIBUTING.md` says.

# Proposal: Qualify Moonx on the pinned stock toolchain

## Why

MoonBit 0.10.20 moves derives to the `#derive(...)` attribute, and its formatter
rewrites every `} derive(...)`. Stock 0.10.16 and 0.10.17 read `#derive` as an
unknown attribute and do not derive the traits, so the formatted
`moonrockz/moon-lander-moonx` source does not compile with them (28 errors with
stock 0.10.17). The old syntax fails `moon check --deny-warn` on 0.10.20. One
source cannot satisfy the current requirement, which names stock 0.10.16 and
0.10.17, and the 0.10.20 toolchain. The owner chose to qualify Moonx on the
pinned stock toolchain (decision of 2026-11-07).

## What Changes

- **BREAKING** Release qualification of the optional Moonx launcher uses the stock
  toolchain of the primary pin (`0.10.20+65efd5b93`) instead of stock
  `0.10.16+b1a0e846e` and `0.10.17+d971670cd`. The next release of
  `moonrockz/moon-lander-moonx` needs MoonBit 0.10.20 or later. Published 0.11.0
  stays available for 0.10.16 and 0.10.17 users.
- The Windows Ctrl-C scenario names the Moonrun of the qualified stock toolchain,
  not the commits `2284bd2` and `3778465`.
- `check:moonx` qualifies the primary pin. `check:moonx-stock16` and the
  task-scoped 0.10.16 and 0.10.17 installations go away, with their CI steps.
- The frozen runtime subset is regenerated with the 0.10.20 formatter. Its
  upstream inputs do not change.

Out of scope:

- The launcher API, the launch plan, cleanup and the frozen upstream inputs.
- A second, older stock toolchain. A later change can add one when a consumer
  needs it.
- The zig-cross sync cross-build plan, which also needed stock 0.10.17. The
  MoonBit 0.10.20 upgrade removes it, and moonx-tools tracks its return.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `moonx-launcher`: the stock qualification requirement, the Windows Ctrl-C
  scenario and the upstream return scenario name the pinned stock toolchain.

## Tracking

- Epic `lander-gc9`, story `lander-gc9.1`.
- Lands with the MoonBit 0.10.20 upgrade pull request.

## Impact

- `.config/mise/config.toml`: `check:moonx` runs on the primary pin; the
  `check:moonx-stock16` task and the task-scoped stock tools go away.
- `scripts/check-moonx.mbtx`, `scripts/qualify-moonx-stock.mbtx`,
  `scripts/check-moonx-release.mbtx`, `scripts/check.mbtx`.
- `.github/workflows/ci.yml` and `release.yml`: one Moonx qualification step for
  each job.
- `pkgs/moonx/runtime/` and its provenance digests; `pkgs/moonx/GUIDE.md`,
  `RUNTIME.md`, `README.md`, `CONTRIBUTING.md`.

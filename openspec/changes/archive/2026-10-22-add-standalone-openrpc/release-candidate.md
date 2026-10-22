# moonrockz/openrpc 0.2.0 release candidate

Prepared on 2026-10-22. This is pre-publication evidence. Nothing has been
uploaded, tagged or released. The owner chose a pipeline release at the shared
version `0.2.0` (tag `v0.1.0` already belongs to the notebooks release).

## Identity

| Item | Value |
| --- | --- |
| Module | `moonrockz/openrpc` |
| Version | `0.2.0`, the shared workspace version (`mise run validate:versions`) |
| Source | commit `ad525049b8a95e9d50a5d6b73bd560c577fec6dc`; the commit that adds this record does not change `pkgs/openrpc` |
| Archive | `moon -C pkgs/openrpc package` → `moonrockz-openrpc-0.2.0.zip` |
| Archive SHA-256 | `25215d9bc7c7a3e5f63fceed9ad219a0ddce4130adea4c4a1526b7c24e397556` |
| Archive size | 160,342 bytes, 80 entries |
| Packaging | Deterministic: the same source gives the same SHA-256 |
| Dependencies | None beyond the MoonBit core library |
| License | `Apache-2.0 AND Unicode-3.0`: `LICENSE`, `OPENRPC-LICENSE.txt` (embedded pinned metaschemas), `UNICODE-LICENSE.txt` (identifier tables) |

API inventory (`pkg.generated.mbti` SHA-256):

| Package | SHA-256 |
| --- | --- |
| `moonrockz/openrpc` | `7b3c6b4cbb9f57263687f36a1ddf333078de2bb0b1839688778982652572c04f` |
| `moonrockz/openrpc/domain` | `34a4896cd0be7daf89c7651fafd106388f3a9a31234bc9d61b7f1512038bae12` |
| `moonrockz/openrpc/json` | `abcf78ee86f5994ee112062853b99a5434dc2ca214ca0b266b6315d3d4aa5e92` |
| `moonrockz/openrpc/reference` | `d724457ca68ae88f843f47ed8bd2d3b13ea361c10d0d8be518eb4922aa4715e8` |
| `moonrockz/openrpc/schema` | `c82b45956d654c7a96b6072f560bfaa21c7a2b2c3739865b412dca9455634589` |

## Evidence

| Command | Result |
| --- | --- |
| `mise run check:openrpc-registry` | Archive audit passed; a consumer outside `moon.work` downloaded the candidate from a loopback registry; its output equals the source build on native, wasm, js and wasm-gc; its resolved graph is exactly `moonrockz/openrpc@0.2.0` |
| `mise run qualify:openrpc` | 34-case frozen corpus: Ajv and the library agree on all four targets |
| `mise run check:openrpc` | Focused suites (190 tests per target) and the source consumer agree on all four targets; dependency deny-list clean |
| `mise run check` | Full workspace gate passed at `ad52504` |
| `mise exec -- openspec validate --all --strict` | Passed |

These are packaged-candidate proofs, not public-registry proof. See
[qualification.md](qualification.md).

## Approval and publication

Publication runs only in `.github/workflows/release.yml`. The owner approves by
merging the release pull request from this branch to `main`. The workflow then:

1. runs `mise run check` and `versions.mbtx check 0.2.0`;
2. packages `moonrockz/openrpc` and records its SHA-256, which must equal
   `25215d9bc7c7a3e5f63fceed9ad219a0ddce4130adea4c4a1526b7c24e397556` for this source;
3. publishes `moonrockz/notebooks@0.2.0` and `moonrockz/openrpc@0.2.0` with the
   `MOONCAKES_USER_TOKEN` organization secret, which this repository can read;
4. runs `mise run check:openrpc-published -- --checksum <that SHA-256>` on all
   four targets from the public registry;
5. creates the GitHub release `v0.2.0` with the CHANGELOG.md section.

Group 11 records the public result from that run.

## Published

The owner approved by merging PR #47 (merge commit
`1de7e46e98d1c7093e14e43ae6317b6320118932`). Release workflow run
[39802962627](https://github.com/moonrockz/moon-lander/actions/runs/39802962627)
passed every job on 2026-10-22:

| Item | Result |
| --- | --- |
| Validate | `mise run check` and `versions.mbtx check 0.2.0` passed at the merge commit |
| Publish | `moonrockz/notebooks@0.2.0` and `moonrockz/openrpc@0.2.0` published |
| Published archive SHA-256 | `8f5c8785377676aefd3e038aed21853e533354f9a378c70306f3efad7238a659`, equal to the archive the workflow built at the merge commit |
| Public consumer | `check:openrpc-published --checksum <that SHA-256>`: a fresh consumer outside `moon.work` resolved `moonrockz/openrpc@0.2.0` from mooncakes.io and matched the source build on native, wasm, js and wasm-gc; graph `openrpc-consumer -> moonrockz/openrpc@0.2.0` only |
| GitHub release | [`v0.2.0`](https://github.com/moonrockz/moon-lander/releases/tag/v0.2.0) at the merge commit |

The published checksum differs from the pre-merge candidate checksum above
(`25215d9b...7556`). `pkgs/openrpc` is identical between the candidate commit
`792017b` and the merge commit; `main` had moved the pinned toolchain from moon
`0.10.15` to `0.10.17`, which packages the same sources into different bytes. The
release gate compares the public archive with the archive built from the released
commit, so the published identity is `8f5c8785...a659` at `1de7e46`.

Merging PR #47 approved the `25215d9b...7556` candidate, not this archive. On
2026-10-22, during review of PR #51, the owner separately approved the published
identity: `moonrockz/openrpc@0.2.0` with archive SHA-256
`8f5c8785377676aefd3e038aed21853e533354f9a378c70306f3efad7238a659`, built from
`1de7e46`. That approval closes tasks 11.1 and 11.2 for the published archive.

## Smithy migration

Smithy PR [#55](https://github.com/moonrockz/smithy/pull/55) moved
`pkgs/smithy-openrpc` onto the published `moonrockz/openrpc@0.2.0`. It imports
the version from mooncakes.io and checks the archive checksum above. It uses no
path override and no `moon.work` member. The owner approved and squash-merged it
on 2026-10-22.

| Item | Value |
| --- | --- |
| Recorded baseline | `c36698b3bd08be62d5d80e93b727ce736388adf6`, squash-merged as `edc6ba3` with an identical tree |
| Branch base | `a9d3525135c0a8043705b8e31dadfcf39e7b4f2d` |
| Source (merged) | `dfcb74e222f3169942f8e4a5e588c12e4a5c1da6` on Smithy `main` |
| Rollback | revert `dfcb74e`; its parent is `5565fb7c5a4b1b21e660f4543ca2c17f1ceb0661` |
| Public API | `pkg.generated.mbti` of `moonrockz/smithy-openrpc` unchanged |
| Parity | 51 captured conversions: identical warnings and errors, documents equal by value |
| Four targets | unit, plugin, isolated consumer and `mise run test:openrpc` passed on native, wasm, wasm-gc and js; the BDD suite passed on native, wasm and js |

Smithy's own record is `docs/migrations/2026-10-22-openrpc-library.md`.

Three things remain open:

- Object members now follow the library's constructor order. The owner approved
  this change; [#57](https://github.com/moonrockz/moon-lander/issues/57) asks the
  library to define that order.
- The library's schema-graph limits cannot be raised by callers
  ([#56](https://github.com/moonrockz/moon-lander/issues/56)). The adapter skips
  `LimitExceeded` findings so that large services still convert.
- Smithy's BDD features, OpenRPC among them, do not run on wasm-gc, and did not
  at the base either. The runner, `moonrockz/moonspec@0.11.0`, has only async
  entry points, and `moonbitlang/async` does not support wasm-gc. On 2026-10-22,
  during review of PR #61, the owner approved narrowing the feature-check
  requirement to native, wasm and js. On wasm-gc, OpenRPC is covered by the unit
  tests, the plugin tests, the isolated consumer and `mise run test:openrpc`. A
  synchronous moonspec runner would bring the features back to wasm-gc.

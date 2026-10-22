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

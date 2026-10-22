# moonrockz/openrpc 0.1.0 release candidate

Prepared on 2026-10-22. This is pre-publication evidence. Nothing has been
uploaded, tagged or released.

## Identity

| Item | Value |
| --- | --- |
| Module | `moonrockz/openrpc` |
| Version | `0.1.0` (the shared workspace version; `mise run validate:versions`) |
| Source | commit `53f5d2209875594ad898c7f9a66b0a5571104768`; `pkgs/openrpc` is unchanged by the commit that adds this record |
| Archive | `_build/publish/moonrockz-openrpc-0.1.0.zip` from `moon -C pkgs/openrpc package` |
| Archive SHA-256 | `f4c5b7ff1d88f85e3cf7ff7897880a7c14157cbade3a146be15011ee0de54887` |
| Archive size | 160,343 bytes, 80 entries |
| Packaging | Deterministic: repackaging the same source gives the same SHA-256 |
| Dependencies | None beyond the MoonBit core library |
| License | `Apache-2.0 AND Unicode-3.0`: `LICENSE`, `OPENRPC-LICENSE.txt` (embedded pinned metaschemas), `UNICODE-LICENSE.txt` (identifier tables) |

## Evidence

| Command | Result |
| --- | --- |
| `mise run check:openrpc-registry` | Archive audit passed; a consumer outside `moon.work` downloaded the candidate from a loopback registry; its output equals the source build on native, wasm, js and wasm-gc; its graph is `openrpc-consumer -> moonrockz/openrpc@0.1.0` only |
| `mise run qualify:openrpc` | 34-case frozen corpus: Ajv and the library agree on all four targets |
| `mise run check:openrpc` | Focused suites (190 tests per target) and the source consumer agree on all four targets; dependency deny-list clean |
| `mise run check` | Full workspace gate passed |
| `mise exec -- openspec validate --all --strict` | Passed |
| `moon -C pkgs/openrpc publish --dry-run` | Not run: it needs the owner's mooncakes.io credentials (`moon login`) |

See [qualification.md](qualification.md) for the qualification record.

## Approval request

Publication needs the owner's explicit approval of this exact candidate:

1. Run `moon login` so `moon -C pkgs/openrpc publish --dry-run` and the upload
   can authenticate.
2. Approve uploading `moonrockz/openrpc@0.1.0` to mooncakes.io from source
   `53f5d22` (or the later commit that only adds records), whose archive
   SHA-256 must equal `f4c5b7ff...4887` immediately before upload.
3. Decide the GitHub release. Tag `v0.1.0` already exists for the notebooks
   release, so either publish to mooncakes.io only, or name a new tag (for
   example `openrpc-v0.1.0`) for a GitHub release.

After an approved upload, `mise run check:openrpc-published` must pass on all
four targets from the public registry, and its archive checksum must match,
before the Smithy migration starts.

# Sigstore test data

`scripts/generate-sigstore-assets.mbtx` checks each file here against `SHA256SUMS`
and writes MoonBit constants from it, because wasm and wasm-gc tests cannot read
files. Do not edit these files. To change one, replace it from its source, update
`SHA256SUMS` and run `mise run build:sigstore-assets`.

| Folder | Source | License |
| --- | --- | --- |
| `public-good/trusted_root.json` | [sigstore/root-signing](https://github.com/sigstore/root-signing) `targets/trusted_root.json` at `c9bda74ad2221f938f7d2e0295ca3aad2da710a8`. It is equal to the first document of `gh attestation trusted-root` on 2026-10-30, which gh gets through TUF | Apache-2.0 |
| `github/` | Attestation bundles from `gh attestation download` (cli/cli) and the GitHub attestations API (finos/morphir-rust), 2026-10-30. `cases.json` gives the artifact digest and identity of each | Public attestations |
| `conformance/` | [sigstore/sigstore-conformance](https://github.com/sigstore/sigstore-conformance) `test/assets/bundle-verify/` at `acb38c9ee4274fa058127e6a5a4cdb9e94e449e1`, all 70 cases | Apache-2.0 (see `conformance/NOTICE`) |
| `wycheproof/` | [C2SP/wycheproof](https://github.com/C2SP/wycheproof) `testvectors_v1` at `d17cc89fa5c8f4f4d378b5385ebf75da5d0926c9`: the ECDSA P-256/SHA-256 and P-384/SHA-384 sets, DER and P1363 | Apache-2.0 (`wycheproof/LICENSE`) |

## gh results for the GitHub bundles

On 2026-10-30, with gh 2.83 and the artifacts from the releases:

| Bundle | Command | Exit |
| --- | --- | --- |
| `morphir-rust-provider-snapshot-0.2.0` | `gh attestation verify <tgz> --bundle <bundle> --repo finos/morphir-rust --signer-workflow finos/morphir-rust/.github/workflows/release-provider-snapshot.yml --deny-self-hosted-runners` | 0 |
| `morphir-rust-provider-snapshot-0.2.0` | the same with `--repo finos/morphir-ui` | 1 |
| `cli-2.50.0` | `gh attestation verify gh_2.50.0_linux_amd64.tar.gz -R cli/cli` | 0 |
| `cli-2.83.0` | `gh attestation verify gh_2.83.0_linux_amd64.tar.gz -R cli/cli` | 0 |

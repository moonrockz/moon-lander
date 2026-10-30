# Tasks: Add Sigstore bundle verification

Status: owner approved for implementation on 2026-10-30, with CRY-1 (reuse mooncrypt),
SCOPE-1 (public repositories first) and MOD-1 (publish as `moonrockz/sigstore`). Epic `lander-1hr` holds one
story for each group. Each group includes its own tests and documentation. Every test
runs on wasm, wasm-gc, js and native.

## 1. Tracer: DSSE signature of a real GitHub bundle

Bead: lander-1hr.1

- [x] 1.1 Spike: import `moonbitstack/mooncrypt@0.4.4` into a new `pkgs/sigstore` module (`moonrockz/sigstore`, in `moon.work`) and verify one P-256 RFC 6979 vector and one SHA-384 FIPS vector on all four targets; if a target fails, record it in design CRY-1 and use the in-house fallback before 1.2
- [x] 1.2 Add `scripts/generate-sigstore-assets.mbtx` with `mise run build:sigstore-assets` and `check:sigstore-assets` tasks; it writes test-only `.mbt` constants from `pkgs/sigstore/testdata/`; verify that `--check` fails on a changed fixture and that `mise run test:scripts` covers it
- [x] 1.3 Parse the morphir-rust `provider-snapshot/v0.2.0` bundle far enough to get the DSSE envelope and the leaf SPKI, verify the PAE signature and match the artifact digest to the third subject; verify a pass, and a fail after one payload byte changes, on all four targets

## 2. Signature primitives and the Wycheproof gate

Bead: lander-1hr.2

- [x] 2.1 Add `internal/signature`: strict DER ECDSA signatures, SPKI keys for P-256 and P-384 with range and on-curve checks, hash selection from the key, and the P-384/SHA-256 second try; verify each DER rule (length, leading zeros, trailing bytes, negative values) with values on each side of the rule
- [x] 2.2 Vendor the Wycheproof `ecdsa_secp256r1_sha256` and `ecdsa_secp384r1_sha384` DER and P1363 sets with their license and source commit; verify that every case gives its expected result on all four targets
- [x] 2.3 Add a manual `bench:sigstore` task for one bundle verify in release mode; verify that `check`, CI and the release workflow do not run it

## 3. Certificates and the trusted root

Bead: lander-1hr.3

- [x] 3.1 Add `internal/der` and `internal/x509`: TBS bytes, validity, SPKI, basic constraints, key usage, EKU, SAN, key IDs, Fulcio extensions `.1.1` to `.1.22`, the SCT list and critical-extension handling; verify against the real leaf and the public-good chain, and against malformed DER cases
- [x] 3.2 Add `TrustedRoot::parse` with typed errors for each rule of the `sigstore-trusted-root` spec, and keep unsupported keys such as Ed25519; verify every scenario of that spec
- [x] 3.3 Generate `public_good.generated.mbt` from root-signing `c9bda74` and add `TrustedRoot::public_good`; verify the SHA-256 digest `6494e21e…0b66` in a test and the generator `--check`
- [x] 3.4 Add the path check at a given time: CA `validFor`, certificate validity with inclusive bounds, CA basic constraints and path length, leaf EKU code signing; verify the scenarios of "Verify the certificate chain"

## 4. Transparency log and SCT

Bead: lander-1hr.4

- [x] 4.1 Add `internal/tlog`: SET payload and signature, log lookup by key ID, log validity, "now" bound; verify the SET of the three real bundles, a changed SET and a future integrated time
- [x] 4.2 Add the RFC 6962 inclusion proof and the signed checkpoint, using the proof log index; verify the sharded morphir-rust entry, a changed proof hash, a wrong hash count and a checkpoint signed by another key
- [x] 4.3 Add the log body check for `dsse/0.0.1` and `hashedrekord/0.0.1`, and not-supported reasons for other kinds; verify each scenario of "Verify the transparency log entry"
- [x] 4.4 Add `internal/sct` with the precertificate TBS rewrite; verify the SCT of the three real leaves, an unknown CT log and a changed SCT signature

## 5. Identity policy, verdict and the conformance suite

Bead: lander-1hr.5

- [x] 5.1 Add the typed identity values and `Policy` with signer workflow, exact SAN, GitHub claims and hosted-runner-only; verify each scenario of the `sigstore-identity-policy` spec and each parse rule on each side of its limit
- [x] 5.2 Add `verify`, `Verdict`, `Rejection`, `Feature` and `Failure`, and the bundle parse rules of the spec (media types, unknown fields, base64 forms, integer forms, limits, message signatures); verify the scenarios of the `sigstore-bundle-verification` spec
- [x] 5.3 Vendor the Rekor v1 conformance subset from sigstore-conformance `acb38c9` with its license; verify that each case gives its expected verdict, and that a sample of `rekor2-*`, `managed-key-*` and TSA cases gives a not-supported reason
- [x] 5.4 Add the cli/cli `v2.50.0` and `v2.83.0` and morphir-rust bundles as pass fixtures, with one mutation case for each pipeline step; verify that the verdicts agree with `gh attestation verify` as recorded in `testdata/README.md`
- [x] 5.5 Write `pkgs/sigstore/README.mbt.md` with a runnable example of install-time verification and of offline re-verification from a stored bundle; add `check:sigstore`, which fails when a target runs zero sigstore tests; verify both in `mise run check`

## 6. Publication

Bead: lander-1hr.6

- [x] 6.1 Add `moonrockz/sigstore` to `scripts/publish.mbtx` after `moonrockz/openrpc`, to the release package and registry-consumer gates, and to the README layout list and `CHANGELOG.md`; verify `mise run validate:publication` and `mise run check:framework-registry`
- [x] 6.2 Run `mise run format`, `mise run check` and `mise exec -- openspec validate --all --strict`; verify that each passes

## Workflow follow-up

- The pull request that lands group 6 archives the change with
  `mise exec -- openspec archive add-sigstore-verification --yes`.
- After each merge, close its bead with the pull request and merge SHA, close epic
  `lander-1hr` after the last story, and run `bd dolt pull` and `bd dolt push`.
- The first release with this module needs owner approval, as every release does.

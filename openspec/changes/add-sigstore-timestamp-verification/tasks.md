# Tasks: Add Sigstore timestamp verification

Status: owner approved for implementation on 2026-10-31, with TIME-2 (every time source
must verify), ROOT-1 (the SCT rule follows the issuing root) and LOG-2 (intoto entries). Epic `lander-19l` holds one
story for each group. Each group includes its own tests and documentation. Every test
runs on wasm, wasm-gc, js and native, and `mise run test:native-zig` passes too.

## 1. Tracer: GitHub root and the release timestamp signature

Bead: lander-19l.1

- [ ] 1.1 Add GitHub's TUF target `trusted_root.json` (SHA-256 `484cdfe1…fbb7`) to `testdata/github-root/`, `SHA256SUMS` and the generator, and add `TrustedRoot::github()`; verify the digest test, the summary (six CAs, six TSAs, no logs) and `mise run check:sigstore-assets`
- [ ] 1.2 Read GeneralizedTime with a fraction in `internal/der`; verify canonical fractions pass and trailing zeros, a bare `.`, offsets and more than nine digits fail
- [ ] 1.3 Add `internal/timestamp`: TimeStampResp status, SignedData with one signer, id-ct-TSTInfo, TSTInfo fields and signed attributes; verify the cli/cli `v2.103.3` token gives genTime `2026-10-26T19:20:09Z`, a SHA-256 imprint and a signature that verifies with GitHub TSA 5, and that status 1, a changed TSTInfo and a changed signature fail

## 2. Timestamp trust, time sources and the SCT rule

Bead: lander-19l.2

- [ ] 2.1 Check the TSA chain at genTime (trusted leaf equals signer, embedded certificates only as intermediates, critical EKU of exactly timeStamping, key usage, authority validity), the imprint over the signature bytes, and genTime not after "now"; verify each scenario of `sigstore-signed-timestamps` and the timestamp-authority `response-injected-certs.tsr` case
- [ ] 2.2 Combine time sources in `verify` (TIME-2) and replace the log fields of `VerifiedBundle` with `times`; verify the private-repository provenance bundle from cli/cli test data, a bundle with no time source, a leaf expired at the timestamp time, and that the 0.10.0 GitHub fixtures still pass
- [ ] 2.3 Add `TrustedRoot::combine` and `TrustedRoot::github_attestations()` with the SCT rule of each source root; verify both scenarios of "Combine trusted roots" and the "GitHub instance leaf" scenario

## 3. Release-attestation policy

Bead: lander-19l.3

- [ ] 3.1 Make the policy issuer optional inside `Policy`, and add `PredicateType::github_release_v0_2()`, `Policy::github_release(repository, tag~)` with `.repository_id` and `.owner_id`, and `PolicyMismatch::ReleaseMismatch`; verify each scenario of "Match a GitHub release attestation" and "Release certificate without issuer"
- [ ] 3.2 Add the cli/cli `v2.103.3` release attestation and the MIT cli/cli release v0.1 bundle with their asset digests and license notice; verify a pass for each, and one mutation for each release rule

## 4. Rekor v1 in-toto entries

Bead: lander-19l.4

- [ ] 4.1 Verify `intoto/0.0.2` bodies; update the pinned conformance outcomes so the `intoto-*` cases pass or fail with their real reason, and verify both scenarios of "Verify in-toto log entries"

## 5. Strictness fixes, documentation and landing

Bead: lander-19l.5

- [ ] 5.1 Refuse an empty SCT list and check the PrintableString and IA5String character sets; verify each rule on each side of its limit
- [ ] 5.2 Update `pkgs/sigstore/README.mbt.md` (timestamps, the GitHub roots, the release policy, a runnable release example) and the `CHANGELOG.md` Unreleased section with the breaking changes; verify the README examples run on four targets
- [ ] 5.3 Run `mise run format`, `mise run check`, `mise run test:native-zig` and `mise exec -- openspec validate --all --strict`; verify that each passes

## Workflow follow-up

- The pull request that lands group 5 archives the change.
- After the merge, close each bead with the pull request and merge SHA, close epic
  `lander-19l`, and run `bd dolt pull` and `bd dolt push`.
- A release that carries this change needs owner approval.

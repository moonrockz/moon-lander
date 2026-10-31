# Proposal

## Why

The MoonBit Morphir CLI (finos/morphir-moonbit, `apps/morphir`) will install
extensions from GitHub releases. Publishers sign each release in GitHub Actions
with artifact attestations (`actions/attest@v4`). These are Sigstore bundles. The
CLI must verify a bundle against a pinned publisher identity at install time, on
native, on js (browser and Node.js) and on wasm-gc. No MoonBit Sigstore verifier
exists, so Moon-Lander will supply one.

## What Changes

- Add the module `moonrockz/sigstore` in `pkgs/sigstore/`. It verifies Sigstore
  bundles (media types v0.1, v0.2 and v0.3) that contain a DSSE envelope with an
  in-toto statement, a Fulcio certificate and a Rekor v1 transparency-log entry.
- The verification core is pure. It takes bytes and values in: the artifact
  digest, the bundle JSON, the trusted root JSON, a policy and the time "now". It
  returns a structured verdict. A failed verdict gives one typed reason. The core
  does no network, filesystem or clock I/O.
- A policy pins the publisher identity: the OIDC issuer, the certificate SAN or
  signer-workflow URI, the source repository, the source ref and the runner
  environment. A policy can refuse self-hosted runners.
- The trusted root is an input. The module embeds a pinned copy of the Sigstore
  public-good `trusted_root.json` as a constant that a consumer can use.
- It also verifies `messageSignature` bundles with `hashedrekord` entries, because
  most Sigstore conformance cases use them.
- All cryptography is pure MoonBit, with no host crypto, so the same code runs on every
  target. SHA-2 and ECDSA (P-256, P-384) come from `moonbitstack/mooncrypt` at an
  exact version, behind our own wrapper and a Wycheproof test gate. A strict DER reader,
  the Fulcio X.509 subset, the SCT check and RFC 6962 proofs are new internal packages.
- Tests use vendored Sigstore conformance cases and real GitHub attestation bundles
  (cli/cli releases and finos/morphir-rust `provider-snapshot/v0.2.0`), on wasm,
  wasm-gc, js and native.
- Add `moonrockz/sigstore` to the publication allowlist as the twelfth library, after the optional `moonrockz/moon-lander-moonx` that landed first.

Out of scope:

- Signing, key generation and OIDC token flows.
- A Sigstore TUF client that refreshes the trusted root. That is a later change.
- A GitHub HTTP client, attestation download and the Morphir trust store or lock.
- Rekor v2 (rekor-tiles) entries, RFC 3161 timestamp verification, GitHub's private
  Sigstore instance, and managed-key (public key) bundles. So attestations from
  private repositories and GitHub immutable-release attestations are not supported
  yet. The verifier refuses each with a typed reason, so a caller can tell "not
  supported" from "invalid".
- Policy matching on in-toto predicate content beyond the predicate type.

## Capabilities

### New Capabilities

- `sigstore-bundle-verification`: verify a Sigstore bundle against an artifact
  digest, a trusted root and a time, and return a typed verdict.
- `sigstore-trusted-root`: parse a Sigstore trusted root and give the pinned
  public-good root.
- `sigstore-identity-policy`: express and match the publisher identity that a
  verified certificate must have.

### Modified Capabilities

- `framework-publication`: the release publishes twelve libraries, with
  `moonrockz/sigstore` after `moonrockz/openrpc`.

## Tracking

Beads epic and stories are on the `Bead:` lines of `tasks.md`.

## Impact

- New module `pkgs/sigstore` in `moon.work`, with internal packages for DER, X.509,
  signatures, the SCT and the transparency log. It imports `moonbitlang/core` and
  `moonbitstack/mooncrypt` (Apache-2.0) at an exact version.
- A moonx script generates the pinned root and the test fixtures as MoonBit source,
  with a `--check` mode in `mise run check`.
- `scripts/publish.mbtx`, the release package and registry-consumer gates, and
  the README layout list add the module.
- Test fixtures under `pkgs/sigstore/testdata/` (Apache-2.0 conformance files keep
  their license notice).
- finos/morphir-moonbit consumes the module after its first release.

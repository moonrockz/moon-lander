# Proposal

## Why

`moonrockz/sigstore` 0.10.0 verifies only bundles whose time comes from a Rekor v1
signed entry timestamp. GitHub signs two kinds of attestation another way: those from
private repositories, and the release attestations of immutable releases. Both use
GitHub's own Sigstore instance, have no transparency-log entry and no SCT, and take
their only time from an RFC 3161 timestamp of `timestamp.githubapp.com`. The Morphir
CLI must verify extensions from private publishers and immutable releases too, so the
verifier must read these timestamps, trust GitHub's instance, and match release
attestations.

## What Changes

- Verify RFC 3161 timestamps in `timestampVerificationData`: the TimeStampResp, the
  CMS SignedData signature with its signed attributes, the TSA certificate chain from
  the trusted root at the timestamp time, and the message imprint over the bundle
  signature. A verified timestamp is a time source like a signed entry timestamp.
- Combine time sources: a bundle needs at least one verified time, every timestamp and
  every log entry it holds must verify, and the leaf must be valid at every verified
  time. Bundles with no log entry and a valid timestamp now verify.
- Require an SCT only when the trusted root that issued the leaf lists CT logs, so
  GitHub-instance leaves (which have no SCT) verify and public-good leaves still need one.
- Give GitHub's trusted root as a pinned value (`TrustedRoot::github()`), and a
  combined root of public good and GitHub (`TrustedRoot::github_attestations()`) that
  keeps the SCT rule of each source root. `TrustedRoot::combine` makes such a root
  from any parsed roots.
- Add a policy for GitHub release attestations (`Policy::github_release`): the SAN
  `https://dotcom.releases.github.com`, no OIDC issuer, the release predicate type,
  and the repository, tag and purl of the predicate, with optional repository and
  owner IDs.
- Verify Rekor v1 `intoto/0.0.2` entries, so the sigstore-conformance cases that pair
  a Rekor v1 entry with an RFC 3161 timestamp run.
- Refuse an empty SCT list, and check the character sets of PrintableString and
  IA5String.
- **BREAKING** (pre-1.0 minor): `Failure` gains timestamp cases, `PolicyMismatch`
  gains a release mismatch case, and `Feature::TimestampAuthority` is removed, since
  timestamp-only bundles now verify. A caller that matches every case adds arms.
  `VerifiedBundle` replaces `log_id`, `log_index` and `integrated_time` with
  `times`, a list of verified times and their sources, because a bundle can now
  have no log entry.

Out of scope:

- Rekor v2 entries, Ed25519 log keys and C2SP checkpoints (a later change; it builds on
  this one).
- A TUF client that refreshes either trusted root, and GitHub data-residency
  (`<domain>.releases.github.com`) roots.
- `gh release verify` of the tag commit, whose digest is SHA-1 (or a gitoid);
  release verification covers release assets (SHA-256) only.
- Managed-key bundles, CRL and OCSP checks, and TSA signatures other than ECDSA.

## Capabilities

### New Capabilities

- `sigstore-signed-timestamps`: verify RFC 3161 timestamps of a bundle and combine
  them with log entry times.

### Modified Capabilities

- `sigstore-bundle-verification`: log entries become one time source among two; the
  SCT is required only for roots with CT logs; `intoto/0.0.2` entries verify.
- `sigstore-trusted-root`: the pinned GitHub root and combined roots.
- `sigstore-identity-policy`: the release-attestation policy, which requires no OIDC
  issuer.

## Tracking

Beads epic and stories are on the `Bead:` lines of `tasks.md`.

## Impact

- `pkgs/sigstore`: a new internal `timestamp` package (CMS SignedData and TSTInfo over
  the existing DER reader), changes to `verify.mbt`, `trusted_root.mbt`, `policy.mbt`,
  `bundle.mbt`, and `internal/der` (GeneralizedTime fractions, string character sets).
  New public API is additive; `Policy` issuer matching and the SCT rule change
  behavior only for bundles that 0.10.0 refused.
- Test data: the pinned GitHub root, the cli/cli `v2.103.3` release attestation, and
  the MIT-licensed cli/cli test bundles (GitHub release v0.1, a private-repo SLSA
  provenance bundle and its artifact digest).
- No new dependency. A release follows only with owner approval.

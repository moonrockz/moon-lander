# sigstore-trusted-root Specification

## Purpose
Give the Sigstore verifier the keys and certificates it trusts as one parsed,
immutable value, from a caller's `trusted_root.json` or from a pinned public-good copy.

## Requirements

### Requirement: Parse a trusted root

The library SHALL parse a Sigstore trusted root document with media type
`application/vnd.dev.sigstore.trustedroot+json;version=0.1` into an immutable
value. The value SHALL hold the transparency logs, certificate authorities,
certificate-transparency logs and timestamp authorities, each with its key or
certificate chain and its validity period.

#### Scenario: Public-good root

- **WHEN** a caller parses the pinned public-good `trusted_root.json`
- **THEN** the value has two transparency logs, two Fulcio certificate authorities, two certificate-transparency logs and one timestamp authority

#### Scenario: GitHub root

- **WHEN** a caller parses the first document that `gh attestation trusted-root` prints
- **THEN** the parse succeeds and gives the same value as the pinned public-good root

### Requirement: Reject a malformed trusted root

A trusted root parse SHALL fail with a typed error that names the field and the
rule it breaks when the media type is unknown, a required field is missing, a key or
certificate does not decode, or a transparency log has no validity start.

#### Scenario: Unknown media type

- **WHEN** the media type is `application/vnd.dev.sigstore.trustedroot+json;version=9.9`
- **THEN** the parse fails with an unsupported media type error

#### Scenario: Log without validity start

- **WHEN** a transparency log entry has a public key with no `validFor.start`
- **THEN** the parse fails with an error that names that log

#### Scenario: Bad certificate bytes

- **WHEN** a certificate authority chain holds bytes that are not a DER certificate
- **THEN** the parse fails with an error that names that certificate authority

### Requirement: Keep unsupported trust material

A trusted root parse SHALL accept a key type that the verifier cannot use, such as an
Ed25519 log key. The verifier SHALL then not use that entry, and an entry from that
log SHALL fail with an unsupported-key reason.

#### Scenario: Ed25519 log in the public-good root

- **WHEN** the public-good root lists the `log2025-1.rekor.sigstore.dev` log with an Ed25519 key
- **THEN** the parse succeeds and that log is marked as not usable for verification

### Requirement: Give the pinned public-good root

The library SHALL give the Sigstore public-good trusted root as a value that needs no
I/O. The embedded document SHALL be byte-equal to a named source revision, and a test
SHALL check its SHA-256 digest.

#### Scenario: Pinned digest

- **WHEN** the test computes the SHA-256 digest of the embedded document
- **THEN** it equals the digest that the module documentation gives with the source revision

### Requirement: Give the pinned GitHub root

The library SHALL give GitHub's Sigstore trusted root as a value that needs no I/O.
The embedded document SHALL be byte-equal to the `trusted_root.json` target of
`https://tuf-repo.github.com` with SHA-256
`484cdfe1a7c65479c5ba2a22193d1be90f0020db1997de696ab207434c62fbb7`, and a test SHALL
check that digest.

#### Scenario: GitHub root content

- **WHEN** a caller reads the summary of the pinned GitHub root
- **THEN** it has six certificate authorities and six timestamp authorities, and no transparency or CT log

### Requirement: Combine trusted roots

The library SHALL combine several trusted roots into one value that trusts the logs
and authorities of each. Each certificate authority SHALL keep the rule of its own
root: an SCT is required only when that root lists CT logs.

#### Scenario: GitHub attestations root

- **WHEN** a caller verifies a public-good bundle and a GitHub-instance bundle with `TrustedRoot::github_attestations()`
- **THEN** both verdicts pass, the public-good leaf needs its SCT and the GitHub leaf needs none

#### Scenario: Public-good leaf without SCT

- **WHEN** the SCT extension is removed from a public-good leaf and the bundle is verified with the combined root
- **THEN** the verdict fails, because the public-good root lists CT logs

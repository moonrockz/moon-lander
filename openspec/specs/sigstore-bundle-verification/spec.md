# sigstore-bundle-verification Specification

## Purpose
Verify a Sigstore bundle offline, as a pure function of an artifact digest, the
bundle, a trusted root, identity policies and a time, and return a typed verdict.

## Requirements

### Requirement: Pure verification

Verification SHALL be a function of five inputs: an artifact digest, a parsed bundle,
a parsed trusted root, one or more identity policies, and the time "now". It MUST NOT
read a clock, the network, the filesystem or the environment. The same inputs SHALL
give the same verdict on the wasm, wasm-gc, js and native targets.

#### Scenario: Same verdict on each target

- **WHEN** the test suite verifies each vendored fixture on wasm, wasm-gc, js and native
- **THEN** each target gives the same verdict and the same reason for each fixture

#### Scenario: Offline after install

- **WHEN** a caller verifies a stored bundle again with a later "now" and no network
- **THEN** the verdict is the same as at install time

### Requirement: Typed verdict

A verdict SHALL either pass with the verified facts, or fail with one typed reason.
A passed verdict SHALL give the in-toto statement (when present), the matched policy,
the certificate identity claims, the log ID, log index and integrated time.
A failed reason SHALL name the check that failed and SHALL tell "invalid" apart
from "not supported".

#### Scenario: Pass

- **WHEN** a caller verifies the finos/morphir-rust `provider-snapshot/v0.2.0` bundle with the digest `sha256:03d190b8ef97d354f9aca6854542979c36ce5f77c68a3d80de28ac1a77c432bd`, the public-good root and a policy for that repository
- **THEN** the verdict passes with predicate type `https://slsa.dev/provenance/v1`, integrated time `1792133282` and SAN `https://github.com/finos/morphir-rust/.github/workflows/release-provider-snapshot.yml@refs/tags/provider-snapshot/v0.2.0`

#### Scenario: Not supported

- **WHEN** the bundle has only a Rekor v2 entry and an RFC 3161 timestamp
- **THEN** the verdict fails with a not-supported reason, not with an invalid reason

### Requirement: Parse a bundle

The library SHALL parse a bundle with media type v0.1, v0.2 or v0.3, in both the
`bundle+json;version=X` and `bundle.vX+json` forms. It SHALL apply the protobuf JSON
rules of sigstore-go: unknown fields fail, bytes are base64, and 64-bit integers are
strings or numbers. A parse failure SHALL be a typed error that names the field.

#### Scenario: Each media type

- **WHEN** a caller parses the conformance bundles `happy-path-v0.1`, `happy-path-v0.2`, `happy-path-v0.3` and `happy-path-v0.3-new-mediaType`
- **THEN** each parse succeeds

#### Scenario: Unknown media type

- **WHEN** the media type is `application/vnd.dev.sigstore.bundle.v0.4+json`
- **THEN** the parse fails with an unsupported media type error

#### Scenario: Unknown field

- **WHEN** a bundle has a field `verificationMaterial.extra`
- **THEN** the parse fails with an error that names `verificationMaterial.extra`

### Requirement: Match the artifact digest

The verifier SHALL require the SHA-256 artifact digest to equal the digest of one
in-toto subject of a DSSE bundle, or the message digest of a message-signature bundle.
Hex digests SHALL compare without regard to letter case.

#### Scenario: Subject in a multi-subject statement

- **WHEN** the digest is the third subject of a four-subject statement
- **THEN** the digest check passes

#### Scenario: Other artifact

- **WHEN** the digest is not in any subject
- **THEN** the verdict fails with an artifact digest mismatch reason

### Requirement: Verify the content signature

For a DSSE bundle, the verifier SHALL require payload type
`application/vnd.in-toto+json`, exactly one signature, and a valid signature by the
leaf certificate key over the DSSE pre-authentication encoding. For a message-signature
bundle, it SHALL verify the signature over the artifact digest.

#### Scenario: Changed payload

- **WHEN** one byte of the DSSE payload of a logged bundle changes
- **THEN** the verdict fails with a transparency log body reason, because the logged payload hash no longer matches

#### Scenario: Signature that does not verify

- **WHEN** the log body matches the bundle but the content signature does not verify with the leaf key
- **THEN** the verdict fails with a content signature reason

#### Scenario: Two signatures

- **WHEN** a DSSE envelope has two signatures
- **THEN** the verdict fails with a bundle shape reason

### Requirement: Verify the certificate chain

The verifier SHALL build a path from the leaf certificate to the root of a Fulcio
certificate authority in the trusted root. At each verified time, each certificate
SHALL be valid, the authority's validity period SHALL contain that time, and the leaf
SHALL have the code signing extended key usage. The leaf issuer MAY be any certificate
of the authority chain.

#### Scenario: Untrusted root

- **WHEN** the leaf chains to a certificate authority that the trusted root does not list
- **THEN** the verdict fails with a certificate chain reason

#### Scenario: Leaf expired at log time

- **WHEN** the integrated time is after the leaf's not-after time
- **THEN** the verdict fails with a certificate validity reason

#### Scenario: Leaf issued by a middle certificate

- **WHEN** the GitHub release leaf is issued by `Fulcio Intermediate l1`, the second certificate of a GitHub authority chain
- **THEN** the path leaf, `Fulcio Intermediate l1`, `Internal Services Root` verifies

### Requirement: Verify the signed certificate timestamp

When the trusted root that holds the leaf's certificate authority lists CT logs, the
verifier SHALL require one embedded signed certificate timestamp in the leaf from one
of those logs, with a valid signature over the precertificate. An empty SCT list SHALL
fail. A root without CT logs SHALL NOT require an SCT.

#### Scenario: Unknown CT log

- **WHEN** the leaf's timestamp names a CT log key that the trusted root does not list
- **THEN** the verdict fails with a certificate timestamp reason

#### Scenario: GitHub instance leaf

- **WHEN** a leaf of GitHub's instance, which has no SCT, verifies with the GitHub root, which has no CT logs
- **THEN** the SCT check passes

#### Scenario: Empty SCT list

- **WHEN** the leaf's SCT extension holds a list with no entry
- **THEN** the verdict fails with a certificate timestamp reason

### Requirement: Verify the transparency log entry

The verifier SHALL check each Rekor v1 entry of the bundle: it is from a log in the
trusted root, with a valid signed entry timestamp, an integrated time inside the log's
validity and not after "now", and a body whose kind, signature, certificate and payload
hash match the bundle. A bundle MAY have no entry when a timestamp gives its time and
no root of an authority that issued the leaf lists transparency logs; when one does, an
entry from one of that root's logs SHALL verify.

#### Scenario: Bad signed entry timestamp

- **WHEN** the signed entry timestamp signature does not verify
- **THEN** the verdict fails with a transparency log reason

#### Scenario: Integrated time in the future

- **WHEN** the integrated time is later than "now"
- **THEN** the verdict fails with a transparency log time reason

#### Scenario: Body for another signature

- **WHEN** the entry body holds a signature that differs from the bundle signature
- **THEN** the verdict fails with a transparency log body reason

#### Scenario: Public-good leaf with only a timestamp

- **WHEN** the log entry is removed from a bundle whose leaf chains to an authority of a root that lists transparency logs, and a valid timestamp remains
- **THEN** the verdict fails with a transparency log reason

### Requirement: Verify inclusion in the log

For bundle v0.2 and later, the verifier SHALL require an RFC 6962 inclusion proof
whose root hash equals the root hash of a checkpoint that the log key signed. A
v0.1 bundle without a proof SHALL pass on its signed entry timestamp alone.

#### Scenario: Corrupted proof hash

- **WHEN** one hash of the inclusion proof changes
- **THEN** the verdict fails with an inclusion proof reason

#### Scenario: Checkpoint signed by another key

- **WHEN** the checkpoint signature does not verify with the log key
- **THEN** the verdict fails with a checkpoint reason

#### Scenario: Real sharded log entry

- **WHEN** the entry log index differs from the inclusion proof log index, as in the morphir-rust bundle
- **THEN** the proof is checked with the inclusion proof log index and the verdict passes

### Requirement: Verify in-toto log entries

The verifier SHALL accept Rekor v1 entries of kind `intoto` version `0.0.2` for DSSE
bundles. The body's envelope signature SHALL equal the bundle signature, its verifier
certificate SHALL equal the leaf, and its payload hash SHALL equal the SHA-256 of the
payload.

#### Scenario: Conformance in-toto bundle with a timestamp

- **WHEN** the verifier checks the sigstore-conformance case `intoto-with-custom-trust-root`
- **THEN** the verdict passes

#### Scenario: Timestamp outside the leaf validity

- **WHEN** the verifier checks the case `intoto-tsa-timestamp-outside-cert-validity_fail`
- **THEN** the verdict fails with a certificate validity reason

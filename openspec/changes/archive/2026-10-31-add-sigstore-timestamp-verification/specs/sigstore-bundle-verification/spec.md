# Spec Delta

## MODIFIED Requirements

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
hash match the bundle. A bundle MAY have no entry when a timestamp gives its time.

#### Scenario: Bad signed entry timestamp

- **WHEN** the signed entry timestamp signature does not verify
- **THEN** the verdict fails with a transparency log reason

#### Scenario: Integrated time in the future

- **WHEN** the integrated time is later than "now"
- **THEN** the verdict fails with a transparency log time reason

#### Scenario: Body for another signature

- **WHEN** the entry body holds a signature that differs from the bundle signature
- **THEN** the verdict fails with a transparency log body reason

## ADDED Requirements

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

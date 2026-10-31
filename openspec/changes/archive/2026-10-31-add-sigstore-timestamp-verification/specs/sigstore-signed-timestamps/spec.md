# Spec Delta

## Purpose

Verify the RFC 3161 timestamps of a Sigstore bundle against the timestamp authorities
of the trusted root, and combine them with transparency log times into the set of
verified times.

## ADDED Requirements

### Requirement: Read an RFC 3161 timestamp

The verifier SHALL read each `rfc3161Timestamps[].signedTimestamp` as a DER
TimeStampResp with status granted, holding a CMS SignedData with exactly one signer and
an id-ct-TSTInfo content. Any other form SHALL fail with a timestamp reason.

#### Scenario: GitHub release timestamp

- **WHEN** the verifier reads the timestamp of the cli/cli `v2.103.3` release attestation
- **THEN** its time is `2026-10-26T19:20:09Z`, its imprint is SHA-256 and its signer is a `timestamp.githubapp.com` authority

#### Scenario: Status other than granted

- **WHEN** a TimeStampResp has status 1 (granted with modifications)
- **THEN** the verdict fails with a timestamp reason

### Requirement: Verify the timestamp signature

The verifier SHALL require signed attributes with the content type id-ct-TSTInfo, a
message digest equal to the hash of the TSTInfo, and, when present, a signing
certificate V2 hash equal to the SHA-256 of the signer certificate. The signature over
the DER SET of the signed attributes SHALL verify with the signer key.

#### Scenario: Changed TSTInfo

- **WHEN** one byte of the TSTInfo changes
- **THEN** the verdict fails with a timestamp reason

#### Scenario: Changed signature

- **WHEN** one byte of the SignerInfo signature changes
- **THEN** the verdict fails with a timestamp reason

### Requirement: Trust the timestamp authority

The signer SHALL chain to a timestamp authority of the trusted root at the timestamp
time: when the authority lists a leaf, the signer SHALL be that leaf; the leaf SHALL
have a critical extended key usage of exactly timeStamping; each certificate SHALL be
valid at that time; and the authority's validity period SHALL contain it.

#### Scenario: Untrusted authority

- **WHEN** a timestamp is signed by an authority that the trusted root does not list
- **THEN** the verdict fails with a timestamp authority reason

#### Scenario: Time outside the authority validity

- **WHEN** the timestamp time is after the end of the authority's validity period
- **THEN** the verdict fails with a timestamp authority reason

### Requirement: Bind the timestamp to the signature

The message imprint SHALL be SHA-256, SHA-384 or SHA-512 of the bundle signature
bytes: the DSSE signature, or the message signature. The timestamp time SHALL NOT be
later than "now".

#### Scenario: Timestamp for another signature

- **WHEN** the imprint does not equal the hash of the bundle signature
- **THEN** the verdict fails with a timestamp reason

#### Scenario: Timestamp in the future

- **WHEN** the timestamp time is later than "now"
- **THEN** the verdict fails with a timestamp time reason

### Requirement: Combine time sources

The verified times SHALL be the integrated time of each verified log entry and the
time of each verified timestamp. A bundle SHALL have at least one verified time; a
timestamp or log entry that does not verify SHALL fail the verdict; and the leaf
certificate SHALL be valid, and chain to a certificate authority, at every verified time.

#### Scenario: Private repository provenance

- **WHEN** a caller verifies the cli/cli private-repository provenance test bundle, which has one timestamp and no log entry, with the GitHub root and a workflow policy for its repository
- **THEN** the verdict passes and gives the timestamp time as the verified time

#### Scenario: No time source

- **WHEN** a bundle has neither a log entry nor a timestamp
- **THEN** the verdict fails with a transparency log reason

#### Scenario: Leaf expired at the timestamp time

- **WHEN** the timestamp time is after the leaf's not-after time
- **THEN** the verdict fails with a certificate validity reason

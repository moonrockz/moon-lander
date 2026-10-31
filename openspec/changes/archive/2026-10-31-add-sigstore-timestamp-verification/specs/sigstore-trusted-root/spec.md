# Spec Delta

## ADDED Requirements

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

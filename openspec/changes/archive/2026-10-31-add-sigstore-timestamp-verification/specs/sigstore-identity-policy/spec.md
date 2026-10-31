# Spec Delta

## MODIFIED Requirements

### Requirement: Match the issuer

A workflow or subject-name policy SHALL require one exact OIDC issuer. The verifier
SHALL read the issuer from the Fulcio issuer extension `1.3.6.1.4.1.57264.1.8`, or
from `1.3.6.1.4.1.57264.1.1` when the first is absent. A release policy SHALL NOT
require an issuer, because GitHub release certificates have no issuer extension.

#### Scenario: Other issuer

- **WHEN** the policy issuer is `https://token.actions.githubusercontent.com` and the certificate issuer is `https://accounts.google.com`
- **THEN** the verdict fails with an issuer mismatch reason that gives both values

#### Scenario: Release certificate without issuer

- **WHEN** a release policy meets the cli/cli `v2.103.3` release leaf, which has no Fulcio extensions
- **THEN** the issuer check passes

## ADDED Requirements

### Requirement: Match a GitHub release attestation

A release policy SHALL require the SAN `https://dotcom.releases.github.com`, a
statement with predicate type `https://in-toto.io/attestation/release/v0.2`, and a
predicate whose `repository` (without regard to ASCII case), `tag` and `purl`
(`pkg:github/<owner>/<repo>@<tag>`, version percent-decoded) match the policy, and a
certificate with no OIDC issuer extension. It SHALL optionally require the predicate
`repositoryId` and `ownerId`. A workflow claim added to a release policy SHALL fail.

#### Scenario: Release asset

- **WHEN** a caller verifies the cli/cli `v2.103.3` release attestation for the digest of a release asset, with the GitHub root and a release policy for `cli/cli` at tag `v2.103.3`
- **THEN** the verdict passes

#### Scenario: Other tag

- **WHEN** the release policy names tag `v2.103.2`
- **THEN** the verdict fails with a release mismatch reason that names the tag

#### Scenario: Other repository ID

- **WHEN** the release policy requires repository ID `1` and the predicate has `212613049`
- **THEN** the verdict fails with a release mismatch reason that names the repository ID

#### Scenario: Workflow certificate with the release SAN

- **WHEN** a certificate has the SAN `https://dotcom.releases.github.com` and an OIDC issuer
- **THEN** a release policy fails with a release mismatch reason that names the issuer

#### Scenario: Workflow claim on a release policy

- **WHEN** a release policy also requires the source ref `refs/heads/main`
- **THEN** the release attestation fails, because its certificate has no source ref

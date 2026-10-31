# sigstore-identity-policy Specification

## Purpose
Let a caller state which publisher identity a signing certificate must carry, and
match that identity against the Fulcio certificate of a verified bundle.

## Requirements

### Requirement: Typed identity values

A policy SHALL be made only from parsed values: an OIDC issuer URL, a certificate
identity, a GitHub repository or owner, a workflow path, a Git ref, a GitHub ID and a
predicate type.
Each parse SHALL fail with a typed error that names the input and the broken rule.

#### Scenario: Repository without owner

- **WHEN** a caller parses the repository `morphir-rust`
- **THEN** the parse fails with an error that requires the form `owner/repo`

#### Scenario: Issuer without HTTPS

- **WHEN** a caller parses the issuer `http://token.actions.githubusercontent.com`
- **THEN** the parse fails with an error that requires an `https` URL

#### Scenario: Ref without prefix

- **WHEN** a caller parses the ref `v0.2.0`
- **THEN** the parse fails with an error that requires a `refs/` prefix

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

### Requirement: Match the certificate identity

A policy SHALL require either an exact SAN URI, or a signer workflow given as a
repository, a workflow path and an optional ref. A signer workflow SHALL match the
SAN `https://github.com/<owner>/<repo>/<path>@<ref>`. Without a ref, the policy accepts
any ref.

#### Scenario: Signer workflow without ref

- **WHEN** the policy signer workflow is `finos/morphir-rust` with path `.github/workflows/release-provider-snapshot.yml` and no ref, and the SAN is that workflow at `refs/tags/provider-snapshot/v0.2.0`
- **THEN** the identity matches

#### Scenario: Other workflow file

- **WHEN** the policy names `.github/workflows/release.yml` and the SAN names `.github/workflows/release-provider-snapshot.yml`
- **THEN** the verdict fails with an identity mismatch reason

#### Scenario: Path prefix is not a match

- **WHEN** the policy names `.github/workflows/release.yml` and the SAN names `.github/workflows/release.yml.evil.yml@refs/heads/main`
- **THEN** the verdict fails with an identity mismatch reason

### Requirement: Match GitHub source claims

A policy SHALL optionally require a source repository, a source repository owner, a
repository ID, an owner ID and a source ref. The verifier SHALL compare each with the
matching Fulcio extension: repository and owner URLs without regard to ASCII case, as
GitHub names are, and IDs and refs exactly. A missing extension SHALL fail a required claim.

#### Scenario: Source repository

- **WHEN** the policy requires the source repository `finos/morphir-rust` and extension `1.3.6.1.4.1.57264.1.12` is `https://github.com/finos/morphir-rust`
- **THEN** the claim matches

#### Scenario: Recreated repository

- **WHEN** the policy requires repository ID `513894754` and extension `1.3.6.1.4.1.57264.1.15` is `999`
- **THEN** the verdict fails with a claim mismatch reason that names the repository ID

#### Scenario: Source ref

- **WHEN** the policy requires the source ref `refs/heads/main` and extension `1.3.6.1.4.1.57264.1.14` is `refs/tags/provider-snapshot/v0.2.0`
- **THEN** the verdict fails with a claim mismatch reason that names the source ref

### Requirement: Match the predicate type

A policy SHALL optionally require the predicate type of the in-toto statement. The
GitHub workflow policy SHALL require `https://slsa.dev/provenance/v1` unless the caller
gives another type. A bundle without a statement SHALL fail a required predicate type.

#### Scenario: SBOM attestation for a provenance policy

- **WHEN** a GitHub workflow policy with the default predicate type meets a statement with predicate type `https://spdx.dev/Document/v2.3`
- **THEN** the verdict fails with a predicate type mismatch reason that gives both values

#### Scenario: Provenance for an SBOM policy

- **WHEN** the policy requires `https://spdx.dev/Document/v2.3` and the morphir-rust bundle has SLSA provenance v1
- **THEN** the verdict fails with a predicate type mismatch reason

### Requirement: Refuse self-hosted runners

A policy SHALL optionally require the runner environment `github-hosted`. With that
requirement, a certificate with runner environment `self-hosted`, or with no runner
environment extension, SHALL fail.

#### Scenario: Self-hosted runner

- **WHEN** the policy refuses self-hosted runners and extension `1.3.6.1.4.1.57264.1.11` is `self-hosted`
- **THEN** the verdict fails with a runner environment reason

#### Scenario: GitHub-hosted runner

- **WHEN** the policy refuses self-hosted runners and the extension is `github-hosted`
- **THEN** the runner claim matches

### Requirement: Match any of several identities

A caller SHALL give one or more policies. The verdict SHALL pass when the certificate
matches at least one policy. A failed verdict SHALL give the mismatch reason of each
policy.

#### Scenario: Second publisher matches

- **WHEN** the policies name `finos/morphir-python` and `finos/morphir-rust`, and the bundle was signed by `finos/morphir-rust`
- **THEN** the verdict passes and names the second policy as the match

### Requirement: Match a GitHub release attestation

A release policy SHALL require the SAN `https://dotcom.releases.github.com`, a
statement with predicate type `https://in-toto.io/attestation/release/v0.2`, and a
predicate whose `repository` (without regard to ASCII case), `tag` and `purl`
(`pkg:github/<owner>/<repo>@<tag>`) match the policy. It SHALL optionally require the
predicate `repositoryId` and `ownerId`.

#### Scenario: Release asset

- **WHEN** a caller verifies the cli/cli `v2.103.3` release attestation for the digest of a release asset, with the GitHub root and a release policy for `cli/cli` at tag `v2.103.3`
- **THEN** the verdict passes

#### Scenario: Other tag

- **WHEN** the release policy names tag `v2.103.2`
- **THEN** the verdict fails with a release mismatch reason that names the tag

#### Scenario: Other repository ID

- **WHEN** the release policy requires repository ID `1` and the predicate has `212613049`
- **THEN** the verdict fails with a release mismatch reason that names the repository ID

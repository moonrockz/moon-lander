# moonrockz/sigstore

Verify [Sigstore](https://www.sigstore.dev/) bundles and GitHub artifact
attestations in MoonBit, on the `wasm`, `wasm-gc`, `js` and `native` targets.

`actions/attest` signs a release in GitHub Actions and stores a Sigstore bundle.
This module checks that bundle offline. It is a pure function of five inputs: the
artifact digest, the bundle, a trusted root, an identity policy and the time "now".
It does no network, filesystem or clock I/O, so a program can verify a bundle at
install time and verify it again later from a lock file, with the same result.

The verifier does these checks, in this order, with the rules of
[sigstore-go](https://github.com/sigstore/sigstore-go):

| Step | Check |
| --- | --- |
| Transparency log | The Rekor v1 entry is from a log of the trusted root. Its signed entry timestamp (SET) verifies, and its integrated time is in the log's validity and not after "now" |
| Inclusion | The RFC 6962 inclusion proof gives the root hash of a checkpoint that the log key signed |
| Certificate | The Fulcio leaf chains to a certificate authority of the trusted root at the integrated time, for code signing |
| Certificate timestamp | An embedded SCT from a trusted CT log verifies |
| Log body | The logged signature, certificate and payload hash are those of the bundle |
| Content | The DSSE signature (or message signature) verifies with the leaf key |
| Artifact | A subject of the in-toto statement (or the message digest) is the artifact digest |
| Policy | The certificate has the issuer, identity and GitHub claims of a policy |

## Verify a GitHub release

Parse each input once at the boundary, then call `verify`. The caller reads the
clock and gives "now". `TrustedRoot::public_good()` is a pinned copy of the
Sigstore public-good root, so it needs no I/O:

```mbt check
///|
test "verify the attestation of a GitHub release" {
  let bundle = @sigstore.Bundle::parse(
    github_fixture("cli-2.50.0.sigstore.json"),
  )
  let digest = @sigstore.ArtifactDigest::parse(
    "sha256:7f9795b3ce99351a1bfc6ea3b09b7363cb1eccca19978a046bcb477839efab82",
  )
  let policy = @sigstore.Policy::github_workflow(
    @sigstore.GitHubRepository::parse("cli/cli"),
    workflow=@sigstore.WorkflowPath::parse(".github/workflows/deployment.yml"),
  )
  let now = @sigstore.Instant::from_unix_seconds(1793000000L)
  match
    @sigstore.verify(
      bundle,
      digest,
      @sigstore.TrustedRoot::public_good(),
      policy,
      now~,
    ) {
    Verified(facts) => {
      assert_eq(facts.integrated_time.unix_seconds(), 1716998983L)
      assert_eq(facts.claims.source_repository_ref, Some("refs/heads/trunk"))
      assert_true(facts.statement is Some({ predicate_type: "https://slsa.dev/provenance/v1", .. }))
    }
    Rejected(reason) => fail(reason.message())
  }
}
```

`github_fixture` reads the test data of this module. A program gets the bundle
from the GitHub attestations API or from `gh attestation download`.

## Policies

A `Policy` names the publisher that must have signed the bundle. It is made only
from parsed values, each with a smart constructor and a typed `IdentityError`:

| Type | Example | Rules |
| --- | --- | --- |
| `Issuer` | `https://token.actions.githubusercontent.com` | An `https` URL with a host |
| `SubjectName` | the certificate SAN | Not empty, no spaces |
| `GitHubRepository` | `finos/morphir-rust` | `owner/repo` with GitHub's name rules |
| `GitHubOwner` | `finos` | 1 to 39 letters, digits and `-` |
| `WorkflowPath` | `.github/workflows/release.yml` | A `.yml` or `.yaml` file directly in `.github/workflows/` |
| `GitRef` | `refs/tags/v1.0.0` | `refs/` and a name |
| `GitHubId` | `513894754` | Decimal digits, no leading zero |

`Policy::github_workflow` requires the signer workflow, the same source repository
and a GitHub-hosted runner. Add claims to pin more. A deleted and recreated
repository keeps its name but gets a new ID, so a trust record should pin the IDs:

```mbt check
///|
test "a policy that pins the repository and owner IDs" {
  let repository = @sigstore.GitHubRepository::parse("finos/morphir-rust")
  let policy = @sigstore.Policy::github_workflow(
      repository,
      workflow=@sigstore.WorkflowPath::parse(
        ".github/workflows/release-provider-snapshot.yml",
      ),
    )
    .repository_id(@sigstore.GitHubId::parse("513894754"))
    .owner_id(@sigstore.GitHubId::parse("35377814"))
  let verdict = @sigstore.verify(
    @sigstore.Bundle::parse(
      github_fixture("morphir-rust-provider-snapshot-0.2.0.sigstore.json"),
    ),
    @sigstore.ArtifactDigest::parse(
      "sha256:03d190b8ef97d354f9aca6854542979c36ce5f77c68a3d80de28ac1a77c432bd",
    ),
    @sigstore.TrustedRoot::public_good(),
    policy,
    now=@sigstore.Instant::from_unix_seconds(1793000000L),
  )
  assert_true(verdict is Verified(_))
}
```

Owner and repository names compare without regard to case, as on GitHub. Workflow
paths and refs compare exactly. Give `alternatives=` to accept one of several
publishers; the verdict names the policy that matched.

## Read a rejection

A `Verdict` is `Verified(VerifiedBundle)` or `Rejected(Rejection)`. A rejection
is `Invalid(Failure)`, with one case for each check, or `Unsupported(Feature)`
for a valid bundle that this version cannot check yet. So a program can tell
"this bundle is bad" from "update the tool":

```mbt check
///|
test "a policy for another repository rejects the bundle" {
  let verdict = @sigstore.verify(
    @sigstore.Bundle::parse(github_fixture("cli-2.50.0.sigstore.json")),
    @sigstore.ArtifactDigest::parse(
      "sha256:7f9795b3ce99351a1bfc6ea3b09b7363cb1eccca19978a046bcb477839efab82",
    ),
    @sigstore.TrustedRoot::public_good(),
    @sigstore.Policy::github_workflow(
      @sigstore.GitHubRepository::parse("cli/go-gh"),
      workflow=@sigstore.WorkflowPath::parse(".github/workflows/deployment.yml"),
    ),
    now=@sigstore.Instant::from_unix_seconds(1793000000L),
  )
  guard verdict is Rejected(Invalid(Policy([IdentityMismatch(..)]))) else {
    fail("expected an identity mismatch")
  }
}
```

## Scope

Supported: bundle media types v0.1, v0.2 and v0.3; DSSE envelopes with in-toto
statements, and message signatures; Fulcio certificates; Rekor v1 entries of kind
`dsse` and `hashedrekord` 0.0.1; ECDSA P-256 and P-384. This covers the attestations
that `actions/attest` makes for public repositories.

Not supported yet, each with an `Unsupported` reason: Rekor v2 entries, RFC 3161
timestamps (the only time source of attestations from private repositories and of
GitHub immutable releases), managed-key bundles, and Ed25519 or RSA keys. A Sigstore
TUF client that refreshes the trusted root is a later change; give
`TrustedRoot::parse` a newer root when the public-good keys change.

## Cryptography

All cryptography is pure MoonBit, so each target runs the same code with no host
crypto. SHA-2 and ECDSA come from
[`moonbitstack/mooncrypt`](https://mooncakes.io/docs/moonbitstack/mooncrypt) at an
exact version. The module's own code reads DER strictly, checks public keys
(uncompressed, coordinates below the field prime, on the curve) and runs the
Wycheproof ECDSA vectors on every target. A verification makes six signature checks;
on an Apple Silicon Mac it takes about 16 ms on native and 41 ms on wasm-gc
(`mise run bench:sigstore`).

## Test data

`testdata/` holds the sources of the tests, with their licenses: 70
[sigstore-conformance](https://github.com/sigstore/sigstore-conformance) cases, the
Wycheproof ECDSA vectors, three real GitHub attestations and the pinned
public-good root. See [testdata/README.md](testdata/README.md).
`mise run build:sigstore-assets` writes them as MoonBit constants, because wasm
tests cannot read files.

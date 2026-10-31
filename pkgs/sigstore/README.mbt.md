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
| Time sources | Each Rekor v1 entry is from a log of the trusted root, its signed entry timestamp (SET) verifies, and its integrated time is in the log's validity. Each RFC 3161 timestamp is signed by a timestamp authority of the trusted root and covers the bundle signature. Every time is not after "now", and there is at least one |
| Inclusion | The RFC 6962 inclusion proof gives the root hash of a checkpoint that the log key signed |
| Certificate | The Fulcio leaf chains to a certificate authority of the trusted root at every verified time, for code signing |
| Certificate timestamp | When the root of that authority lists CT logs, an embedded SCT from one of them verifies |
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
      assert_eq(facts.times[0].time.unix_seconds(), 1716998983L)
      assert_eq(facts.claims.source_repository_ref, Some("refs/heads/trunk"))
      guard facts.statement is Some(statement) else { fail("no statement") }
      assert_eq(statement.predicate_type, @sigstore.PredicateType::slsa_provenance_v1())
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
| `PredicateType` | `https://slsa.dev/provenance/v1` | An absolute URI |

`Policy::github_workflow` requires the signer workflow, the same source repository,
a GitHub-hosted runner and an in-toto statement of SLSA provenance v1, as
`gh attestation verify` does. So an SBOM attestation that the same workflow made
does not pass as provenance; give `predicate_type=` to accept another type. Add claims to pin more. A deleted and recreated
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

## Choose a trusted root

GitHub signs attestations with two Sigstore instances, so the module pins two
roots. Both need no I/O:

| Root | Holds | Signs |
| --- | --- | --- |
| `TrustedRoot::public_good()` | Rekor and CT logs, Fulcio, a TSA | Attestations of public repositories |
| `TrustedRoot::github()` | GitHub's Fulcio and TSA, no logs | Attestations of private repositories, and release attestations of immutable releases |
| `TrustedRoot::github_attestations()` | Both | All of them; a public-good leaf still needs its SCT, and a GitHub leaf needs none |

`TrustedRoot::combine` joins any parsed roots in the same way. `VerifiedBundle.times`
lists each verified time and its source: a log entry or a timestamp authority.

## Verify an immutable release

A GitHub immutable release has a release attestation. GitHub signs it, so the
certificate names no workflow; the statement names the repository and the tag.
`Policy::github_release` matches them, and the artifact digest is the SHA-256 of a
release asset:

```mbt check
///|
test "verify a release asset of an immutable release" {
  let verdict = @sigstore.verify(
    @sigstore.Bundle::parse(github_fixture("release-cli-2.103.3.sigstore.json")),
    @sigstore.ArtifactDigest::parse(
      "sha256:4c806978ffce1cec70853302a56d70ac6da4f19bae7adca4e1a8ab00633dd91d",
    ),
    @sigstore.TrustedRoot::github_attestations(),
    @sigstore.Policy::github_release(
      @sigstore.GitHubRepository::parse("cli/cli"),
      tag=@sigstore.ReleaseTag::parse("v2.103.3"),
    ).repository_id(@sigstore.GitHubId::parse("212613049")),
    now=@sigstore.Instant::from_unix_seconds(1794000000L),
  )
  guard verdict is Verified(facts) else { fail("not verified") }
  guard facts.times is [{ source: Authority(uri~), .. }] else { fail("not a timestamp") }
  assert_eq(uri, "timestamp.githubapp.com")
}
```

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
statements, and message signatures; Fulcio certificates of the public-good and
GitHub instances; Rekor v1 entries of kind `dsse` and `hashedrekord` 0.0.1 and
`intoto` 0.0.2; RFC 3161 timestamps with ECDSA; ECDSA P-256 and P-384. This covers
the attestations that `actions/attest` makes for public and private repositories,
and the release attestations of GitHub immutable releases (release assets).

Not supported yet, each with an `Unsupported` reason: Rekor v2 entries, managed-key
bundles, Ed25519 or RSA keys, and RSA timestamps. Release verification of the tag
commit (a SHA-1 digest) and GitHub data-residency roots are not covered. A TUF client
that refreshes the trusted roots is a later change; give `TrustedRoot::parse` a newer
root when the keys change.

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

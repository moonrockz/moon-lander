///|
/// A valid bundle feature that this verifier does not support yet.
pub enum Feature {
  /// The content is signed by a key that the bundle names by a hint, not by a
  /// certificate (managed keys).
  PublicKeyMaterial
  /// The only time source is an RFC 3161 timestamp, as in bundles from
  /// private repositories and GitHub immutable releases.
  TimestampAuthority
  /// A Rekor v2 (rekor-tiles) entry.
  RekorV2
  /// A Rekor entry kind and version other than `dsse/0.0.1` and
  /// `hashedrekord/0.0.1`.
  EntryKind(kind~ : String, version~ : String)
  /// A key type, for example `Ed25519`.
  KeyType(String)
  /// A message digest algorithm other than SHA-256.
  DigestAlgorithm(String)
} derive(Eq, Debug)

///|
pub extend Feature with Eq::{equal, not_equal}

///|
pub extend Feature with @debug.Debug::{to_repr}

///|
/// A check of the verification pipeline that failed, with the detail that a
/// user needs.
pub enum Failure {
  /// The bundle is well-formed JSON but has a shape that verification refuses.
  BundleShape(String)
  /// The transparency log entry is from an unknown log, or its signed entry
  /// timestamp does not verify.
  TransparencyLog(String)
  /// The integrated time is outside the log's validity, or later than "now".
  TransparencyLogTime(integrated_time~ : Instant, now~ : Instant)
  /// The log entry body does not match the bundle.
  TransparencyLogBody(String)
  /// The inclusion proof does not give the root hash.
  InclusionProof(String)
  /// The checkpoint does not verify or has another root hash.
  Checkpoint(String)
  /// The leaf certificate cannot be read or used.
  Certificate(String)
  /// The leaf certificate was not valid at the integrated time.
  CertificateValidity(not_before~ : Instant, not_after~ : Instant, time~ : Instant)
  /// No trusted certificate authority issued the leaf at the integrated time.
  CertificateChain(String)
  /// No embedded signed certificate timestamp verifies.
  CertificateTimestamp(String)
  /// The DSSE payload type is not `application/vnd.in-toto+json`.
  PayloadType(String)
  /// The content signature does not verify with the leaf key.
  ContentSignature
  /// The DSSE payload is not an in-toto statement that verification can read.
  Statement(String)
  /// No subject (or message digest) has the artifact digest.
  ArtifactDigestMismatch(ArtifactDigest)
  /// The certificate matches no policy; one reason for each policy.
  Policy(Array[PolicyMismatch])
} derive(Eq, Debug)

///|
pub extend Failure with Eq::{equal, not_equal}

///|
pub extend Failure with @debug.Debug::{to_repr}

///|
/// Why a bundle was not verified: a valid feature that is not supported, or
/// a check that failed.
pub enum Rejection {
  Unsupported(Feature)
  Invalid(Failure)
} derive(Eq, Debug)

///|
pub extend Rejection with Eq::{equal, not_equal}

///|
pub extend Rejection with @debug.Debug::{to_repr}

///|
pub fn Rejection::message(self : Rejection) -> String {
  match self {
    Unsupported(feature) => {
      let name = match feature {
        PublicKeyMaterial => "public key (managed key) bundles"
        TimestampAuthority => "bundles whose only time source is an RFC 3161 timestamp"
        RekorV2 => "Rekor v2 log entries"
        EntryKind(kind~, version~) => "Rekor entries of kind \{kind} \{version}"
        KeyType(kind) => "\{kind} keys"
        DigestAlgorithm(name) => "message digests with \{name}"
      }
      "Not supported: \{name}"
    }
    Invalid(failure) => {
      let reason = match failure {
        BundleShape(text) => "bundle: \{text}"
        TransparencyLog(text) => "transparency log: \{text}"
        TransparencyLogTime(integrated_time~, now~) =>
          "transparency log time \{integrated_time} is outside the log validity or after now (\{now})"
        TransparencyLogBody(text) => "transparency log body: \{text}"
        InclusionProof(text) => "inclusion proof: \{text}"
        Checkpoint(text) => "checkpoint: \{text}"
        Certificate(text) => "certificate: \{text}"
        CertificateValidity(not_before~, not_after~, time~) =>
          "the certificate is valid from \{not_before} to \{not_after}, not at \{time}"
        CertificateChain(text) => "certificate chain: \{text}"
        CertificateTimestamp(text) => "signed certificate timestamp: \{text}"
        PayloadType(text) => "the DSSE payload type is \{text.escape()}"
        ContentSignature => "the content signature does not verify"
        Statement(text) => "statement: \{text}"
        ArtifactDigestMismatch(digest) => "no subject has the digest \{digest}"
        Policy(reasons) =>
          "no policy matches: \{reasons.map(reason => reason.message()).join("; ")}"
      }
      "Invalid: \{reason}"
    }
  }
}

///|
/// One subject of an in-toto statement.
pub struct Subject {
  name : String
  /// The SHA-256 digest in lowercase hex, when the subject has one.
  sha256 : String?
} derive(Eq, Debug)

///|
pub extend Subject with Eq::{equal, not_equal}

///|
pub extend Subject with @debug.Debug::{to_repr}

///|
/// The in-toto statement of a verified DSSE bundle.
pub struct Statement {
  predicate_type : String
  subjects : Array[Subject]
  /// The exact payload bytes that the signature covers.
  payload : Bytes
} derive(Eq, Debug)

///|
pub extend Statement with Eq::{equal, not_equal}

///|
pub extend Statement with @debug.Debug::{to_repr}

///|
/// The facts of a verified bundle.
pub struct VerifiedBundle {
  /// The statement of a DSSE bundle; `None` for a message signature.
  statement : Statement?
  /// The index of the policy that matched: 0 for the first policy, then the
  /// alternatives in order.
  policy_index : Int
  claims : CertificateClaims
  /// The key ID of the transparency log.
  log_id : Bytes
  log_index : Int64
  integrated_time : Instant
} derive(Eq, Debug)

///|
pub extend VerifiedBundle with Eq::{equal, not_equal}

///|
pub extend VerifiedBundle with @debug.Debug::{to_repr}

///|
/// The result of a verification.
pub enum Verdict {
  Verified(VerifiedBundle)
  Rejected(Rejection)
} derive(Eq, Debug)

///|
pub extend Verdict with Eq::{equal, not_equal}

///|
pub extend Verdict with @debug.Debug::{to_repr}

///|
/// A valid bundle feature that this verifier does not support yet.
pub enum Feature {
  /// The content is signed by a key that the bundle names by a hint, not by a
  /// certificate (managed keys).
  PublicKeyMaterial
  /// An RFC 3161 timestamp uses an algorithm that the verifier does not
  /// support, for example an RSA signature.
  TimestampAlgorithm(String)
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
  /// An RFC 3161 timestamp cannot be read, does not verify, or is not for the
  /// bundle signature.
  Timestamp(String)
  /// No timestamp authority of the trusted root signed a timestamp at its time.
  TimestampAuthority(String)
  /// A timestamp time is later than "now".
  TimestampTime(time~ : Instant, now~ : Instant)
  /// The leaf certificate cannot be read or used.
  Certificate(CertificateProblem)
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
/// Why the leaf certificate cannot be used.
pub enum CertificateProblem {
  /// The certificate, its key or a Fulcio extension cannot be read; the text
  /// gives the rule.
  Unreadable(String)
  /// The leaf has no code signing extended key usage.
  NotForCodeSigning
  /// The leaf key usage does not allow digital signatures.
  NoDigitalSignature
  /// The leaf has a critical extension with this OID that the verifier does
  /// not understand.
  UnknownCriticalExtension(String)
  /// The leaf is a certificate authority.
  LeafIsAuthority
} derive(Eq, Debug)

///|
pub extend CertificateProblem with Eq::{equal, not_equal}

///|
pub extend CertificateProblem with @debug.Debug::{to_repr}

///|
/// Text for people that describes the problem.
pub fn CertificateProblem::message(self : CertificateProblem) -> String {
  match self {
    Unreadable(rule) => rule
    NotForCodeSigning => "the leaf is not for code signing"
    NoDigitalSignature => "the leaf key usage does not allow digital signatures"
    UnknownCriticalExtension(oid) => "the leaf has the unknown critical extension \{oid}"
    LeafIsAuthority => "the leaf is a certificate authority"
  }
}

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
/// Text for people that names the feature or the check, with its detail.
pub fn Rejection::message(self : Rejection) -> String {
  match self {
    Unsupported(feature) => {
      let name = match feature {
        PublicKeyMaterial => "public key (managed key) bundles"
        TimestampAlgorithm(name) => "RFC 3161 timestamps with \{name}"
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
        Timestamp(text) => "timestamp: \{text}"
        TimestampAuthority(text) => "timestamp authority: \{text}"
        TimestampTime(time~, now~) => "the timestamp time \{time} is after now (\{now})"
        Certificate(problem) => "certificate: \{problem.message()}"
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
  /// The SHA-256 digest, when the subject has one.
  sha256 : ArtifactDigest?
} derive(Eq, Debug)

///|
pub extend Subject with Eq::{equal, not_equal}

///|
pub extend Subject with @debug.Debug::{to_repr}

///|
/// The in-toto statement of a verified DSSE bundle.
pub struct Statement {
  predicate_type : PredicateType
  /// The predicate JSON, as the statement gives it.
  predicate : Json
  subjects : Array[Subject]
  /// The exact payload bytes that the signature covers.
  payload : Bytes
} derive(Eq, Debug)

///|
pub extend Statement with Eq::{equal, not_equal}

///|
pub extend Statement with @debug.Debug::{to_repr}

///|
/// What gave a verified time.
pub enum TimeSource {
  /// The signed entry timestamp of a transparency log entry.
  Log(log_id~ : Bytes, log_index~ : Int64)
  /// An RFC 3161 timestamp of the authority with this URI.
  Authority(uri~ : String)
} derive(Eq, Debug)

///|
pub extend TimeSource with Eq::{equal, not_equal}

///|
pub extend TimeSource with @debug.Debug::{to_repr}

///|
/// A time at which the bundle was signed, and what gave it.
pub struct VerifiedTime {
  time : Instant
  source : TimeSource
} derive(Eq, Debug)

///|
pub extend VerifiedTime with Eq::{equal, not_equal}

///|
pub extend VerifiedTime with @debug.Debug::{to_repr}

///|
/// The facts of a verified bundle.
pub struct VerifiedBundle {
  /// The statement of a DSSE bundle; `None` for a message signature.
  statement : Statement?
  /// The index of the policy that matched: 0 for the first policy, then the
  /// alternatives in order.
  policy_index : Int
  claims : CertificateClaims
  /// Each verified time, in the order: log entries, then timestamps. The
  /// leaf certificate was valid at each one.
  times : Array[VerifiedTime]
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

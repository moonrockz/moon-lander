///|
/// The rule of an artifact digest that a text breaks.
pub enum DigestRule {
  /// The text has no `algorithm:` prefix.
  MissingAlgorithm
  /// The algorithm is not `sha256`.
  UnsupportedAlgorithm(String)
  /// The value is not hex.
  NotHex
  /// The value does not have 32 bytes.
  WrongLength(Int)
} derive(Eq, Debug)

///|
pub extend DigestRule with Eq::{equal, not_equal}

///|
pub extend DigestRule with @debug.Debug::{to_repr}

///|
/// A text that is not a valid artifact digest.
pub suberror DigestError {
  InvalidDigest(text~ : String, rule~ : DigestRule)
} derive(Debug)

///|
pub extend DigestError with @debug.Debug::{to_repr}

///|
/// Text for people that names the input and the rule.
pub fn DigestError::message(self : DigestError) -> String {
  let InvalidDigest(text~, rule~) = self
  let reason = match rule {
    MissingAlgorithm => "use the form sha256:<hex>"
    UnsupportedAlgorithm(name) => "the algorithm \{name.escape()} is not supported; use sha256"
    NotHex => "the value is not hex"
    WrongLength(size) => "a SHA-256 digest has 32 bytes, not \{size}"
  }
  "Invalid artifact digest \{text.escape()}: \{reason}"
}

///|
/// The SHA-256 digest of an artifact.
pub struct ArtifactDigest {
  priv bytes : Bytes
} derive(Eq, Debug)

///|
pub extend ArtifactDigest with Eq::{equal, not_equal}

///|
pub extend ArtifactDigest with @debug.Debug::{to_repr}

///|
/// Parse a digest such as `sha256:03d190…32bd`. Hex digits can be in either case.
pub fn ArtifactDigest::parse(text : String) -> ArtifactDigest raise DigestError {
  guard text.find(":") is Some(colon) else {
    raise InvalidDigest(text~, rule=MissingAlgorithm)
  }
  let algorithm = text[:colon].to_owned()
  guard algorithm == "sha256" else {
    raise InvalidDigest(text~, rule=UnsupportedAlgorithm(algorithm))
  }
  let bytes = @encoding.decode_hex(text[colon + 1:]) catch {
    _ => raise InvalidDigest(text~, rule=NotHex)
  }
  guard bytes.length() == 32 else {
    raise InvalidDigest(text~, rule=WrongLength(bytes.length()))
  }
  { bytes, }
}

///|
/// The digest of the artifact bytes.
pub fn ArtifactDigest::of_bytes(artifact : BytesView) -> ArtifactDigest {
  { bytes: @signature.sha256(artifact) }
}

///|
/// The 32 digest bytes.
pub fn ArtifactDigest::to_bytes(self : ArtifactDigest) -> Bytes {
  self.bytes
}

///|
/// The digest as `sha256:<lowercase hex>`, which `ArtifactDigest::parse` reads back.
pub impl Show for ArtifactDigest with output(self, logger) {
  logger.write_string("sha256:")
  logger.write_string(@encoding.encode_hex(self.bytes))
}

///|
pub extend ArtifactDigest with Show::{output, to_string}

///|
/// A trusted root text that cannot be read.
pub suberror TrustedRootError {
  /// The media type is not a trusted root version that the library reads.
  UnsupportedTrustedRootMediaType(String)
  /// The field at `field` (a dotted JSON path) breaks `rule`.
  InvalidTrustedRoot(field~ : String, rule~ : String)
} derive(Debug)

///|
pub extend TrustedRootError with @debug.Debug::{to_repr}

///|
/// Text for people that names the field and the rule.
pub fn TrustedRootError::message(self : TrustedRootError) -> String {
  match self {
    UnsupportedTrustedRootMediaType(media_type) =>
      "Unsupported trusted root media type \{media_type.escape()}"
    InvalidTrustedRoot(field~, rule~) =>
      if field.is_empty() {
        "Invalid trusted root: \{rule}"
      } else {
        "Invalid trusted root field \{field}: \{rule}"
      }
  }
}

///|
/// Whether the verifier can use a key of the trusted root.
pub enum KeyStatus {
  /// The verifier can use the key.
  Supported
  /// The key type, for example `Ed25519`, that the verifier does not support.
  Unsupported(String)
} derive(Eq, Debug)

///|
pub extend KeyStatus with Eq::{equal, not_equal}

///|
pub extend KeyStatus with @debug.Debug::{to_repr}

///|
priv enum TrustedKey {
  Usable(@signature.PublicKey)
  Unusable(String)
}

///|
fn TrustedKey::status(self : TrustedKey) -> KeyStatus {
  match self {
    Usable(_) => Supported
    Unusable(kind) => Unsupported(kind)
  }
}

///|
/// A validity period. Both bounds are inclusive; an absent bound is open.
priv struct Period {
  start : Instant?
  end : Instant?
}

///|
fn Period::contains(self : Period, time : Instant) -> Bool {
  (self.start is None || self.start.unwrap() <= time) &&
  (self.end is None || time <= self.end.unwrap())
}

///|
/// A transparency log or a certificate-transparency log.
priv struct TrustedLog {
  base_url : String
  log_id : Bytes
  key : TrustedKey
  valid : Period
}

///|
/// A certificate authority or a timestamp authority.
priv struct Authority {
  uri : String
  /// The chain as the trusted root lists it: for a certificate authority the
  /// intermediates then the root; for a timestamp authority the leaf first.
  chain : Array[@x509.Certificate]
  valid : Period
  /// Whether a leaf of this authority needs an SCT: true when the root that
  /// listed the authority also lists CT logs (design ROOT-1).
  sct_required : Bool
}

///|
/// The keys and certificates that verification trusts. Only
/// `TrustedRoot::parse` and `TrustedRoot::public_good` make it.
pub struct TrustedRoot {
  priv tlogs : Array[TrustedLog]
  priv authorities : Array[Authority]
  priv ctlogs : Array[TrustedLog]
  priv timestamp_authorities : Array[Authority]
}

///|
/// A log of the trusted root, for display.
pub struct TrustedLogSummary {
  base_url : String
  key : KeyStatus
}

///|
/// What a trusted root holds, for display and tests.
pub struct TrustedRootSummary {
  transparency_logs : Array[TrustedLogSummary]
  certificate_authorities : Array[String]
  certificate_transparency_logs : Array[TrustedLogSummary]
  timestamp_authorities : Array[String]
}

///|
/// The logs and authorities of the root, and whether each log key is usable.
pub fn TrustedRoot::summary(self : TrustedRoot) -> TrustedRootSummary {
  fn log_summary(log : TrustedLog) -> TrustedLogSummary {
    { base_url: log.base_url, key: log.key.status() }
  }

  {
    transparency_logs: self.tlogs.map(log_summary),
    certificate_authorities: self.authorities.map(ca => ca.uri),
    certificate_transparency_logs: self.ctlogs.map(log_summary),
    timestamp_authorities: self.timestamp_authorities.map(tsa => tsa.uri),
  }
}

///|
let trusted_root_media_type : String = "application/vnd.dev.sigstore.trustedroot+json;version=0.1"

///|
/// Read a trusted root from its protobuf JSON text, as sigstore-go reads it.
pub fn TrustedRoot::parse(text : StringView) -> TrustedRoot raise TrustedRootError {
  parse_root(text) catch {
    Shape(field, rule) => raise InvalidTrustedRoot(field~, rule~)
    UnsupportedTrustedRootMediaType(_) as err => raise err
    InvalidTrustedRoot(..) as err => raise err
    err => raise InvalidTrustedRoot(field="", rule=err.to_string())
  }
}

///|
/// The pinned Sigstore public-good trusted root (sigstore/root-signing
/// `c9bda74`, SHA-256 `6494e21e…0b66`). It needs no I/O.
pub fn TrustedRoot::public_good() -> TrustedRoot {
  TrustedRoot::parse(public_good_document) catch {
    err => abort("the pinned public-good root does not parse: \{err.message()}")
  }
}

///|
/// The pinned trusted root of GitHub's Sigstore instance (the
/// `trusted_root.json` target of `https://tuf-repo.github.com`, SHA-256
/// `484cdfe1…fbb7`). It holds the certificate and timestamp authorities of
/// private-repository and release attestations, and no log. It needs no I/O.
pub fn TrustedRoot::github() -> TrustedRoot {
  TrustedRoot::parse(github_document) catch {
    err => abort("the pinned GitHub root does not parse: \{err.message()}")
  }
}

///|
/// The pinned GitHub `trusted_root.json` text.
pub fn github_trusted_root_json() -> String {
  github_document
}

///|
/// One root that trusts the logs and authorities of each of `roots`. Each
/// certificate authority keeps the SCT rule of its own root.
pub fn TrustedRoot::combine(roots : ArrayView[TrustedRoot]) -> TrustedRoot {
  {
    tlogs: roots.iter().flat_map(root => root.tlogs.iter()).collect(),
    authorities: roots.iter().flat_map(root => root.authorities.iter()).collect(),
    ctlogs: roots.iter().flat_map(root => root.ctlogs.iter()).collect(),
    timestamp_authorities: roots
      .iter()
      .flat_map(root => root.timestamp_authorities.iter())
      .collect(),
  }
}

///|
/// The public-good and GitHub roots combined: one root for public-repository,
/// private-repository and release attestations from GitHub. A public-good leaf
/// still needs its SCT; a GitHub leaf needs none.
pub fn TrustedRoot::github_attestations() -> TrustedRoot {
  TrustedRoot::combine([TrustedRoot::public_good(), TrustedRoot::github()])
}

///|
/// The pinned public-good `trusted_root.json` text.
pub fn public_good_trusted_root_json() -> String {
  public_good_document
}

///|
fn parse_root(text : StringView) -> TrustedRoot raise {
  let root = fields(parse_json(text), "", [
    "mediaType", "tlogs", "certificateAuthorities", "ctlogs", "timestampAuthorities",
  ])
  let media_type = root.require_string("mediaType")
  guard media_type == trusted_root_media_type else {
    raise UnsupportedTrustedRootMediaType(media_type)
  }
  let tlogs = root
    .array("tlogs")
    .mapi((index, json) => read_log(json, "\{root.at("tlogs")}[\{index}]", true))
  let ctlogs = root
    .array("ctlogs")
    .mapi((index, json) => read_log(json, "\{root.at("ctlogs")}[\{index}]", false))
  let authorities = root
    .array("certificateAuthorities")
    .mapi((index, json) => read_authority(json, "\{root.at("certificateAuthorities")}[\{index}]"))
  let timestamp_authorities = root
    .array("timestampAuthorities")
    .mapi((index, json) => read_authority(json, "\{root.at("timestampAuthorities")}[\{index}]"))
  let sct_required = !ctlogs.is_empty()
  {
    tlogs,
    authorities: authorities.map(authority => { ..authority, sct_required }),
    ctlogs,
    timestamp_authorities,
  }
}

///|
fn read_period(parent : Fields, name : String) -> Period raise Shape {
  match parent.object(name, ["start", "end"]) {
    Some(range) => {
      fn bound(field : String) -> Instant? raise Shape {
        match range.string(field) {
          Some(text) =>
            match parse_timestamp(text) {
              Some(time) => Some(time)
              None => raise Shape(range.at(field), "not an RFC 3339 time")
            }
          None => None
        }
      }

      { start: bound("start"), end: bound("end") }
    }
    None => { start: None, end: None }
  }
}

///|
fn read_log(json : Json, path : String, require_start : Bool) -> TrustedLog raise Shape {
  let log = fields(json, path, [
    "baseUrl", "hashAlgorithm", "publicKey", "logId", "checkpointKeyId", "operator",
  ])
  let key = log.require_object("publicKey", ["rawBytes", "keyDetails", "validFor"])
  let valid = read_period(key, "validFor")
  if require_start {
    guard valid.start is Some(_) else {
      raise Shape(key.at("validFor.start"), "the log \{log.string("baseUrl").unwrap_or("")} has no validity start")
    }
  }
  let raw = key.require_bytes("rawBytes")
  // The key details name the encoding: an ECDSA key must be a valid DER
  // SubjectPublicKeyInfo; another type, such as a PKCS#1 RSA key, is kept but
  // is not usable.
  let details = match key.get("keyDetails") {
    Some(String(name)) => Some(name)
    Some(Number(_, ..)) => Some("key details \{key.get("keyDetails").unwrap().stringify()}")
    _ => None
  }
  let trusted_key = try @signature.PublicKey::from_spki(raw) catch {
    UnsupportedKey(kind) => Unusable(kind)
    BadKey(rule) =>
      match details {
        Some(name) if !name.has_prefix("PKIX_ECDSA") => Unusable(name)
        _ => raise Shape(key.at("rawBytes"), rule)
      }
  } noraise {
    parsed => Usable(parsed)
  }
  {
    base_url: log.string("baseUrl").unwrap_or(""),
    log_id: log.require_object("logId", ["keyId"]).require_bytes("keyId"),
    key: trusted_key,
    valid,
  }
}

///|
fn read_authority(json : Json, path : String) -> Authority raise Shape {
  let authority = fields(json, path, ["subject", "uri", "certChain", "validFor", "operator"])
  ignore(authority.object("subject", ["organization", "commonName"]))
  let chain = authority.require_object("certChain", ["certificates"])
  let certificates = chain
    .array("certificates")
    .mapi((index, item) => {
      let at = "\{chain.at("certificates")}[\{index}]"
      let raw = fields(item, at, ["rawBytes"]).require_bytes("rawBytes")
      @x509.parse(raw) catch {
        err => raise Shape(at, "\{err.message()} in \{authority.string("uri").unwrap_or(path)}")
      }
    })
  guard !certificates.is_empty() else {
    raise Shape(chain.at("certificates"), "the chain is empty")
  }
  {
    uri: authority.string("uri").unwrap_or(""),
    chain: certificates,
    valid: read_period(authority, "validFor"),
    sct_required: false,
  }
}

///|
fn TrustedRoot::tlog(self : TrustedRoot, log_id : BytesView) -> TrustedLog? {
  self.tlogs.iter().find_first(log => log.log_id[:] == log_id)
}

///|
fn TrustedRoot::ctlog(self : TrustedRoot, log_id : BytesView) -> TrustedLog? {
  self.ctlogs.iter().find_first(log => log.log_id[:] == log_id)
}

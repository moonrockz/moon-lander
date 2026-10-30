///|
/// A bundle text that cannot be read.
pub suberror BundleError {
  /// The media type is not a bundle version that the library reads.
  UnsupportedBundleMediaType(String)
  /// The field at `field` (a dotted JSON path) breaks `rule`.
  InvalidBundle(field~ : String, rule~ : String)
} derive(Debug)

///|
pub extend BundleError with @debug.Debug::{to_repr}

///|
pub fn BundleError::message(self : BundleError) -> String {
  match self {
    UnsupportedBundleMediaType(media_type) =>
      "Unsupported bundle media type \{media_type.escape()}"
    InvalidBundle(field~, rule~) =>
      if field.is_empty() {
        "Invalid bundle: \{rule}"
      } else {
        "Invalid bundle field \{field}: \{rule}"
      }
  }
}

///|
/// The bundle format version.
pub enum BundleVersion {
  V0_1
  V0_2
  V0_3
} derive(Eq, Compare, Debug)

///|
pub extend BundleVersion with Eq::{equal, not_equal}

///|
pub extend BundleVersion with Compare::{compare, op_lt, op_le, op_ge, op_gt}

///|
pub extend BundleVersion with @debug.Debug::{to_repr}

///|
/// The key material that signed the content.
priv enum Material {
  /// A leaf certificate. Like sigstore-go, verification ignores the other
  /// certificates of a v0.1 or v0.2 chain and uses only the trusted root.
  Certificate(Bytes)
  /// A key that the verifier knows by a hint. Not supported.
  KeyHint
}

///|
priv struct Envelope {
  payload : Bytes
  payload_type : String
  signatures : Array[Bytes]
}

///|
priv enum Content {
  Dsse(Envelope)
  Message(algorithm~ : String, digest~ : Bytes, signature~ : Bytes)
}

///|
priv struct InclusionProof {
  log_index : Int64
  root_hash : Bytes
  tree_size : Int64
  hashes : Array[Bytes]
  checkpoint : String
}

///|
priv struct LogEntry {
  log_index : Int64
  log_id : Bytes
  kind : String
  version : String
  integrated_time : Int64
  promise : Bytes?
  proof : InclusionProof?
  body : Bytes
}

///|
/// A parsed Sigstore bundle. Only `Bundle::parse` makes it, and it holds the
/// values that verification checks.
pub struct Bundle {
  priv version : BundleVersion
  priv material : Material
  priv content : Content
  priv entries : Array[LogEntry]
  priv timestamps : Int
}

///|
/// The format version of the bundle.
pub fn Bundle::version(self : Bundle) -> BundleVersion {
  self.version
}

///|
/// The most tlog entries and timestamps that a bundle can hold, as in sigstore-go.
let max_entries : Int = 32

///|
let hash_algorithm_names : Array[String] = [
  "HASH_ALGORITHM_UNSPECIFIED", "SHA2_256", "SHA2_384", "SHA2_512", "SHA3_256", "SHA3_384",
]

///|
fn media_version(media_type : String) -> BundleVersion? {
  match media_type {
    "application/vnd.dev.sigstore.bundle+json;version=0.1" => Some(V0_1)
    "application/vnd.dev.sigstore.bundle+json;version=0.2" => Some(V0_2)
    "application/vnd.dev.sigstore.bundle+json;version=0.3" => Some(V0_3)
    "application/vnd.dev.sigstore.bundle.v0.1+json" => Some(V0_1)
    "application/vnd.dev.sigstore.bundle.v0.2+json" => Some(V0_2)
    "application/vnd.dev.sigstore.bundle.v0.3+json" => Some(V0_3)
    _ => None
  }
}

///|
/// Read a bundle from its protobuf JSON text, with the rules of sigstore-go.
pub fn Bundle::parse(text : StringView) -> Bundle raise BundleError {
  parse_bundle(text) catch {
    Shape(field, rule) => raise InvalidBundle(field~, rule~)
    UnsupportedBundleMediaType(_) as err => raise err
    InvalidBundle(..) as err => raise err
    err => raise InvalidBundle(field="", rule=err.to_string())
  }
}

///|
fn parse_bundle(text : StringView) -> Bundle raise {
  let root = fields(parse_json(text), "", [
    "mediaType", "verificationMaterial", "messageSignature", "dsseEnvelope",
  ])
  let media_type = root.require_string("mediaType")
  guard media_version(media_type) is Some(version) else {
    raise UnsupportedBundleMediaType(media_type)
  }
  let material = root.require_object("verificationMaterial", [
    "publicKey", "x509CertificateChain", "certificate", "tlogEntries", "timestampVerificationData",
  ])
  let content = match (root.has("dsseEnvelope"), root.has("messageSignature")) {
    (true, false) => Dsse(read_envelope(root.require_object("dsseEnvelope", ["payload", "payloadType", "signatures"])))
    (false, true) => read_message(root.require_object("messageSignature", ["messageDigest", "signature"]))
    _ => raise Shape("", "exactly one of dsseEnvelope and messageSignature is required")
  }
  let key_material = read_material(material, version)
  let entries = material
    .array("tlogEntries")
    .mapi((index, json) => read_entry(json, "\{material.at("tlogEntries")}[\{index}]", version))
  guard entries.length() <= max_entries else {
    raise Shape(material.at("tlogEntries"), "more than \{max_entries} entries")
  }
  let timestamps = match material.object("timestampVerificationData", ["rfc3161Timestamps"]) {
    Some(data) => {
      let list = data.array("rfc3161Timestamps")
      for index, item in list {
        ignore(fields(item, "\{data.at("rfc3161Timestamps")}[\{index}]", ["signedTimestamp"]).require_bytes("signedTimestamp"))
      }
      list.length()
    }
    None => 0
  }
  guard timestamps <= max_entries else {
    raise Shape(material.at("timestampVerificationData"), "more than \{max_entries} timestamps")
  }
  { version, material: key_material, content, entries, timestamps }
}

///|
fn read_material(material : Fields, version : BundleVersion) -> Material raise Shape {
  let present = ["publicKey", "x509CertificateChain", "certificate"].filter(name => material.has(name))
  guard present.length() == 1 else {
    raise Shape(material.path, "exactly one of publicKey, x509CertificateChain and certificate is required")
  }
  match present[0] {
    "publicKey" => {
      ignore(material.require_object("publicKey", ["hint"]).string("hint"))
      KeyHint
    }
    "x509CertificateChain" => {
      guard version != V0_3 else {
        raise Shape(material.at("x509CertificateChain"), "a v0.3 bundle must use certificate")
      }
      let chain = material.require_object("x509CertificateChain", ["certificates"])
      let certificates = chain
        .array("certificates")
        .mapi((index, json) => fields(json, "\{chain.at("certificates")}[\{index}]", ["rawBytes"]).require_bytes("rawBytes"))
      guard !certificates.is_empty() else {
        raise Shape(chain.at("certificates"), "the chain is empty")
      }
      Certificate(certificates[0])
    }
    _ => {
      let certificate = material.require_object("certificate", ["rawBytes"])
      Certificate(certificate.require_bytes("rawBytes"))
    }
  }
}

///|
fn read_envelope(envelope : Fields) -> Envelope raise Shape {
  let signatures = envelope
    .array("signatures")
    .mapi((index, json) => fields(json, "\{envelope.at("signatures")}[\{index}]", ["sig", "keyid"]).require_bytes("sig"))
  {
    payload: envelope.require_bytes("payload"),
    payload_type: envelope.require_string("payloadType"),
    signatures,
  }
}

///|
fn read_message(message : Fields) -> Content raise Shape {
  let digest = message.require_object("messageDigest", ["algorithm", "digest"])
  Message(
    algorithm=digest.enum_name("algorithm", hash_algorithm_names).unwrap_or("HASH_ALGORITHM_UNSPECIFIED"),
    digest=digest.require_bytes("digest"),
    signature=message.require_bytes("signature"),
  )
}

///|
fn read_entry(json : Json, path : String, version : BundleVersion) -> LogEntry raise Shape {
  let entry = fields(json, path, [
    "logIndex", "logId", "kindVersion", "integratedTime", "inclusionPromise", "inclusionProof",
    "canonicalizedBody",
  ])
  let log_index = entry.int64("logIndex")
  guard log_index >= 0L else { raise Shape(entry.at("logIndex"), "negative log index") }
  let log_id = entry.require_object("logId", ["keyId"]).require_bytes("keyId")
  let kind_version = entry.require_object("kindVersion", ["kind", "version"])
  let promise = match entry.object("inclusionPromise", ["signedEntryTimestamp"]) {
    Some(promise) => Some(promise.require_bytes("signedEntryTimestamp"))
    None => None
  }
  let proof = match entry.object("inclusionProof", ["logIndex", "rootHash", "treeSize", "hashes", "checkpoint"]) {
    Some(proof) => {
      let checkpoint = proof.require_object("checkpoint", ["envelope"]).require_string("envelope")
      let hashes = proof
        .array("hashes")
        .mapi((index, item) => match item {
          String(text) =>
            @encoding.decode_base64(text) catch {
              _ => raise Shape("\{proof.at("hashes")}[\{index}]", "not base64")
            }
          _ => raise Shape("\{proof.at("hashes")}[\{index}]", "expected a string")
        })
      Some({
        log_index: proof.int64("logIndex"),
        root_hash: proof.require_bytes("rootHash"),
        tree_size: proof.int64("treeSize"),
        hashes,
        checkpoint,
      })
    }
    None => None
  }
  if version == V0_1 {
    guard promise is Some(_) else {
      raise Shape(entry.at("inclusionPromise"), "a v0.1 bundle requires an inclusion promise")
    }
  } else {
    guard proof is Some(_) else {
      raise Shape(entry.at("inclusionProof"), "a v0.2 or later bundle requires an inclusion proof")
    }
  }
  {
    log_index,
    log_id,
    kind: kind_version.require_string("kind"),
    version: kind_version.require_string("version"),
    integrated_time: entry.int64("integratedTime"),
    promise,
    proof,
    body: entry.require_bytes("canonicalizedBody"),
  }
}

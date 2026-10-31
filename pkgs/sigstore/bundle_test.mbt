///|
let morphir_bundle : String = "morphir-rust-provider-snapshot-0.2.0.sigstore.json"

///|
/// The JSON value at a dotted path; a number step indexes an array. The value
/// shares its objects and arrays with `json`, so a change to it changes `json`.
fn find(json : Json, path : String) -> Json raise {
  let mut at = json
  for step in path.split(".") {
    at = match at {
      Object(map) =>
        match map.get(step.to_owned()) {
          Some(next) => next
          None => fail("no \{step} in \{path}")
        }
      Array(items) => {
        let index = @string.parse_int(step)
        guard index >= 0 && index < items.length() else { fail("no \{step} in \{path}") }
        items[index]
      }
      _ => fail("\{step} of \{path} is not in an object or array")
    }
  }
  at
}

///|
fn object_at(json : Json, path : String) -> Map[String, Json] raise {
  guard find(json, path) is Object(map) else { fail("\{path} is not an object") }
  map
}

///|
fn array_at(json : Json, path : String) -> Array[Json] raise {
  guard find(json, path) is Array(items) else { fail("\{path} is not an array") }
  items
}

///|
fn text_at(json : Json, path : String) -> String raise {
  guard find(json, path) is String(text) else { fail("\{path} is not a string") }
  text
}

///|
/// Set the field `key` of the object at `path`; an empty path is the root.
fn set_field(json : Json, path : String, key : String, value : Json) -> Unit raise {
  let map = if path.is_empty() {
    guard json is Object(map) else { fail("the root is not an object") }
    map
  } else {
    object_at(json, path)
  }
  map[key] = value
}

///|
/// Remove the field `key` of the object at `path`; an empty path is the root.
fn remove_field(json : Json, path : String, key : String) -> Unit raise {
  let map = if path.is_empty() {
    guard json is Object(map) else { fail("the root is not an object") }
    map
  } else {
    object_at(json, path)
  }
  guard map.contains(key) else { fail("no \{key} in \{path}") }
  map.remove(key)
}

///|
/// The base64 text with one bit of byte `index` changed.
fn flip_base64(text : String, index : Int) -> String raise {
  let bytes = @encoding.decode_base64(text).to_array()
  bytes[index] = (bytes[index].to_int() ^ 1).to_byte()
  @encoding.encode_base64(Bytes::from_array(bytes))
}

///|
/// A copy of a JSON value.
fn copy_json(json : Json) -> Json raise {
  @json.parse(json.stringify())
}

///|
/// The morphir-rust bundle as a JSON document that a test can change.
fn morphir_document() -> Json raise {
  @json.parse(fixture(@fixtures.github, morphir_bundle))
}

///|
/// A conformance bundle as a JSON document that a test can change.
fn conformance_document(name : String) -> Json raise {
  @json.parse(fixture(@fixtures.conformance, "\{name}/bundle.sigstore.json"))
}

///|
/// The error of a bundle parse, as `field: rule`, or `unsupported <type>`;
/// `None` when the parse succeeds.
fn bundle_error(text : String) -> String? {
  try @sigstore.Bundle::parse(text) catch {
    UnsupportedBundleMediaType(media_type) => Some("unsupported \{media_type}")
    InvalidBundle(field~, rule~) => Some("\{field}: \{rule}")
  } noraise {
    _ => None
  }
}

///|
fn document_error(json : Json) -> String? {
  bundle_error(json.stringify())
}

///|
test "scenario: each media type" {
  let cases = [
    ("happy-path-v0.1", "V0_1"),
    ("happy-path-v0.2", "V0_2"),
    ("happy-path-v0.3", "V0_3"),
    ("happy-path-v0.3-new-mediaType", "V0_3"),
  ]
  for case in cases {
    let bundle = @sigstore.Bundle::parse(
      fixture(@fixtures.conformance, "\{case.0}/bundle.sigstore.json"),
    )
    let version = match bundle.version() {
      V0_1 => "V0_1"
      V0_2 => "V0_2"
      V0_3 => "V0_3"
    }
    assert_eq(version, case.1, msg=case.0)
  }
  assert_true(
    @sigstore.Bundle::parse(fixture(@fixtures.github, morphir_bundle)).version() is V0_3,
  )
}

///|
test "each media type form gives its version" {
  let doc = morphir_document()
  let forms = [
    "application/vnd.dev.sigstore.bundle+json;version=0.2",
    "application/vnd.dev.sigstore.bundle+json;version=0.3",
    "application/vnd.dev.sigstore.bundle.v0.3+json",
  ]
  for form in forms {
    set_field(doc, "", "mediaType", Json::string(form))
    assert_eq(document_error(doc), None, msg=form)
  }
}

///|
test "scenario: unknown media type" {
  let doc = morphir_document()
  let refused = [
    "application/vnd.dev.sigstore.bundle.v0.4+json", "application/vnd.dev.sigstore.bundle+json;version=0.4",
    "application/vnd.dev.sigstore.bundle+json", "application/json",
  ]
  for media_type in refused {
    set_field(doc, "", "mediaType", Json::string(media_type))
    assert_eq(document_error(doc), Some("unsupported \{media_type}"))
  }
  let err = try @sigstore.Bundle::parse(doc.stringify()) catch {
    err => err
  } noraise {
    _ => fail("parsed")
  }
  assert_true(err.message().contains("application/json"), msg=err.message())
}

///|
test "scenario: unknown field" {
  let doc = morphir_document()
  set_field(doc, "verificationMaterial", "extra", Json::string("x"))
  assert_eq(document_error(doc), Some("verificationMaterial.extra: unknown field"))
  let err = try @sigstore.Bundle::parse(doc.stringify()) catch {
    err => err
  } noraise {
    _ => fail("parsed")
  }
  assert_eq(err.message(), "Invalid bundle field verificationMaterial.extra: unknown field")
}

///|
test "protobuf JSON: an unknown field at the root and in an entry fails" {
  let root = morphir_document()
  set_field(root, "", "extra", Json::boolean(true))
  assert_eq(document_error(root), Some("extra: unknown field"))
  let entry = morphir_document()
  set_field(entry, "verificationMaterial.tlogEntries.0.inclusionProof", "extra", Json::number(1.0))
  assert_eq(
    document_error(entry),
    Some("verificationMaterial.tlogEntries[0].inclusionProof.extra: unknown field"),
  )
}

///|
test "protobuf JSON: the proto field name is accepted" {
  let doc = morphir_document()
  let media_type = find(doc, "mediaType")
  remove_field(doc, "", "mediaType")
  set_field(doc, "", "media_type", media_type)
  let material = find(doc, "verificationMaterial")
  remove_field(doc, "", "verificationMaterial")
  set_field(doc, "", "verification_material", material)
  let entry = "verification_material.tlogEntries.0"
  let body = find(doc, "\{entry}.canonicalizedBody")
  remove_field(doc, entry, "canonicalizedBody")
  set_field(doc, entry, "canonicalized_body", body)
  assert_eq(document_error(doc), None)
  let case = morphir_case()
  assert_eq(outcome(verify_document(doc, case_policy(case))), "pass")
}

///|
test "protobuf JSON: a field given in both spellings fails" {
  let doc = morphir_document()
  set_field(doc, "", "media_type", find(doc, "mediaType"))
  assert_eq(document_error(doc), Some("mediaType: field is repeated"))
}

///|
test "protobuf JSON: a duplicate key fails" {
  let text = fixture(@fixtures.github, morphir_bundle).replace(
    old="{\"mediaType\":",
    new="{\"mediaType\":\"x\",\"mediaType\":",
  )
  guard bundle_error(text) is Some(error) else { fail("parsed") }
  assert_true(error.has_prefix(": not JSON"), msg=error)
}

///|
test "protobuf JSON: null is an absent field" {
  let doc = morphir_document()
  set_field(doc, "", "messageSignature", Json::null())
  set_field(doc, "verificationMaterial", "publicKey", Json::null())
  set_field(doc, "verificationMaterial", "x509CertificateChain", Json::null())
  assert_eq(document_error(doc), None)
  let case = morphir_case()
  assert_eq(outcome(verify_document(doc, case_policy(case))), "pass")
  // A required field given as null is absent.
  set_field(doc, "", "mediaType", Json::null())
  assert_eq(document_error(doc), Some("mediaType: field is required"))
}

///|
test "protobuf JSON: int64 as a string and as a number" {
  let text = fixture(@fixtures.github, morphir_bundle)
  let numbers = text
    .replace(old="\"logIndex\":\"3275146211\"", new="\"logIndex\":3275146211")
    .replace(old="\"integratedTime\":\"1792133282\"", new="\"integratedTime\":1792133282")
    .replace(old="\"treeSize\":\"3153242266\"", new="\"treeSize\":3153242266")
  assert_true(numbers != text)
  let case = morphir_case()
  let verdict = @sigstore.verify(
    @sigstore.Bundle::parse(numbers),
    @sigstore.ArtifactDigest::parse(case.digest),
    @sigstore.TrustedRoot::public_good(),
    case_policy(case),
    now=later,
  )
  guard verdict is Verified(facts) else { fail(outcome(verdict)) }
  assert_eq(facts.log_index, 3275146211L)
  assert_eq(facts.integrated_time.unix_seconds(), 1792133282L)
  // A number that is not an integer, and a text that is not one, fail.
  let fraction = text.replace(old="\"logIndex\":\"3275146211\"", new="\"logIndex\":3275146211.5")
  assert_eq(
    bundle_error(fraction),
    Some("verificationMaterial.tlogEntries[0].logIndex: not an integer"),
  )
  let word = text.replace(old="\"logIndex\":\"3275146211\"", new="\"logIndex\":\"12a\"")
  assert_eq(bundle_error(word), Some("verificationMaterial.tlogEntries[0].logIndex: not an integer"))
  let negative = text.replace(old="\"logIndex\":\"3275146211\"", new="\"logIndex\":\"-1\"")
  assert_eq(
    bundle_error(negative),
    Some("verificationMaterial.tlogEntries[0].logIndex: negative log index"),
  )
}

///|
test "protobuf JSON: bytes accept URL-safe base64" {
  let doc = morphir_document()
  let path = "verificationMaterial.certificate"
  let raw = text_at(doc, "\{path}.rawBytes")
  assert_true(raw.contains("+") && raw.contains("/"))
  let url_safe = raw.replace_all(old="+", new="-").replace_all(old="/", new="_")
  set_field(doc, path, "rawBytes", Json::string(url_safe))
  assert_eq(document_error(doc), None)
  assert_eq(outcome(verify_document(doc, case_policy(morphir_case()))), "pass")
  set_field(doc, path, "rawBytes", Json::string("not base64!"))
  assert_eq(document_error(doc), Some("verificationMaterial.certificate.rawBytes: not base64"))
}

///|
test "protobuf JSON: at most 32 tlog entries" {
  fn with_entries(count : Int) -> Json raise {
    let doc = morphir_document()
    let entries = array_at(doc, "verificationMaterial.tlogEntries")
    let first = entries[0]
    for _ in 1..<count {
      entries.push(copy_json(first))
    }
    assert_eq(entries.length(), count)
    doc
  }

  assert_eq(document_error(with_entries(32)), None)
  assert_eq(
    document_error(with_entries(33)),
    Some("verificationMaterial.tlogEntries: more than 32 entries"),
  )
}

///|
test "protobuf JSON: v0.1 needs an inclusion promise, not a proof" {
  let name = "happy-path-v0.1"
  let without_proof = conformance_document(name)
  remove_field(without_proof, "verificationMaterial.tlogEntries.0", "inclusionProof")
  assert_eq(document_error(without_proof), None)
  // A v0.1 bundle without a proof passes on its signed entry timestamp alone.
  assert_eq(verify_conformance_document(name, without_proof), "pass")
  let without_promise = conformance_document(name)
  remove_field(without_promise, "verificationMaterial.tlogEntries.0", "inclusionPromise")
  assert_eq(
    document_error(without_promise),
    Some(
      "verificationMaterial.tlogEntries[0].inclusionPromise: a v0.1 bundle requires an inclusion promise",
    ),
  )
}

///|
test "protobuf JSON: v0.2 and later need an inclusion proof" {
  let v2 = conformance_document("happy-path-v0.2")
  remove_field(v2, "verificationMaterial.tlogEntries.0", "inclusionProof")
  let rule = "verificationMaterial.tlogEntries[0].inclusionProof: a v0.2 or later bundle requires an inclusion proof"
  assert_eq(document_error(v2), Some(rule))
  let v3 = morphir_document()
  remove_field(v3, "verificationMaterial.tlogEntries.0", "inclusionProof")
  assert_eq(document_error(v3), Some(rule))
}

///|
test "protobuf JSON: v0.3 refuses x509CertificateChain" {
  let doc = morphir_document()
  let certificate = find(doc, "verificationMaterial.certificate")
  remove_field(doc, "verificationMaterial", "certificate")
  set_field(
    doc,
    "verificationMaterial",
    "x509CertificateChain",
    Json::object({ "certificates": Json::array([certificate]) }),
  )
  assert_eq(
    document_error(doc),
    Some("verificationMaterial.x509CertificateChain: a v0.3 bundle must use certificate"),
  )
  // A v0.2 bundle can give the leaf in a chain.
  set_field(
    doc,
    "",
    "mediaType",
    Json::string("application/vnd.dev.sigstore.bundle+json;version=0.2"),
  )
  assert_eq(document_error(doc), None)
  assert_eq(outcome(verify_document(doc, case_policy(morphir_case()))), "pass")
  // An empty chain fails.
  set_field(doc, "verificationMaterial.x509CertificateChain", "certificates", Json::array([]))
  assert_eq(
    document_error(doc),
    Some("verificationMaterial.x509CertificateChain.certificates: the chain is empty"),
  )
}

///|
test "protobuf JSON: exactly one key material" {
  let both = morphir_document()
  set_field(
    both,
    "verificationMaterial",
    "publicKey",
    Json::object({ "hint": Json::string("abc") }),
  )
  assert_eq(
    document_error(both),
    Some(
      "verificationMaterial: exactly one of publicKey, x509CertificateChain and certificate is required",
    ),
  )
  let none = morphir_document()
  remove_field(none, "verificationMaterial", "certificate")
  assert_eq(document_error(none), document_error(both))
}

///|
test "protobuf JSON: messageSignature and dsseEnvelope together fail" {
  let doc = morphir_document()
  let message = conformance_document("happy-path-v0.3")
  set_field(doc, "", "messageSignature", find(message, "messageSignature"))
  assert_eq(
    document_error(doc),
    Some(": exactly one of dsseEnvelope and messageSignature is required"),
  )
  remove_field(doc, "", "messageSignature")
  remove_field(doc, "", "dsseEnvelope")
  assert_eq(
    document_error(doc),
    Some(": exactly one of dsseEnvelope and messageSignature is required"),
  )
}

///|
test "v0.1 and v0.2 also parse in the bundle.vX+json form" {
  for
    pair in [
      ("happy-path-v0.1", "application/vnd.dev.sigstore.bundle+json;version=0.1", "application/vnd.dev.sigstore.bundle.v0.1+json"),
      ("happy-path-v0.2", "application/vnd.dev.sigstore.bundle+json;version=0.2", "application/vnd.dev.sigstore.bundle.v0.2+json"),
    ] {
    let (name, old, new) = pair
    let text = fixture(@fixtures.conformance, "\{name}/bundle.sigstore.json")
    assert_true(text.contains(old), msg=name)
    let bundle = @sigstore.Bundle::parse(text.replace(old~, new~))
    assert_eq(bundle.version(), @sigstore.Bundle::parse(text).version())
  }
}

///|
fn base64(text : String) -> Bytes raise {
  @encoding.decode_base64(text)
}

///|
fn concat(parts : Array[BytesView]) -> Bytes {
  let out : Array[Byte] = []
  for part in parts {
    for byte in part {
      out.push(byte)
    }
  }
  Bytes::from_array(out)
}

///|
/// The text of a fixture file in a generated fixture group.
fn fixture(group : Array[(String, String)], path : String) -> String {
  for file in group {
    if file.0 == path {
      return file.1
    }
  }
  abort("no fixture \{path}")
}

///|
/// The JSON value at a path of object keys and array indexes.
fn json_at(json : Json, path : Array[String]) -> Json raise {
  let mut at = json
  for step in path {
    at = match at {
      Object(object) =>
        match object.get(step) {
          Some(next) => next
          None => fail("no \{step}")
        }
      Array(items) => items[@string.parse_int(step)]
      _ => fail("cannot step into \{step}")
    }
  }
  at
}

///|
fn text_at(json : Json, path : Array[String]) -> String raise {
  guard json_at(json, path) is String(text) else { fail("not text") }
  text
}

///|
/// The leaf certificate of a bundle with a `certificate` field.
fn bundle_leaf(text : String) -> @x509.Certificate raise {
  let bundle = @json.parse(text)
  @x509.parse(
    base64(text_at(bundle, ["verificationMaterial", "certificate", "rawBytes"])),
  )
}

///|
let github_bundles : Array[String] = [
  "morphir-rust-provider-snapshot-0.2.0.sigstore.json", "cli-2.50.0.sigstore.json",
  "cli-2.83.0.sigstore.json",
]

///|
/// The public-good `sigstore-intermediate` (certificateAuthorities[1]).
let intermediate_base64 : String = "MIICGjCCAaGgAwIBAgIUALnViVfnU0brJasmRkHrn/UnfaQwCgYIKoZIzj0EAwMwKjEVMBMGA1UEChMMc2lnc3RvcmUuZGV2MREwDwYDVQQDEwhzaWdzdG9yZTAeFw0yMjA0MTMyMDA2MTVaFw0zMTEwMDUxMzU2NThaMDcxFTATBgNVBAoTDHNpZ3N0b3JlLmRldjEeMBwGA1UEAxMVc2lnc3RvcmUtaW50ZXJtZWRpYXRlMHYwEAYHKoZIzj0CAQYFK4EEACIDYgAE8RVS/ysH+NOvuDZyPIZtilgUF9NlarYpAd9HP1vBBH1U5CV77LSS7s0ZiH4nE7Hv7ptS6LvvR/STk798LVgMzLlJ4HeIfF3tHSaexLcYpSASr1kS0N/RgBJz/9jWCiXno3sweTAOBgNVHQ8BAf8EBAMCAQYwEwYDVR0lBAwwCgYIKwYBBQUHAwMwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU39Ppz1YkEZb5qNjpKFWixi4YZD8wHwYDVR0jBBgwFoAUWMAeX5FFpWapesyQoZMi0CrFxfowCgYIKoZIzj0EAwMDZwAwZAIwPCsQK4DYiZYDPIaDi5HFKnfxXx6ASSVmERfsynYBiX2X6SJRnZU84/9DZdnFvvxmAjBOt6QpBlc4J/0DxvkTCqpclvziL6BCCPnjdlIB3Pu3BxsPmygUY7Ii2zbdCdliiow="

///|
/// The public-good CT log (ctlogs[1], `ctfe.sigstore.dev/2022`).
let ct_log_id : String = "3T0wasbHETJjGR4cmWc3AqJKXrjePK3/h4pygC8p7o4="

///|
let ct_key : String = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEiPSlFi0CmFTfEjCUqF9HuCEcYXNKAaYalIJmBZ8yyezPjTqhxrKBpMnaocVtLJBI1eM3uXnQzQGAJdJ4gs9Fyw=="

///|
/// The public-good Rekor v1 key, which is not a CT log key.
let rekor_key : String = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE2G2Y+2tabdTV5BcGiBIx0a9fAFwrkBbmLSGtks4L3qX6yYY0zufBnhC8Ur/iy55GhWP/9A/bY2LhC30M9+RYtw=="

///|
/// The SCT list extension value of a certificate.
fn sct_extension(certificate : @x509.Certificate) -> Bytes raise {
  guard certificate.extension(@x509.SCT_LIST_OID) is Some(extension) else {
    fail("no SCT list")
  }
  extension.value
}

///|
/// The rule of a `BadSct`, or the number of SCTs.
fn list_outcome(value : BytesView) -> String {
  try {
    "ok \{@sct.parse_list(value).length()}"
  } catch {
    BadSct(rule) => rule
  }
}

///|
/// An extension value around a TLS SCT list `content`.
fn octets(content : BytesView) -> Bytes {
  @der.encode(@der.OCTET_STRING, content)
}

///|
test "the SCTs of the real GitHub leaf certificates verify" {
  let intermediate = @x509.parse(base64(intermediate_base64))
  let key = @signature.PublicKey::from_spki(base64(ct_key))
  assert_eq(@signature.sha256(key.spki), base64(ct_log_id))
  let rekor = @signature.PublicKey::from_spki(base64(rekor_key))
  for bundle in github_bundles {
    let leaf = bundle_leaf(fixture(@fixtures.github, bundle))
    let scts = @sct.parse_list(sct_extension(leaf))
    assert_eq(scts.length(), 1, msg=bundle)
    let sct = scts[0]
    assert_eq(sct.log_id, base64(ct_log_id), msg=bundle)
    assert_eq(sct.hash_algorithm, 4, msg=bundle)
    assert_eq(sct.signature_algorithm, 3, msg=bundle)
    assert_eq(sct.extensions, b"", msg=bundle)
    // The log saw the certificate within its validity.
    assert_true(leaf.valid_at(sct.timestamp / 1000L), msg=bundle)
    let tbs = leaf.tbs_without(@x509.SCT_LIST_OID)
    assert_true(sct.verify(key, intermediate.spki, tbs), msg=bundle)
    // The full TBS, another issuer key, or another log key fail.
    assert_false(sct.verify(key, intermediate.spki, leaf.tbs), msg=bundle)
    assert_false(sct.verify(key, leaf.spki, tbs), msg=bundle)
    assert_false(sct.verify(rekor, intermediate.spki, tbs), msg=bundle)
  }
}

///|
test "the morphir-rust SCT timestamp and signed data" {
  let intermediate = @x509.parse(base64(intermediate_base64))
  let leaf = bundle_leaf(
    fixture(
      @fixtures.github, "morphir-rust-provider-snapshot-0.2.0.sigstore.json",
    ),
  )
  let sct = @sct.parse_list(sct_extension(leaf))[0]
  // Oct 16 06:48:02.023 2026 GMT.
  assert_eq(sct.timestamp, 1792133282023L)
  let tbs = leaf.tbs_without(@x509.SCT_LIST_OID)
  let data = sct.signed_data(intermediate.spki, tbs)
  // Version, signature type, timestamp, entry type, issuer key hash, the
  // TBS with a 3-byte length, and no extensions.
  let n = tbs.length()
  assert_eq(data.length(), 2 + 8 + 2 + 32 + 3 + n + 2)
  assert_eq(data[0:2].to_owned(), b"\x00\x00")
  assert_eq(
    @encoding.encode_hex(data[2:10]),
    @encoding.encode_hex(b"\x00\x00\x01\xa1\x43\x77\xb8\xe7"),
  )
  assert_eq(data[10:12].to_owned(), b"\x00\x01")
  assert_eq(data[12:44].to_owned(), @signature.sha256(intermediate.spki))
  assert_eq(
    data[44:47].to_owned(),
    Bytes::from_array([
      (n >> 16).to_byte(),
      ((n >> 8) & 0xff).to_byte(),
      (n & 0xff).to_byte(),
    ]),
  )
  assert_eq(data[47:47 + n].to_owned(), tbs)
  assert_eq(data[47 + n:].to_owned(), b"\x00\x00")
}

///|
test "an SCT with extensions verifies" {
  let root = @json.parse(
    fixture(
      @fixtures.conformance, "bundle-with-sct-with-extensions/trusted_root.json",
    ),
  )
  let leaf = bundle_leaf(
    fixture(
      @fixtures.conformance, "bundle-with-sct-with-extensions/bundle.sigstore.json",
    ),
  )
  let issuer = @x509.parse(
    base64(
      text_at(root, [
        "certificateAuthorities", "0", "certChain", "certificates", "0", "rawBytes",
      ]),
    ),
  )
  let key = @signature.PublicKey::from_spki(
    base64(text_at(root, ["ctlogs", "0", "publicKey", "rawBytes"])),
  )
  let scts = @sct.parse_list(sct_extension(leaf))
  assert_eq(scts.length(), 1)
  let sct = scts[0]
  assert_eq(
    sct.log_id,
    base64(text_at(root, ["ctlogs", "0", "logId", "keyId"])),
  )
  assert_eq(sct.extensions, b"\x00\x00\x05\x00\x00\x00\x00\x70")
  let tbs = leaf.tbs_without(@x509.SCT_LIST_OID)
  let data = sct.signed_data(issuer.spki, tbs)
  assert_eq(
    data[data.length() - 10:].to_owned(),
    b"\x00\x08\x00\x00\x05\x00\x00\x00\x00\x70",
  )
  assert_true(sct.verify(key, issuer.spki, tbs))
}

///|
/// The TLS list inside the morphir-rust SCT extension.
fn morphir_list() -> Bytes raise {
  let leaf = bundle_leaf(
    fixture(
      @fixtures.github, "morphir-rust-provider-snapshot-0.2.0.sigstore.json",
    ),
  )
  @der.parse_tag(sct_extension(leaf), @der.OCTET_STRING).content.to_owned()
}

///|
/// `bytes` with the byte at `at` changed by `xor`.
fn flip(bytes : Bytes, at : Int, xor : Byte) -> Bytes {
  let out = bytes.to_array()
  out[at] = out[at] ^ xor
  Bytes::from_array(out)
}

///|
test "a changed SCT does not verify" {
  let intermediate = @x509.parse(base64(intermediate_base64))
  let leaf = bundle_leaf(
    fixture(
      @fixtures.github, "morphir-rust-provider-snapshot-0.2.0.sigstore.json",
    ),
  )
  let key = @signature.PublicKey::from_spki(base64(ct_key))
  let tbs = leaf.tbs_without(@x509.SCT_LIST_OID)
  let list = morphir_list()
  // The list: length (2), SCT length (2), version (1), log ID (32),
  // timestamp (8), extensions (2), hash (1), signature algorithm (1),
  // signature length (2) and the DER signature.
  let timestamp_end = 2 + 2 + 1 + 32 + 8
  let hash_at = timestamp_end + 2
  let original = @sct.parse_list(octets(list))[0]
  assert_true(original.verify(key, intermediate.spki, tbs))
  let later = @sct.parse_list(octets(flip(list, timestamp_end - 1, b'\x01')))[0]
  assert_eq(later.timestamp, original.timestamp ^ 1L)
  assert_false(later.verify(key, intermediate.spki, tbs))
  // The last byte of s; the signature stays strict DER.
  let changed = @sct.parse_list(octets(flip(list, list.length() - 1, b'\x01')))[0]
  assert_eq(changed.signature.length(), original.signature.length())
  assert_false(changed.verify(key, intermediate.spki, tbs))
  // Another hash (SHA-384 = 5) or signature algorithm (RSA = 1).
  let sha384 = @sct.parse_list(octets(flip(list, hash_at, b'\x01')))[0]
  assert_eq(sha384.hash_algorithm, 5)
  assert_false(sha384.verify(key, intermediate.spki, tbs))
  let rsa = @sct.parse_list(octets(flip(list, hash_at + 1, b'\x02')))[0]
  assert_eq(rsa.signature_algorithm, 1)
  assert_false(rsa.verify(key, intermediate.spki, tbs))
  // Another log ID still parses; the caller matches it to a log.
  let other_log = @sct.parse_list(octets(flip(list, 5, b'\x01')))[0]
  assert_true(other_log.log_id != original.log_id)
}

///|
test "SCT list framing rules" {
  let list = morphir_list()
  assert_eq(list_outcome(octets(list)), "ok 1")
  // Not an OCTET STRING, and trailing bytes after it.
  assert_eq(
    list_outcome(@der.encode(@der.BIT_STRING, list)),
    "the extension is not an OCTET STRING",
  )
  assert_eq(
    list_outcome(concat([octets(list), b"\x00"])),
    "the extension is not an OCTET STRING",
  )
  // Truncated by one byte, and one trailing byte after the list.
  assert_eq(list_outcome(octets(list[:list.length() - 1])), "truncated")
  assert_eq(list_outcome(octets(concat([list, b"\x00"]))), "trailing bytes")
  // An empty input.
  assert_eq(list_outcome(octets(b"")), "truncated")
  assert_eq(list_outcome(octets(b"\x00")), "truncated")
  // One trailing byte inside the SCT, with both lengths grown by one.
  let grown = concat([list, b"\x00"]).to_array()
  for at in [1, 3] {
    grown[at] = grown[at] + b'\x01'
  }
  assert_eq(
    list_outcome(octets(Bytes::from_array(grown))),
    "trailing bytes in an SCT",
  )
  // The SCT is one byte shorter than its length says.
  let shrunk = list[:list.length() - 1].to_owned().to_array()
  shrunk[1] = shrunk[1] - b'\x01'
  assert_eq(list_outcome(octets(Bytes::from_array(shrunk))), "truncated")
  // Version 2.
  assert_eq(list_outcome(octets(flip(list, 4, b'\x01'))), "not a v1 SCT")
  // Two SCTs.
  let sct = list[2:]
  let length = 2 * sct.length()
  let two = concat([
    Bytes::from_array([(length >> 8).to_byte(), (length & 0xff).to_byte()]),
    sct,
    sct,
  ])
  assert_eq(list_outcome(octets(two)), "ok 2")
}

///|
test "an empty SCT list is refused" {
  // OCTET STRING { u16 list length 0 }.
  let refused = try {
    ignore(@sct.parse_list(b"\x04\x02\x00\x00"))
    None
  } catch {
    BadSct(rule) => Some(rule)
  }
  assert_eq(refused, Some("the SCT list is empty"))
}

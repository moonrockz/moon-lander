///|
fn hex(text : String) -> Bytes raise {
  @encoding.decode_hex(text)
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
fn member_text(object : Map[String, Json], name : String) -> String raise {
  guard object.get(name) is Some(String(value)) else { fail("no text \{name}") }
  value
}

///|
fn member_int(object : Map[String, Json], name : String) -> Int raise {
  guard object.get(name) is Some(Number(value, ..)) else { fail("no number \{name}") }
  value.to_int()
}

///|
fn member_array(object : Map[String, Json], name : String) -> Array[Json] raise {
  guard object.get(name) is Some(Array(value)) else { fail("no array \{name}") }
  value
}

///|
fn as_object(json : Json) -> Map[String, Json] raise {
  guard json is Object(object) else { fail("not an object") }
  object
}

///|
/// The outcome of `PublicKey::from_spki` as text, so a test can compare it.
fn key_outcome(spki : BytesView) -> String {
  try {
    let key = @signature.PublicKey::from_spki(spki)
    "ok \{key.kind.hash() is Sha256}"
  } catch {
    UnsupportedKey(kind) => "UnsupportedKey(\{kind})"
    BadKey(rule) => "BadKey(\{rule})"
  }
}

///|
/// One Wycheproof test file: the counts of valid, invalid and acceptable
/// cases. Every case must give its expected result.
struct WycheproofCount {
  valid : Int
  invalid : Int
  acceptable : Int
} derive(Debug)

///|
fn run_wycheproof(path : String, p1363 : Bool) -> WycheproofCount raise {
  let root = as_object(@json.parse(fixture(@fixtures.wycheproof, path)))
  let mut valid = 0
  let mut invalid = 0
  let mut acceptable = 0
  for group_json in member_array(root, "testGroups") {
    let group = as_object(group_json)
    let key = @signature.PublicKey::from_spki(
      hex(member_text(group, "publicKeyDer")),
    )
    let hash : @signature.HashAlgorithm = match member_text(group, "sha") {
      "SHA-256" => Sha256
      "SHA-384" => Sha384
      other => fail("unexpected hash \{other}")
    }
    assert_eq(key.kind.hash(), hash)
    for case_json in member_array(group, "tests") {
      let case = as_object(case_json)
      let id = member_int(case, "tcId")
      let message = hex(member_text(case, "msg"))
      let signature = hex(member_text(case, "sig"))
      let verified = if p1363 {
        key.verify_digest_raw(@signature.digest(hash, message), signature)
      } else {
        key.verify(message, signature)
      }
      match member_text(case, "result") {
        "valid" => {
          valid += 1
          assert_true(verified, msg="\{path} tcId \{id} must verify")
        }
        "invalid" => {
          invalid += 1
          assert_false(verified, msg="\{path} tcId \{id} must not verify")
        }
        "acceptable" => acceptable += 1
        other => fail("\{path} tcId \{id}: unknown result \{other}")
      }
    }
  }
  assert_eq(valid + invalid + acceptable, member_int(root, "numberOfTests"))
  { valid, invalid, acceptable }
}

///|
test "Wycheproof P-256 SHA-256 DER signatures" {
  debug_inspect(
    run_wycheproof("ecdsa_secp256r1_sha256_test.json", false),
    content="{ valid: 174, invalid: 310, acceptable: 0 }",
  )
}

///|
test "Wycheproof P-384 SHA-384 DER signatures" {
  debug_inspect(
    run_wycheproof("ecdsa_secp384r1_sha384_test.json", false),
    content="{ valid: 194, invalid: 310, acceptable: 0 }",
  )
}

///|
test "Wycheproof P-256 SHA-256 P1363 signatures" {
  debug_inspect(
    run_wycheproof("ecdsa_secp256r1_sha256_p1363_test.json", true),
    content="{ valid: 173, invalid: 89, acceptable: 0 }",
  )
}

///|
test "Wycheproof P-384 SHA-384 P1363 signatures" {
  debug_inspect(
    run_wycheproof("ecdsa_secp384r1_sha384_p1363_test.json", true),
    content="{ valid: 193, invalid: 87, acceptable: 0 }",
  )
}

///|
test "digests of the SHA-2 family" {
  let abc = b"abc"
  assert_eq(
    @encoding.encode_hex(@signature.sha256(abc)),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  assert_eq(@signature.digest(Sha256, abc), @signature.sha256(abc))
  assert_eq(
    @encoding.encode_hex(@signature.digest(Sha384, abc)),
    "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7",
  )
  assert_eq(
    @encoding.encode_hex(@signature.digest(Sha512, abc)),
    "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f",
  )
}

///|
test "DER signatures convert to fixed-width r and s" {
  // r = 1 and s = 2 are padded on the left.
  let one = @signature.der_signature_to_raw(hex("3006020101020102"), 32)
  assert_eq(
    one.map(b => @encoding.encode_hex(b)),
    Some("00".repeat(31) + "01" + "00".repeat(31) + "02"),
  )
  // A sign byte before a high bit is required and removed.
  let high = @signature.der_signature_to_raw(hex("30080202008002020081"), 2)
  assert_eq(high.map(b => @encoding.encode_hex(b)), Some("00800081"))
  // r and s of exactly the curve width, with sign bytes.
  let wide = "0221" + "00" + "ff".repeat(32)
  let both = @signature.der_signature_to_raw(hex("3046" + wide + wide), 32)
  assert_eq(both.map(b => @encoding.encode_hex(b)), Some("ff".repeat(64)))
  // 32 bytes without the sign byte would be negative.
  let negative = "0220" + "ff".repeat(32)
  assert_eq(
    @signature.der_signature_to_raw(hex("3044" + negative + negative), 32),
    None,
  )
  // A value 33 bytes wide is wider than the curve.
  let too_wide = "0221" + "01" + "00".repeat(32)
  assert_eq(
    @signature.der_signature_to_raw(hex("3026" + too_wide + "020101"), 32),
    None,
  )
  assert_eq(
    @signature.der_signature_to_raw(hex("3026020101" + too_wide), 32),
    None,
  )
  // The same value fits a wider curve.
  assert_true(
    @signature.der_signature_to_raw(hex("3026" + too_wide + "020101"), 48)
    is Some(_),
  )
}

///|
test "DER signatures that are not strict DER are refused" {
  let refused = [
    // A length in the long form when the short form fits.
    "308106020101020102",
    // A leading zero before a byte without the high bit.
    "300702020001020102", "300702010102020002",
    // Negative values.
    "3006020180020102", "3006020101020180",
    // An empty INTEGER.
    "30050200020102",
    // Trailing bytes after the SEQUENCE and inside it.
    "300602010102010200", "3009020101020102020103",
    // Only one INTEGER.
    "3003020101",
    // The wrong outer tag, and the wrong inner tag.
    "3106020101020102", "3006020101040102",
    // A truncated SEQUENCE.
    "3007020101020102", "",
  ]
  for text in refused {
    assert_eq(
      @signature.der_signature_to_raw(hex(text), 32),
      None,
      msg="\{text} must be refused",
    )
  }
}

///|
/// A P-256 SPKI around `point`, with the real DER lengths.
fn p256_spki(point : BytesView) -> Bytes raise {
  let algorithm = hex("301306072a8648ce3d020106082a8648ce3d030107")
  let bits = @der.encode(@der.BIT_STRING, concat([b"\x00", point]))
  @der.encode(@der.SEQUENCE, concat([algorithm, bits]))
}

///|
/// The key of the first P-256 Wycheproof group.
let p256_x : String = "04aaec73635726f213fb8a9e64da3b8632e41495a944d0045b522eba7240fad5"

///|
let p256_y : String = "87d9315798aaa3a5ba01775787ced05eaaf7b4e09fc81d6d1aa546e8365d525d"

///|
let p256_prime : String = "ffffffff00000001000000000000000000000000ffffffffffffffffffffffff"

///|
let p256_prime_minus_one : String = "ffffffff00000001000000000000000000000000fffffffffffffffffffffffe"

///|
test "P-256 and P-384 keys are read with their hash" {
  let spki = p256_spki(hex("04" + p256_x + p256_y))
  assert_eq(
    spki,
    hex(
      "3059301306072a8648ce3d020106082a8648ce3d030107034200" +
      "04" +
      p256_x +
      p256_y,
    ),
  )
  let key = @signature.PublicKey::from_spki(spki)
  assert_true(key.kind is EcdsaP256)
  assert_eq(key.kind.hash(), Sha256)
  assert_eq(key.spki, spki)
  // The public-good Rekor key.
  let rekor = @signature.PublicKey::from_spki(
    @encoding.decode_base64(
      "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE2G2Y+2tabdTV5BcGiBIx0a9fAFwrkBbmLSGtks4L3qX6yYY0zufBnhC8Ur/iy55GhWP/9A/bY2LhC30M9+RYtw==",
    ),
  )
  assert_true(rekor.kind is EcdsaP256)
  // The first P-384 Wycheproof key.
  let root = as_object(
    @json.parse(
      fixture(@fixtures.wycheproof, "ecdsa_secp384r1_sha384_test.json"),
    ),
  )
  let group = as_object(member_array(root, "testGroups")[0])
  let p384 = @signature.PublicKey::from_spki(
    hex(member_text(group, "publicKeyDer")),
  )
  assert_true(p384.kind is EcdsaP384)
  assert_eq(p384.kind.hash(), Sha384)
}

///|
test "points must be uncompressed, in the field and on the curve" {
  assert_eq(key_outcome(p256_spki(hex("04" + p256_x + p256_y))), "ok true")
  let shape = "BadKey(the point is not an uncompressed point of the curve)"
  let prime = "BadKey(a coordinate is not less than the field prime)"
  let curve = "BadKey(the point is not on the curve)"
  // A compressed point (y is odd).
  assert_eq(key_outcome(p256_spki(hex("03" + p256_x))), shape)
  assert_eq(key_outcome(p256_spki(hex("02" + p256_x))), shape)
  // The hybrid form and the point at infinity.
  assert_eq(key_outcome(p256_spki(hex("07" + p256_x + p256_y))), shape)
  assert_eq(key_outcome(p256_spki(hex("00"))), shape)
  // One byte short and one byte long.
  assert_eq(
    key_outcome(p256_spki(hex("04" + p256_x + p256_y[:62].to_owned()))),
    shape,
  )
  assert_eq(key_outcome(p256_spki(hex("04" + p256_x + p256_y + "00"))), shape)
  // No format byte.
  assert_eq(key_outcome(p256_spki(hex(p256_x + p256_y))), shape)
  // A P-384-sized point for a P-256 key.
  assert_eq(
    key_outcome(p256_spki(hex("04" + "00".repeat(16) + p256_x + "00".repeat(16) + p256_y))),
    shape,
  )
  // A coordinate equal to the prime is refused before the curve check;
  // p - 1 passes that rule but is not on the curve with this y.
  assert_eq(key_outcome(p256_spki(hex("04" + p256_prime + p256_y))), prime)
  assert_eq(key_outcome(p256_spki(hex("04" + p256_x + p256_prime))), prime)
  assert_eq(key_outcome(p256_spki(hex("04" + "ff".repeat(32) + p256_y))), prime)
  assert_eq(
    key_outcome(p256_spki(hex("04" + p256_prime_minus_one + p256_y))),
    curve,
  )
  // A changed y.
  let changed = p256_y[:62].to_owned() + "5e"
  assert_eq(key_outcome(p256_spki(hex("04" + p256_x + changed))), curve)
  // Zero coordinates.
  assert_eq(key_outcome(p256_spki(hex("04" + "00".repeat(64)))), curve)
}

///|
test "other key types are named" {
  // The public-good Rekor v2 key.
  assert_eq(
    key_outcome(
      @encoding.decode_base64(
        "MCowBQYDK2VwAyEAt8rlp1knGwjfbcXAYPYAkn0XiLz1x8O4t0YkEhie244=",
      ),
    ),
    "UnsupportedKey(Ed25519)",
  )
  // A 1024-bit RSA key from openssl.
  assert_eq(
    key_outcome(
      hex(
        "30819f300d06092a864886f70d010101050003818d0030818902818100c18be84d671b61f2efd827cbc114bc66c7bf4ddc7cc61fb6c6a105574a8595e20e467e4cb5be34b7c6a3eb4df0ad3f661566b65a43545eb2fa52bad176e474ac661ad1e14c2ed6175ad423133dea980e2f676f50c46a946d7a674c512b6c8bdf68e48c6675746b69f1dfd13fdfa3baf6e533032c64876de932bdef3a72282f690203010001",
      ),
    ),
    "UnsupportedKey(RSA)",
  )
  // A secp256k1 key from openssl.
  assert_eq(
    key_outcome(
      hex(
        "3056301006072a8648ce3d020106052b8104000a03420004c64b51bd720e94ce009624e93d7e668b9f7afeb7948a23f61992bb4efd9e31ff932e91e78648d1c0d12f441629dd74a85516a5c645c0fe2f1d23481f54806f82",
      ),
    ),
    "UnsupportedKey(ECDSA curve 1.3.132.0.10)",
  )
  // An unknown algorithm (Ed448) is named by its OID.
  assert_eq(
    key_outcome(hex("3043300506032b6571033a00" + "00".repeat(57))),
    "UnsupportedKey(1.3.101.113)",
  )
}

///|
test "malformed key DER is a bad key" {
  let good = p256_spki(hex("04" + p256_x + p256_y))
  let refused = [
    // Truncated, and one trailing byte.
    good[0:good.length() - 1].to_owned(),
    concat([good, b"\x00"]),
    // The outer tag is a SET.
    concat([b"\x31", good[1:]]),
    // The key is an OCTET STRING, not a BIT STRING.
    concat([good[:23], b"\x04", good[24:]]),
    // The BIT STRING has unused bits.
    concat([good[:25], b"\x01", good[26:]]),
    // Empty input.
    b"",
  ]
  for spki in refused {
    assert_true(
      key_outcome(spki).has_prefix("BadKey(malformed DER"),
      msg=@encoding.encode_hex(spki),
    )
  }
  // An ECDSA key with NULL parameters has no named curve.
  let no_curve = hex(
    "3051300b06072a8648ce3d0201050003420004" + p256_x + p256_y,
  )
  assert_eq(key_outcome(no_curve), "BadKey(ECDSA key without a named curve)")
  // Parameters of another type.
  let other = hex(
    "3052300c06072a8648ce3d020102010103420004" + p256_x + p256_y,
  )
  assert_eq(
    key_outcome(other),
    "BadKey(malformed DER: unknown key parameters)",
  )
}

///|
/// A P-256 key from openssl and its SHA-384 signature of "hash override".
let openssl_p256 : String = "3059301306072a8648ce3d020106082a8648ce3d03010703420004d4cce8b204891f5519969bdb554ae93023b419f67b0cd0359596bc1c0d41ba569e7a68b965a215521b963ef555f5f3f42b9ae277c86061f22ab58aa543a5125d"

///|
let openssl_sha384_signature : String = "30440220427a8918e216fc365de8631033cd09d56fdb19e02766ba7616bcd669640e1cb40220760c644c30c549502e08fc234ce20a45e8b2c9918850ea47117d4c30abaaf3f2"

///|
test "the hash comes from the key kind unless given" {
  let key = @signature.PublicKey::from_spki(hex(openssl_p256))
  let message = b"hash override"
  let signature = hex(openssl_sha384_signature)
  assert_false(key.verify(message, signature))
  assert_false(key.verify(message, signature, hash=Sha256))
  assert_true(key.verify(message, signature, hash=Sha384))
  assert_false(key.verify(message, signature, hash=Sha512))
  assert_true(
    key.verify_digest(@signature.digest(Sha384, message), signature),
  )
  // The same check through the fixed-width form.
  guard @signature.der_signature_to_raw(signature, 32) is Some(raw) else {
    fail("the signature is strict DER")
  }
  assert_true(
    key.verify_digest_raw(@signature.digest(Sha384, message), raw),
  )
  assert_false(key.verify_digest_raw(@signature.digest(Sha384, message), signature))
  assert_false(key.verify_digest_raw(@signature.digest(Sha384, message), raw[1:]))
  // A changed message fails.
  assert_false(key.verify(b"hash overridE", signature, hash=Sha384))
}

///|
test "a P-384 key verifies with SHA-384 by default" {
  let root = as_object(
    @json.parse(
      fixture(@fixtures.wycheproof, "ecdsa_secp384r1_sha384_test.json"),
    ),
  )
  let group = as_object(member_array(root, "testGroups")[0])
  let key = @signature.PublicKey::from_spki(
    hex(member_text(group, "publicKeyDer")),
  )
  for case_json in member_array(group, "tests") {
    let case = as_object(case_json)
    if member_text(case, "result") == "valid" {
      let message = hex(member_text(case, "msg"))
      let signature = hex(member_text(case, "sig"))
      assert_true(key.verify(message, signature))
      assert_true(key.verify(message, signature, hash=Sha384))
      assert_false(key.verify(message, signature, hash=Sha256))
      assert_false(key.verify(message, signature, hash=Sha512))
      return
    }
  }
  fail("no valid case")
}

///|
/// The morphir-rust artifact digest.
let morphir_digest : String = "sha256:03d190b8ef97d354f9aca6854542979c36ce5f77c68a3d80de28ac1a77c432bd"

///|
/// The rule that `text` breaks as an artifact digest, checked against the
/// error text, or `None` when it parses.
fn digest_rule(text : String) -> String? raise {
  try @sigstore.ArtifactDigest::parse(text) catch {
    InvalidDigest(text=actual, rule~) as err => {
      assert_eq(actual, text)
      assert_true(err.message().contains(text.escape()), msg=err.message())
      Some(
        match rule {
          MissingAlgorithm => "missing algorithm"
          UnsupportedAlgorithm(name) => "unsupported \{name}"
          NotHex => "not hex"
          WrongLength(size) => "length \{size}"
        },
      )
    }
  } noraise {
    _ => None
  }
}

///|
test "ArtifactDigest: sha256 and 32 bytes of hex" {
  let hex = "03d190b8ef97d354f9aca6854542979c36ce5f77c68a3d80de28ac1a77c432bd"
  assert_eq(digest_rule("sha256:" + hex), None)
  assert_eq(digest_rule(hex), Some("missing algorithm"))
  assert_eq(digest_rule(""), Some("missing algorithm"))
  assert_eq(digest_rule(":" + hex), Some("unsupported "))
  assert_eq(digest_rule("sha512:" + hex), Some("unsupported sha512"))
  assert_eq(digest_rule("SHA256:" + hex), Some("unsupported SHA256"))
  assert_eq(digest_rule("sha256:" + hex[:62].to_owned() + "zz"), Some("not hex"))
  assert_eq(digest_rule("sha256:" + hex[:63].to_owned()), Some("not hex"))
  assert_eq(digest_rule("sha256:"), Some("length 0"))
  assert_eq(digest_rule("sha256:" + hex[:62].to_owned()), Some("length 31"))
  assert_eq(digest_rule("sha256:" + hex + "00"), Some("length 33"))
}

///|
test "ArtifactDigest: upper-case hex reads back as lower-case" {
  let upper = @sigstore.ArtifactDigest::parse(morphir_digest.to_upper().replace(old="SHA256", new="sha256"))
  let lower = @sigstore.ArtifactDigest::parse(morphir_digest)
  assert_eq(upper, lower)
  assert_eq(upper.to_string(), morphir_digest)
  assert_eq(@sigstore.ArtifactDigest::parse(upper.to_string()), upper)
  assert_eq(upper.to_bytes().length(), 32)
}

///|
test "ArtifactDigest: the message names the rule" {
  let err = try @sigstore.ArtifactDigest::parse("sha512:00") catch {
    err => err
  } noraise {
    _ => fail("parsed")
  }
  assert_eq(
    err.message(),
    "Invalid artifact digest \"sha512:00\": the algorithm \"sha512\" is not supported; use sha256",
  )
}

///|
test "ArtifactDigest: of_bytes is the SHA-256 of the bytes" {
  assert_eq(
    @sigstore.ArtifactDigest::of_bytes(b"").to_string(),
    "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  )
  assert_eq(
    @sigstore.ArtifactDigest::of_bytes(b"abc").to_string(),
    "sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

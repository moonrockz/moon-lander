///|
fn base64_fails(text : String) -> Bool {
  try {
    ignore(@encoding.decode_base64(text))
    false
  } catch {
    BadBase64(_) => true
    BadHex(_) => false
  }
}

///|
test "base64 reads both alphabets with and without padding" {
  assert_eq(@encoding.decode_base64("+/8="), b"\xfb\xff")
  assert_eq(@encoding.decode_base64("-_8"), b"\xfb\xff")
  assert_eq(@encoding.decode_base64("YWJj"), b"abc")
  assert_eq(@encoding.decode_base64("YWI="), b"ab")
  assert_eq(@encoding.decode_base64("YWI"), b"ab")
  assert_eq(@encoding.decode_base64("YQ=="), b"a")
  assert_eq(@encoding.decode_base64("YQ"), b"a")
  assert_eq(@encoding.decode_base64(""), b"")
  assert_eq(@encoding.decode_base64("YW\nJj"), b"abc")
}

///|
test "base64 refuses bad characters, lengths and padding" {
  for text in ["Y", "YWJjZ", "YQ===", "Y=Q=", "YQ=", "YW!j", "+_8=", "YWJj=="] {
    assert_true(base64_fails(text), msg=text)
  }
}

///|
test "base64 encoding round-trips" {
  for bytes in [b"", b"a", b"ab", b"abc", b"\x00\xff\x10\x80"] {
    assert_eq(@encoding.decode_base64(@encoding.encode_base64(bytes)), bytes)
  }
  assert_eq(@encoding.encode_base64(b"ab"), "YWI=")
  assert_eq(@encoding.encode_base64(b"\xfb\xff"), "+/8=")
}

///|
test "hex reads both cases and refuses odd or bad text" {
  assert_eq(@encoding.decode_hex("00fFaB"), b"\x00\xff\xab")
  assert_eq(@encoding.encode_hex(b"\x00\xff\xab"), "00ffab")
  for text in ["0", "0g", "zz"] {
    let failed = try {
      ignore(@encoding.decode_hex(text))
      false
    } catch {
      _ => true
    }
    assert_true(failed, msg=text)
  }
}

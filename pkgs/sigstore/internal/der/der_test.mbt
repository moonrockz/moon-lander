///|
fn hex(text : String) -> Bytes raise {
  @encoding.decode_hex(text)
}

///|
fn malformed(bytes : Bytes) -> Bool {
  try {
    ignore(@der.parse(bytes))
    false
  } catch {
    Malformed(_) => true
  }
}

///|
test "lengths must be definite and minimal" {
  assert_eq(@der.parse(hex("0400")).content.length(), 0)
  assert_eq(@der.parse(hex("04 7f".replace_all(old=" ", new="") + "00".repeat(127))).content.length(), 127)
  assert_eq(@der.parse(hex("048180" + "00".repeat(128))).content.length(), 128)
  // 127 bytes in the long form is not minimal.
  assert_true(malformed(hex("04817f" + "00".repeat(127))))
  // Leading zero in the length.
  assert_true(malformed(hex("04820080" + "00".repeat(128))))
  // Indefinite length.
  assert_true(malformed(hex("24800000")))
  // Multi-byte tag, truncation and trailing bytes.
  assert_true(malformed(hex("1f0100")))
  assert_true(malformed(hex("0402aa")))
  assert_true(malformed(hex("04010000")))
  assert_true(malformed(hex("04")))
  assert_true(malformed(hex("040000")))
}

///|
test "integers must be minimal and non-negative" {
  assert_eq(@der.parse(hex("020100")).unsigned().to_owned(), b"\x00")
  assert_eq(@der.parse(hex("02020080")).unsigned().to_owned(), b"\x80")
  assert_eq(@der.parse(hex("02017f")).small_int(), 127)
  for bad in ["0200", "020180", "0202007f", "0202ff80"] {
    let failed = try {
      ignore(@der.parse(hex(bad)).unsigned())
      false
    } catch {
      _ => true
    }
    assert_true(failed, msg=bad)
  }
}

///|
test "object identifiers" {
  assert_eq(@der.parse(hex("06092a864886f70d01010b")).oid(), "1.2.840.113549.1.1.11")
  assert_eq(@der.parse(hex("060a2b0601040183bf300101")).oid(), "1.3.6.1.4.1.57264.1.1")
  assert_eq(@der.parse(hex("0603551d11")).oid(), "2.5.29.17")
  for bad in ["0600", "06022b80", "06028001", "06012b86"] {
    let failed = try {
      ignore(@der.parse(hex(bad)).oid())
      false
    } catch {
      _ => true
    }
    assert_true(failed, msg=bad)
  }
}

///|
test "times are UTC with seconds" {
  let utc = @der.parse(@encoding.utf8("\u{17}\u{0d}261016064801Z"))
  assert_eq(utc.time(), 1792133281L)
  let general = @der.parse(@encoding.utf8("\u{18}\u{0f}20261016064801Z"))
  assert_eq(general.time(), 1792133281L)
  assert_eq(@der.parse(@encoding.utf8("\u{17}\u{0d}700101000000Z")).time(), 0L)
  assert_eq(@der.parse(@encoding.utf8("\u{17}\u{0d}491231235959Z")).time(), 2524607999L)
  for
    bad in [
      "\u{17}\u{0d}261016064801+", "\u{17}\u{0b}2610160648Z", "\u{17}\u{0d}261316064801Z",
      "\u{17}\u{0d}260230064801Z", "\u{17}\u{0d}261016246001Z",
    ] {
    let failed = try {
      ignore(@der.parse(@encoding.utf8(bad)).time())
      false
    } catch {
      _ => true
    }
    assert_true(failed, msg=bad)
  }
}

///|
test "booleans and bit strings" {
  assert_true(@der.parse(hex("0101ff")).boolean())
  assert_false(@der.parse(hex("010100")).boolean())
  let failed = try {
    ignore(@der.parse(hex("010101")).boolean())
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  // Key usage digitalSignature only: one named bit, seven unused.
  assert_eq(@der.parse(hex("03020780")).named_bits(), 1)
  // keyCertSign (5) and cRLSign (6).
  assert_eq(@der.parse(hex("03020106")).named_bits(), (1 << 5) | (1 << 6))
  assert_eq(@der.parse(hex("030200ff")).bit_string_bytes().to_owned(), b"\xff")
}

///|
test "encode writes minimal lengths that parse back" {
  for size in [0, 1, 127, 128, 255, 256, 65535, 65536] {
    let content = Bytes::make(size, b'\x01')
    let encoded = @der.encode(@der.OCTET_STRING, content)
    let element = @der.parse(encoded)
    assert_eq(element.tag, @der.OCTET_STRING)
    assert_eq(element.content.length(), size)
  }
}

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

///|
/// True when `body` raises `Malformed`.
fn refused(body : () -> Unit raise) -> Bool {
  try {
    body()
    false
  } catch {
    @der.Malformed(_) => true
    _ => false
  }
}

///|
test "length forms at each limit" {
  // One to three length bytes are read; four are not.
  assert_eq(@der.parse(hex("0481ff" + "00".repeat(255))).content.length(), 255)
  assert_eq(@der.parse(hex("04820100" + "00".repeat(256))).content.length(), 256)
  assert_true(malformed(hex("048200ff" + "00".repeat(255))))
  assert_true(malformed(hex("0484000000010000")))
  // A length longer than the input, in the short and long forms.
  assert_true(malformed(hex("047f00")))
  assert_true(malformed(hex("048180" + "00".repeat(127))))
  // The length bytes themselves are truncated.
  assert_true(malformed(hex("0482")))
  assert_true(malformed(hex("048201")))
  // A tag of 0x1e is one byte; 0x1f starts a multi-byte tag.
  assert_eq(@der.parse(hex("1e00")).tag, 0x1e)
  assert_true(malformed(hex("3f0100")))
}

///|
test "reader cursor operations" {
  let reader = @der.Reader::new(hex("0201010400"))
  assert_eq(reader.peek_tag(), Some(@der.INTEGER))
  assert_true(reader.optional(@der.OCTET_STRING) is None)
  assert_true(refused(() => reader.finish()))
  assert_eq(reader.expect(@der.INTEGER).small_int(), 1)
  assert_true(refused(() => ignore(reader.expect(@der.INTEGER))))
  // A failed expect still reads the element.
  assert_true(reader.is_empty())
  assert_eq(reader.peek_tag(), None)
  reader.finish()
  assert_true(refused(() => ignore(reader.next())))
  // The raw bytes include the header.
  let element = @der.parse(hex("3003020105"))
  assert_eq(element.raw.to_owned(), hex("3003020105"))
  assert_eq(element.content.to_owned(), hex("020105"))
  assert_eq(element.children().expect(@der.INTEGER).small_int(), 5)
  // Only constructed elements have children.
  assert_true(refused(() => ignore(@der.parse(hex("020105")).children())))
  assert_eq(@der.parse_tag(hex("0500"), @der.NULL).content.length(), 0)
  assert_true(refused(() => ignore(@der.parse_tag(hex("0500"), @der.INTEGER))))
}

///|
test "small integers up to three bytes" {
  assert_eq(@der.parse(hex("02037fffff")).small_int(), 0x7fffff)
  assert_eq(@der.parse(hex("020400ffffff")).small_int(), 0xffffff)
  assert_true(refused(() => ignore(@der.parse(hex("020401000000")).small_int())))
  // Not an INTEGER.
  assert_true(refused(() => ignore(@der.parse(hex("0a0101")).small_int())))
}

///|
test "booleans must be one byte" {
  assert_true(refused(() => ignore(@der.parse(hex("0100")).boolean())))
  assert_true(refused(() => ignore(@der.parse(hex("0102ffff")).boolean())))
  assert_true(refused(() => ignore(@der.parse(hex("0201ff")).boolean())))
}

///|
test "bit strings at each limit" {
  // bit_string_bytes needs no unused bits.
  assert_eq(@der.parse(hex("030100")).bit_string_bytes().length(), 0)
  assert_true(refused(() => ignore(@der.parse(hex("0300")).bit_string_bytes())))
  assert_true(refused(() => ignore(@der.parse(hex("030201ff")).bit_string_bytes())))
  assert_true(refused(() => ignore(@der.parse(hex("0401ff")).bit_string_bytes())))
  // named_bits: no bits, 16 bits, and the limits of the unused count.
  assert_eq(@der.parse(hex("030100")).named_bits(), 0)
  assert_eq(@der.parse(hex("030300ffff")).named_bits(), 0xffff)
  assert_eq(@der.parse(hex("03020080")).named_bits(), 1)
  assert_true(refused(() => ignore(@der.parse(hex("03040000ffff")).named_bits())))
  assert_true(refused(() => ignore(@der.parse(hex("03020880")).named_bits())))
  assert_true(refused(() => ignore(@der.parse(hex("030101")).named_bits())))
  assert_true(refused(() => ignore(@der.parse(hex("0300")).named_bits())))
  // The unused bits must be zero.
  assert_true(refused(() => ignore(@der.parse(hex("03020781")).named_bits())))
  assert_true(refused(() => ignore(@der.parse(hex("03020107")).named_bits())))
  assert_eq(@der.parse(hex("03020780")).named_bits(), 1)
  assert_eq(@der.parse(hex("03020106")).named_bits(), 0x60)
}

///|
test "object identifier arcs at each limit" {
  // The first two arcs share one value: 0.39, 1.0, 1.39, 2.0 and 2.100.
  assert_eq(@der.parse(hex("060127")).oid(), "0.39")
  assert_eq(@der.parse(hex("060128")).oid(), "1.0")
  assert_eq(@der.parse(hex("06014f")).oid(), "1.39")
  assert_eq(@der.parse(hex("060150")).oid(), "2.0")
  assert_eq(@der.parse(hex("06028134")).oid(), "2.100")
  // Arcs of 127 and 128.
  assert_eq(@der.parse(hex("06022a7f")).oid(), "1.2.127")
  assert_eq(@der.parse(hex("06032a8100")).oid(), "1.2.128")
  // The largest arc of 63 bits, and one 7-bit group more.
  assert_eq(
    @der.parse(hex("060a2a" + "ff".repeat(8) + "7f")).oid(),
    "1.2.\{(1UL << 63) - 1UL}",
  )
  assert_true(
    refused(() => ignore(@der.parse(hex("060b2a" + "ff".repeat(9) + "7f")).oid())),
  )
  // Not an OID.
  assert_true(refused(() => ignore(@der.parse(hex("04012a")).oid())))
}

///|
test "strings" {
  assert_eq(@der.parse(hex("0c026162")).text(), "ab")
  assert_eq(@der.parse(hex("13026162")).text(), "ab")
  assert_eq(@der.parse(hex("16026162")).text(), "ab")
  assert_eq(@der.parse(hex("0c03e282ac")).text(), "\u{20ac}")
  assert_true(refused(() => ignore(@der.parse(hex("0c01ff")).text())))
  assert_true(refused(() => ignore(@der.parse(hex("04026162")).text())))
}

///|
test "time limits" {
  // UTCTime years 50 and 49 are 1950 and 2049.
  let utc = (text : String) => @der.parse(
    @der.encode(@der.UTC_TIME, @encoding.utf8(text)),
  )
  assert_eq(utc("500101000000Z").time(), -631152000L)
  assert_eq(utc("491231235959Z").time(), 2524607999L)
  // Leap days.
  assert_eq(utc("000229000000Z").time(), 951782400L)
  assert_true(refused(() => ignore(utc("010229000000Z").time())))
  assert_true(refused(() => ignore(utc("000230000000Z").time())))
  // Day 0, month 0, minute 60 and second 60.
  for bad in ["260100000000Z", "260001000000Z", "260101006000Z", "260101000060Z"] {
    assert_true(refused(() => ignore(utc(bad).time())), msg=bad)
  }
  // A fraction or an offset is not DER.
  let general = (text : String) => @der.parse(
    @der.encode(@der.GENERALIZED_TIME, @encoding.utf8(text)),
  )
  assert_eq(general("21000301000000Z").time(), 4107542400L)
  assert_true(refused(() => ignore(general("20261016064801.5Z").time())))
  assert_true(refused(() => ignore(general("20261016064801+0000").time())))
  assert_true(refused(() => ignore(general("2026101606480Z").time())))
  // 2100 is not a leap year; 2000 is.
  assert_true(refused(() => ignore(general("21000229000000Z").time())))
  assert_eq(general("20000229000000Z").time(), 951782400L)
  // Another tag.
  assert_true(refused(() => ignore(@der.parse(hex("0400")).time())))
}

///|
test "days_in_month and unix_seconds" {
  assert_eq(@der.days_in_month(2024, 2), 29)
  assert_eq(@der.days_in_month(2023, 2), 28)
  assert_eq(@der.days_in_month(1900, 2), 28)
  assert_eq(@der.days_in_month(2000, 2), 29)
  assert_eq(@der.days_in_month(2026, 4), 30)
  assert_eq(@der.days_in_month(2026, 12), 31)
  assert_eq(@der.unix_seconds(1970, 1, 1, 0, 0, 0), 0L)
  assert_eq(@der.unix_seconds(1969, 12, 31, 23, 59, 59), -1L)
  assert_eq(@der.unix_seconds(2038, 1, 19, 3, 14, 8), 2147483648L)
}

///|
fn generalized(text : String) -> (Int64, Int) raise {
  let content = @encoding.utf8(text)
  let header = Bytes::from_array([b'\x18', content.length().to_byte()])
  @der.parse(Bytes::from_array([..header.to_array(), ..content.to_array()])).generalized_time()
}

///|
test "GeneralizedTime reads canonical fractions" {
  assert_eq(generalized("20261026192009Z"), (1793042409L, 0))
  assert_eq(generalized("20261026192009.5Z"), (1793042409L, 500_000_000))
  assert_eq(generalized("20261026192009.123456789Z"), (1793042409L, 123_456_789))
  assert_eq(generalized("20261026192009.001Z"), (1793042409L, 1_000_000))
  for
    bad in [
      "20261026192009.Z", "20261026192009.50Z", "20261026192009.1234567891Z", "20261026192009+0000",
      "20261026192009.5", "20261026192009,5Z", "2026102619200Z", "20261026192009.5aZ",
    ] {
    let failed = try {
      ignore(generalized(bad))
      false
    } catch {
      _ => true
    }
    assert_true(failed, msg=bad)
  }
}

///|
fn string_element(tag : Int, text : Bytes) -> @der.Element raise {
  @der.parse(Bytes::from_array([tag.to_byte(), text.length().to_byte(), ..text.to_array()]))
}

///|
test "PrintableString and IA5String keep to their character sets" {
  assert_eq(string_element(@der.PRINTABLE_STRING, b"Az09 '()+,-./:=?").text(), "Az09 '()+,-./:=?")
  for bad in [b"a@b", b"a*b", b"a_b", b"a\x00b", b"\xc3\xa9"] {
    let failed = try {
      ignore(string_element(@der.PRINTABLE_STRING, bad).text())
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
  assert_eq(string_element(@der.IA5_STRING, b"a@b_*\x7f").text(), "a@b_*\u{7f}")
  let failed = try {
    ignore(string_element(@der.IA5_STRING, b"\x80").text())
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  // UTF8String accepts any UTF-8.
  assert_eq(string_element(@der.UTF8_STRING, b"\xc3\xa9").text(), "é")
}

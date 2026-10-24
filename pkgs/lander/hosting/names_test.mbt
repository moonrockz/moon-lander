///|
/// The parse result as text: `ok`, or the error message.
fn service_name_result(text : String) -> String {
  try {
    ignore(@hosting.ServiceName::parse(text))
    "ok"
  } catch {
    err => err.message()
  }
}

///|
test "service names accept Unicode letters, marks, digits, _, - and ." {
  for
    text in [
      "a", "Z", "db", "db.primary", "telemetry-flush", "cache_2", "données",
      "数据库", "डेटा", "Ωmega", "café", "console", "com10", "lpt", "con2",
      "a\u{00B7}b", "a\u{203F}b", "a\u{FF3F}b", "a\u{30FB}b", "\u{216B}", "\u{2118}x",
    ] {
    @expect.expect(service_name_result(text)).to_equal("ok")
    @expect.expect(@hosting.ServiceName::parse(text).to_string()).to_equal(
      text,
    )
  }
}

///|
test "service names must start with a letter" {
  @expect.expect(service_name_result("")).to_equal(
    "Invalid service name \"\": the name is empty",
  )
  for
    text in [
      " db", "\tdb", "\u{00A0}db", ".db", "1db", "_db", "-db", "\u{0301}db", "\u{3164}",
      "\u{3164}db", "\u{200D}db",
    ] {
    @expect.expect(service_name_result(text)).to_equal(
      "Invalid service name \{text.escape()}: the name must start with a letter",
    )
  }
}

///|
test "service names have no character that a path cannot hold" {
  for
    text in [
      "a b", "a/b", "a\\b", "a:b", "a*b", "a?b", "a\"b", "a<b", "a>b", "a|b",
      "db\u{00A0}", "db\u{3000}", "d\nb", "d\u{2028}b", "d\u{202E}b", "d\u{007F}",
      "d\u{0000}b", "com\u{00B9}", "lpt\u{00B3}",
    ] {
    @expect.expect(service_name_result(text).contains("is not allowed")).to_equal(
      true,
    )
  }
}

///|
test "service names do not end with a dot" {
  @expect.expect(service_name_result("db.")).to_equal(
    "Invalid service name \"db.\": the name must not end with '.'",
  )
  @expect.expect(service_name_result("db.log")).to_equal("ok")
}

///|
test "service names are not Windows device names" {
  for
    text in [
      "con", "CON", "Prn", "aux", "nul", "NUL.log", "com0", "com9", "COM1",
      "lpt0", "LPT9", "con.d.e",
    ] {
    @expect.expect(service_name_result(text)).to_equal(
      "Invalid service name \{text.escape()}: the name is a Windows device name",
    )
  }
}

///|
test "service names are at most 128 bytes in UTF-8" {
  let ascii = "a" + "b".repeat(127)
  @expect.expect(service_name_result(ascii)).to_equal("ok")
  @expect.expect(service_name_result(ascii + "c")).to_equal(
    "Invalid service name \{(ascii + "c").escape()}: the name is 129 bytes in UTF-8; the limit is 128",
  )
  // `é` is 2 bytes in UTF-8, and `数` is 3.
  @expect.expect(service_name_result("é".repeat(64))).to_equal("ok")
  @expect.expect(
    service_name_result("é".repeat(65)).contains("130 bytes in UTF-8"),
  ).to_equal(true)
  @expect.expect(
    service_name_result("数".repeat(43)).contains("129 bytes in UTF-8"),
  ).to_equal(true)
}

///|
test "exit codes are in the range 0 to 255" {
  @expect.expect(@hosting.ExitCode::from_int(0)).to_equal(
    @hosting.ExitCode::success(),
  )
  @expect.expect(@hosting.ExitCode::from_int(1)).to_equal(
    @hosting.ExitCode::failure(),
  )
  @expect.expect(@hosting.ExitCode::from_int(255).to_int()).to_equal(255)
  for code in [-1, 256, 999] {
    let result : Result[@hosting.ExitCode, @hosting.HostError] = try
      Ok(@hosting.ExitCode::from_int(code))
    catch {
      err => Err(err)
    }
    guard result is Err(@hosting.InvalidExitCode(code=got)) else {
      fail("expected InvalidExitCode")
    }
    @expect.expect(got).to_equal(code)
  }
}

///|
test "service names have no invisible character" {
  for
    text in [
      "d\u{200C}b", "d\u{200D}b", "db\u{FE0F}", "a\u{034F}", "a\u{3164}", "a\u{FFA0}",
      "a\u{180B}", "a\u{17B4}", "a\u{E0100}",
    ] {
    @expect.expect(service_name_result(text).has_suffix("it is invisible")).to_equal(
      true,
    )
  }
}

///|
test "service name bytes count 4-byte characters" {
  // `𠀀` (U+20000) is 4 bytes in UTF-8 and a surrogate pair in UTF-16.
  @expect.expect(service_name_result("\u{20000}".repeat(32))).to_equal("ok")
  @expect.expect(
    service_name_result("\u{20000}".repeat(33)).contains("132 bytes in UTF-8"),
  ).to_equal(true)
}

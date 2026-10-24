///|
/// The parse result as text: `ok`, or the error message.
fn app_name_result(text : String) -> String {
  try {
    ignore(@hosting.AppName::parse(text))
    "ok"
  } catch {
    err => err.message()
  }
}

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
/// The characters next to each allowed ASCII range, which no rule allows.
let outside_ranges : Array[Char] = ['@', '[', '`', '{', '/', ':', ' ']

///|
test "application names start with a letter and use letters, digits, - and _" {
  for text in ["a", "z", "A", "Z", "a0", "a9", "my-tool", "my_tool", "a-1_b"] {
    @expect.expect(app_name_result(text)).to_equal("ok")
    @expect.expect(@hosting.AppName::parse(text).to_string()).to_equal(text)
  }
}

///|
test "an application name with a space names the text and the character" {
  let result : Result[@hosting.AppName, @hosting.HostError] = try
    Ok(@hosting.AppName::parse("my tool"))
  catch {
    err => Err(err)
  }
  guard result is Err(@hosting.InvalidAppName(text~, reason~)) else {
    fail("expected InvalidAppName")
  }
  @expect.expect(text).to_equal("my tool")
  @expect.expect(reason).to_equal(
    "the character \" \" is not allowed; use ASCII letters, digits, '-' and '_'",
  )
}

///|
test "application names that break a rule do not parse" {
  @expect.expect(app_name_result("")).to_equal(
    "Invalid application name \"\": the name is empty",
  )
  for text in ["0tool", "9tool", "-tool", "_tool", "../etc", " acme"] {
    @expect.expect(app_name_result(text)).to_equal(
      "Invalid application name \{text.escape()}: the name must start with an ASCII letter",
    )
  }
  for char in outside_ranges {
    @expect.expect(app_name_result("a\{char}").contains("is not allowed")).to_equal(
      true,
    )
  }
  for text in ["my.tool", "a\\b", "café", "tool\n", "a\u{00A0}"] {
    @expect.expect(app_name_result(text).contains("is not allowed")).to_equal(
      true,
    )
  }
}

///|
test "service names accept Unicode letters, marks, digits, _, - and ." {
  for
    text in [
      "a", "Z", "db", "db.primary", "telemetry-flush", "cache_2", "données",
      "数据库", "डेटा", "Ωmega", "café", "console", "com10", "lpt", "con2",
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
  for text in [" db", "\tdb", "\u{00A0}db", ".db", "1db", "_db", "-db", "\u{0301}db"] {
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

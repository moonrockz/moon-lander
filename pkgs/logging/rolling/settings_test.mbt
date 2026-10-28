///|
/// The rule that `text` breaks, or `None` when it parses. It also checks that
/// the error holds the input.
fn stem_rule(text : String) -> @rolling.StemRule? raise {
  try {
    ignore(@rolling.LogFileStem::parse(text))
    None
  } catch {
    InvalidStem(input~, rule~) => {
      assert_eq(input, text)
      Some(rule)
    }
    error => raise error
  }
}

///|
test "a stem has 1 to 64 characters" {
  assert_true(stem_rule("") is Some(Empty))
  assert_true(stem_rule("a") is None)
  assert_true(stem_rule(String::make(64, 'a')) is None)
  assert_true(stem_rule(String::make(65, 'a')) is Some(TooLong))
}

///|
test "a stem starts with an ASCII letter" {
  assert_true(stem_rule("acme") is None)
  assert_true(stem_rule("Zeta") is None)
  assert_true(stem_rule("1acme") is Some(NotLetterStart))
  assert_true(stem_rule("_acme") is Some(NotLetterStart))
  assert_true(stem_rule("-acme") is Some(NotLetterStart))
  assert_true(stem_rule("éacme") is Some(NotLetterStart))
}

///|
test "a stem holds only ASCII letters, digits, _ and -" {
  assert_true(stem_rule("my_app-2b") is None)
  assert_true(stem_rule("a.b") is Some(InvalidCharacter('.')))
  assert_true(stem_rule("a b") is Some(InvalidCharacter(' ')))
  assert_true(stem_rule("a/b") is Some(InvalidCharacter('/')))
  assert_true(stem_rule("caf\u{e9}") is Some(InvalidCharacter('\u{e9}')))
}

///|
test "a stem does not end with _ or - and digits" {
  assert_true(stem_rule("acme_001") is Some(NumericSuffix))
  assert_true(stem_rule("acme-20261027") is Some(NumericSuffix))
  assert_true(stem_rule("acme-1") is Some(NumericSuffix))
  assert_true(stem_rule("acme2") is None)
  assert_true(stem_rule("acme-v1") is None)
  assert_true(stem_rule("acme_") is None)
  assert_true(stem_rule("acme-") is None)
}

///|
test "a stem is not a Windows device name in any letter case" {
  for name in [
    "CON", "con", "Con", "PRN", "aux", "NUL", "COM1", "com9", "COM0", "lpt1", "LPT9",
    "Lpt0",
  ] {
    assert_true(stem_rule(name) is Some(ReservedDeviceName))
  }
  for name in ["CONX", "cons", "COM10", "COMA", "LPT", "nulls", "AUXI"] {
    assert_true(stem_rule(name) is None)
  }
}

///|
test "a stem error names the input and the rule" {
  let message = try {
    ignore(@rolling.LogFileStem::parse("a.b"))
    ""
  } catch {
    error => error.message()
  }
  inspect(message, content=(
    #|Invalid log file stem "a.b": the character "." is not an ASCII letter, an ASCII digit, _ or -
  ))
}

///|
test "a file byte limit is greater than zero" {
  assert_eq(@rolling.FileByteLimit::bytes(1L).to_int64(), 1L)
  let zero = try {
    ignore(@rolling.FileByteLimit::bytes(0L))
    None
  } catch {
    NotPositiveByteLimit(bytes~) => Some(bytes)
    _ => None
  }
  assert_eq(zero, Some(0L))
  let negative = try {
    ignore(@rolling.FileByteLimit::bytes(-1L))
    None
  } catch {
    NotPositiveByteLimit(bytes~) => Some(bytes)
    _ => None
  }
  assert_eq(negative, Some(-1L))
  assert_eq(@rolling.FileByteLimit::default().to_int64(), 10485760L)
}

///|
test "a retained file count is greater than zero" {
  assert_eq(@rolling.RetainedFileCount::count(1).to_int(), 1)
  let zero = try {
    ignore(@rolling.RetainedFileCount::count(0))
    None
  } catch {
    NotPositiveFileCount(count~) => Some(count)
    _ => None
  }
  assert_eq(zero, Some(0))
  let negative = try {
    ignore(@rolling.RetainedFileCount::count(-1))
    None
  } catch {
    NotPositiveFileCount(count~) => Some(count)
    _ => None
  }
  assert_eq(negative, Some(-1))
  assert_eq(@rolling.RetainedFileCount::default().to_int(), 31)
}

///|
test "the defaults" {
  assert_eq(
    @rolling.RollingPolicy::default(),
    DailyAndSize(@rolling.FileByteLimit::default()),
  )
  assert_eq(
    @rolling.Retention::default(),
    KeepNewest(@rolling.RetainedFileCount::default()),
  )
  assert_eq(@rolling.FileFormat::default(), Text)
  assert_eq(@rolling.FileFormat::Text.extension(), "log")
  assert_eq(@rolling.FileFormat::JsonLines.extension(), "jsonl")
}

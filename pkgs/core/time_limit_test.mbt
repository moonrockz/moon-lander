///|
/// The milliseconds of the parsed `text`.
fn parsed_millis(text : String) -> Int raise {
  @lander_core.TimeLimit::parse(text).to_millis()
}

///|
/// The rule that `text` breaks, or `None` when it parses. It also checks that
/// the error holds the input.
fn parse_rule(text : String) -> @lander_core.TimeLimitRule? raise {
  try {
    ignore(@lander_core.TimeLimit::parse(text))
    None
  } catch {
    InvalidTimeLimit(input~, rule~) => {
      assert_eq(input, text)
      Some(rule)
    }
  }
}

///|
/// The input and the rule of a failed constructor call, or `None` when it
/// succeeds.
fn constructor_failure(
  make : () -> @lander_core.TimeLimit raise @lander_core.TimeLimitError,
) -> (String, @lander_core.TimeLimitRule)? {
  try {
    ignore(make())
    None
  } catch {
    InvalidTimeLimit(input~, rule~) => Some((input, rule))
  }
}

///|
test "the smallest and the largest limits" {
  assert_eq(@lander_core.TimeLimit::millis(1).to_millis(), 1)
  assert_eq(
    @lander_core.TimeLimit::millis(2147483647).to_millis(),
    2147483647,
  )
}

///|
test "zero and negative counts are not positive" {
  let zero = constructor_failure(() => @lander_core.TimeLimit::millis(0))
  assert_true(zero is Some(("0ms", NotPositive)))
  let negative = constructor_failure(() => @lander_core.TimeLimit::millis(-1))
  assert_true(negative is Some(("-1ms", NotPositive)))
  let seconds = constructor_failure(() => @lander_core.TimeLimit::seconds(0))
  assert_true(seconds is Some(("0s", NotPositive)))
}

///|
test "seconds are checked against the largest limit without overflow" {
  assert_eq(
    @lander_core.TimeLimit::seconds(2147483).to_millis(),
    2147483000,
  )
  let above = constructor_failure(() => {
    @lander_core.TimeLimit::seconds(2147484)
  })
  assert_true(above is Some(("2147484s", AboveLargest)))
  let largest = constructor_failure(() => {
    @lander_core.TimeLimit::seconds(2147483647)
  })
  assert_true(largest is Some((_, AboveLargest)))
}

///|
test "constructors and the parse give equal and ordered limits" {
  assert_eq(@lander_core.TimeLimit::seconds(30).to_millis(), 30000)
  let parsed = @lander_core.TimeLimit::parse("1.5s")
  assert_eq(@lander_core.TimeLimit::millis(1500), parsed)
  assert_true(parsed < @lander_core.TimeLimit::seconds(2))
  assert_true(@lander_core.TimeLimit::millis(1) < parsed)
}

///|
test "short units" {
  assert_eq(["9ms", "9 ms", "10s", "5m", "2h"].map(parsed_millis), [
    9, 9, 10000, 300000, 7200000,
  ])
}

///|
test "long units" {
  assert_eq(
    [
      "1 millisecond", "2 milliseconds", "10 seconds", "1 second", "2 minutes",
      "1 minute", "1 hour", "3 hours",
    ].map(parsed_millis),
    [1, 2, 10000, 1000, 120000, 60000, 3600000, 10800000],
  )
}

///|
test "compound values" {
  assert_eq(["2m30s", "1h 15m", "1h 2m 3s 4ms", "1m30s"].map(parsed_millis), [
    150000, 4500000, 3723004, 90000,
  ])
}

///|
test "decimal numbers" {
  assert_eq(["1.5s", "0.25 hours", "1.001s", "010s"].map(parsed_millis), [
    1500, 900000, 1001, 10000,
  ])
}

///|
test "a number without a unit" {
  for text in ["5000", "10 5s", "1m 30"] {
    assert_true(parse_rule(text) is Some(MissingUnit))
  }
}

///|
test "an unknown unit names the unit text" {
  for (text, unit) in [
    ("30d", "d"),
    ("10 secs", "secs"),
    ("10 Seconds", "Seconds"),
    ("1MS", "MS"),
  ] {
    assert_true(parse_rule(text) is Some(UnknownUnit(found)) && found == unit)
  }
}

///|
test "the value must be a whole number of milliseconds" {
  assert_eq(parsed_millis("1ms"), 1)
  assert_true(parse_rule("0.5ms") is Some(NotWholeMilliseconds))
  assert_eq(parsed_millis("1.001s"), 1001)
  assert_true(parse_rule("1.0005s") is Some(NotWholeMilliseconds))
  assert_eq(parsed_millis("1.0010000000000000000000s"), 1001)
}

///|
test "a zero total is not positive" {
  for text in ["0s", "0ms", "0.0h", "0h 0m"] {
    assert_true(parse_rule(text) is Some(NotPositive))
  }
}

///|
test "a sign or a bad decimal is not a number" {
  for text in ["-1s", "+1s", ".5s", "5.s", "s", "1m ,30s", "1.5.5s"] {
    assert_true(parse_rule(text) is Some(NotANumber))
  }
}

///|
test "the largest limit" {
  assert_eq(parsed_millis("596h"), 2145600000)
  assert_eq(parsed_millis("596h31m23s647ms"), 2147483647)
  assert_true(parse_rule("596h31m23s648ms") is Some(AboveLargest))
  assert_true(parse_rule("597h") is Some(AboveLargest))
  assert_true(parse_rule("99999999999999999999999h") is Some(AboveLargest))
}

///|
test "parts must go from the largest unit to the smallest" {
  assert_true(parse_rule("30s 1m") is Some(UnitsOutOfOrder))
  assert_true(parse_rule("1ms 1s") is Some(UnitsOutOfOrder))
  assert_true(parse_rule("1m 30s 1m") is Some(UnitsOutOfOrder))
}

///|
test "a unit can occur only one time" {
  assert_true(parse_rule("1m 1m") is Some(RepeatedUnit))
  assert_true(parse_rule("1 second 2s") is Some(RepeatedUnit))
}

///|
test "empty text and extra spaces" {
  assert_true(parse_rule("") is Some(Empty))
  for text in [" 10s", "10s ", "10  s", "1m  30s", " "] {
    assert_true(parse_rule(text) is Some(UnexpectedSpace))
  }
}

///|
test "the shape is checked before the order and the value" {
  assert_true(parse_rule("30s 1x") is Some(UnknownUnit(_)))
  assert_true(parse_rule("0.5ms 1s") is Some(UnitsOutOfOrder))
}

///|
test "the canonical text" {
  assert_eq(
    [150000, 1500, 3723004, 1, 2147483647, 3600000].map(millis => {
      @lander_core.TimeLimit::millis(millis).to_string()
    }),
    ["2m30s", "1s500ms", "1h2m3s4ms", "1ms", "596h31m23s647ms", "1h"],
  )
}

///|
test "law: the canonical text parses to an equal limit" {
  @quickcheck.check((pair : (UInt, UInt)) => {
    let (high, low) = pair
    let millis = ((high.to_uint64() * 65536UL + low.to_uint64()) % 2147483647UL +
    1UL).to_int()
    let limit = @lander_core.TimeLimit::millis(millis)
    @lander_core.TimeLimit::parse(limit.to_string()) == limit
  })
}

///|
test "the error message names the input and the rule" {
  let messages = ["", "30d", "0s"].map(text => try {
    ignore(@lander_core.TimeLimit::parse(text))
    "ok"
  } catch {
    err => err.message()
  })
  assert_eq(messages, [
    "Invalid time limit \"\": the text is empty",
    "Invalid time limit \"30d\": the unit \"d\" is not known; use ms, s, m or h, or millisecond(s), second(s), minute(s) or hour(s)",
    "Invalid time limit \"0s\": the value must be greater than zero",
  ])
}

///|
test "long digit runs give the same value on every target" {
  let zeros = String::make(5000, '0')
  assert_eq(parsed_millis("1.\{zeros}s"), 1000)
  assert_eq(parsed_millis("\{zeros}1500ms"), 1500)
  assert_eq(parsed_millis("\{zeros}1.5\{zeros}s"), 1500)
}

///|
test "the parse time is linear in the text" {
  let zeros = String::make(200_000, '0')
  assert_eq(parsed_millis("1.\{zeros}ms"), 1)
  assert_true(parse_rule("1\{zeros}ms") is Some(AboveLargest))
}

///|
test "fractions next to the 7-digit limit" {
  assert_eq(parsed_millis("0.0000125h"), 45)
  assert_eq(parsed_millis("0.00001250h"), 45)
  assert_true(parse_rule("0.0000001h") is Some(NotWholeMilliseconds))
  assert_true(parse_rule("0.00000001h") is Some(NotWholeMilliseconds))
  assert_true(parse_rule("0.00000125h") is Some(NotWholeMilliseconds))
}

///|
test "whole numbers next to the 10-digit limit" {
  assert_true(parse_rule("9999999999ms") is Some(AboveLargest))
  assert_true(parse_rule("10000000000ms") is Some(AboveLargest))
  assert_eq(parsed_millis("0000000002147483647ms"), 2147483647)
}

///|
test "each part must be a whole number of milliseconds" {
  assert_true(parse_rule("1.0005s 0.5ms") is Some(NotWholeMilliseconds))
  assert_true(parse_rule("1\{String::make(20, '0')}h 0.5ms") is Some(NotWholeMilliseconds))
}

///|
test "whitespace that is not a space is unexpected" {
  for text in ["10s\n", "\t10s", "10\ts", "10\u{00A0}s", "1m\r\n30s"] {
    assert_true(parse_rule(text) is Some(UnexpectedSpace))
  }
}

///|
test "an unknown unit holds the full text that follows the number" {
  for (text, unit) in [
    ("10µs", "µs"),
    ("10 séconds", "séconds"),
    ("10%", "%"),
    ("1m,30s", "m,"),
  ] {
    assert_true(parse_rule(text) is Some(UnknownUnit(found)) && found == unit)
  }
}

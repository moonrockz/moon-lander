# moonrockz/moon-lander-core

Shared domain types of the Moon-Lander framework: the application name and the
time limit. The other framework modules (`moon-lander-config`,
`moon-lander-mediator`, `moon-lander-hosting` and `moon-lander`) import this
module, so a type here has one set of rules for all of them. The module imports nothing except the MoonBit core library.

Import the root package with an explicit alias, because the module name has `-`
in it:

```moonbit notest
///|
import {
  "moonrockz/moon-lander-core" @lander_core,
}
```

## Application name

An `AppName` starts with an ASCII letter and holds only ASCII letters, digits,
`-` and `_`. So it is safe in file and directory names. `AppName::parse` is the
only way to make one. A failure raises `AppNameError::InvalidAppName` with the
text and the broken rule as an `AppNameRule` case, so a caller can match the rule
and does not have to read the message:

```mbt check
///|
test "parse an application name and match a failure by its rule" {
  let name = @lander_core.AppName::parse("my-tool")
  assert_eq(name.to_string(), "my-tool")
  let rule = try {
    ignore(@lander_core.AppName::parse("my tool"))
    None
  } catch {
    InvalidAppName(rule~, ..) => Some(rule)
  }
  assert_true(rule is Some(CharNotAllowed(' ')))
}
```

| Rule | Case | Example that breaks it |
| --- | --- | --- |
| Not empty | `Empty` | `""` |
| Starts with an ASCII letter | `FirstNotAsciiLetter` | `9tool`, `-tool` |
| Only ASCII letters, digits, `-` and `_` | `CharNotAllowed(char)` | `my tool`, `my.tool`, `café` |

## Time limit

A `TimeLimit` is a positive amount of time, from 1 millisecond to 2 147 483 647
milliseconds (the largest `Int`, about 24.8 days). That is the range of the
timeouts of `moonbitlang/async`, so `to_millis()` gives an `Int` that a timeout
can take, and it cannot fail. Make one from a count with
`TimeLimit::millis(count)` or `TimeLimit::seconds(count)`, or parse its text form
with `TimeLimit::parse(text)`:

```mbt check
///|
/// A function that takes a timeout as milliseconds, such as
/// `@async.with_timeout`.
fn wait_up_to(millis : Int) -> String {
  "waits up to \{millis} ms"
}

///|
test "parse a time limit and give it to a timeout" {
  let limit = @lander_core.TimeLimit::parse("2m30s")
  assert_eq(wait_up_to(limit.to_millis()), "waits up to 150000 ms")
  assert_eq(limit.to_string(), "2m30s")
  assert_eq(limit, @lander_core.TimeLimit::seconds(150))
}
```

The text form has one or more parts. Each part is a decimal number, an optional
space and a unit, and the parts go from the largest unit to the smallest, each
unit at most one time: `9ms`, `9 ms`, `10 seconds`, `1.5s`, `2m30s`, `1h 15m`.

| Unit | Short | Long |
| --- | --- | --- |
| Millisecond | `ms` | `millisecond`, `milliseconds` |
| Second | `s` | `second`, `seconds` |
| Minute | `m` | `minute`, `minutes` |
| Hour | `h` | `hour`, `hours` |

A failure raises `TimeLimitError::InvalidTimeLimit` with the input and the broken
rule as a `TimeLimitRule` case:

| Rule | Case | Example that breaks it |
| --- | --- | --- |
| Not empty | `Empty` | `""` |
| At most one space, only inside or between parts | `UnexpectedSpace` | ` 10s`, `10  s` |
| Each part starts with a number | `NotANumber` | `-1s`, `.5s` |
| Each number has a unit | `MissingUnit` | `5000` |
| A known unit, in lower case | `UnknownUnit(unit)` | `30d`, `10 Seconds` |
| Largest unit first | `UnitsOutOfOrder` | `30s 1m` |
| Each unit one time | `RepeatedUnit` | `1m 1m` |
| A whole number of milliseconds | `NotWholeMilliseconds` | `0.5ms`, `1.0005s` |
| Greater than zero | `NotPositive` | `0s` |
| Not more than the largest limit | `AboveLargest` | `597h` |

`to_string()` gives the canonical text, from hours to milliseconds with short
units and no spaces, for example `1s500ms`. The parse reads it back to an equal
limit.

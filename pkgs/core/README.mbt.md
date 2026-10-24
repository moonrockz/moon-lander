# moonrockz/moon-lander-core

Shared domain types of the Moon-Lander framework. The other framework modules
(`moon-lander-config`, `moon-lander-mediator`, `moon-lander-hosting` and
`moon-lander`) import this module, so a type here has one set of rules for all of
them. The module imports nothing except the MoonBit core library.

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

///|
/// One part of a parsed message template: literal text or a named hole.
priv enum Part {
  Literal(String)
  Hole(String)
}

///|
/// Parse a message template into literal text and named holes.
///
/// `{{` is a literal `{` and `}}` is a literal `}`. A `{`, one or more name
/// characters (ASCII letters, digits and `_`) and a `}` make a hole. Each other
/// brace is literal text: an unclosed `{`, an empty `{}`, a name with another
/// character, and a single `}`. A parse never fails.
fn parse_template(template : String) -> Array[Part] {
  let chars = template.to_array()
  let parts = []
  let text = StringBuilder()
  let flush = () => {
    if !text.is_empty() {
      parts.push(Literal(text.to_string()))
      text.reset()
    }
  }
  let mut i = 0
  while i < chars.length() {
    let char = chars[i]
    if char == '{' && i + 1 < chars.length() && chars[i + 1] == '{' {
      text.write_char('{')
      i += 2
    } else if char == '}' && i + 1 < chars.length() && chars[i + 1] == '}' {
      text.write_char('}')
      i += 2
    } else if char == '{' {
      let mut end = i + 1
      while end < chars.length() && is_hole_name_char(chars[end]) {
        end += 1
      }
      if end > i + 1 && end < chars.length() && chars[end] == '}' {
        flush()
        parts.push(Hole(String::from_array(chars[i + 1:end])))
        i = end + 1
      } else {
        text.write_char('{')
        i += 1
      }
    } else {
      text.write_char(char)
      i += 1
    }
  }
  flush()
  parts
}

///|
/// An ASCII letter, an ASCII digit or `_`.
fn is_hole_name_char(char : Char) -> Bool {
  (char >= 'a' && char <= 'z') ||
  (char >= 'A' && char <= 'Z') ||
  (char >= '0' && char <= '9') ||
  char == '_'
}

///|
/// Pair the holes of `parts` with `args` in order. A hole with no argument gives
/// no property, and an argument with no hole is dropped. Each value is a copy, so
/// a later change to an argument does not change the event.
fn bind_properties(parts : Array[Part], args : Array[Json]) -> Array[(String, Json)] {
  let properties = []
  for part in parts {
    guard part is Hole(name) else { continue }
    guard properties.length() < args.length() else { break }
    properties.push((name, copy_json(args[properties.length()])))
  }
  properties
}

///|
/// The text of a property value in a message: a JSON string without quotes, and
/// each other value as compact JSON.
fn render_value(value : Json) -> String {
  match value {
    String(text) => text
    _ => value.stringify()
  }
}

///|
/// The message text: the template with each hole replaced by the text of its
/// property value. A hole whose name has no property stays as its literal text.
/// When a name occurs in more than one hole, each of them shows the first value.
pub fn LogEvent::message(self : LogEvent) -> String {
  let out = StringBuilder()
  for part in parse_template(self.template) {
    match part {
      Literal(text) => out.write_string(text)
      Hole(name) =>
        match self.find(name) {
          Some(value) => out.write_string(render_value(value))
          None => out.write_string("{\{name}}")
        }
    }
  }
  out.to_string()
}

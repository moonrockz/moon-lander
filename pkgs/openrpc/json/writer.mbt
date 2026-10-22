///|
priv enum WriteItem {
  Text(String)
  Item(Value, Int32)
}

///|
fn key_compare(a : String, b : String) -> Int32 {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    let order = a.code_unit_at(i).compare(b.code_unit_at(i))
    if order != 0 {
      return order
    }
  }
  a.length().compare(b.length())
}

///|
fn hex4(unit : Int) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for shift in [12, 8, 4, 0] {
    out.write_char(digits[(unit >> shift) & 15].to_int().unsafe_to_char())
  }
  out.to_string()
}

///|
/// Minimal JSON string escaping, or None for an unpaired UTF-16 surrogate,
/// which the reader rejects and which is not Unicode text.
fn quote(text : String) -> String? {
  let out = StringBuilder()
  out.write_char('"')
  let n = text.length()
  let mut i = 0
  while i < n {
    let unit = text.code_unit_at(i).to_int()
    if unit >= 0xD800 && unit <= 0xDFFF {
      guard unit <= 0xDBFF && i + 1 < n else { return None }
      let low = text.code_unit_at(i + 1).to_int()
      guard low >= 0xDC00 && low <= 0xDFFF else { return None }
      let point = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
      out.write_char(point.unsafe_to_char())
      i += 2
      continue
    }
    match unit {
      0x22 => out.write_string("\\\"")
      0x5C => out.write_string("\\\\")
      0x08 => out.write_string("\\b")
      0x0C => out.write_string("\\f")
      0x0A => out.write_string("\\n")
      0x0D => out.write_string("\\r")
      0x09 => out.write_string("\\t")
      _ =>
        if unit < 0x20 {
          out.write_string("\\u" + hex4(unit))
        } else {
          out.write_char(unit.unsafe_to_char())
        }
    }
    i += 1
  }
  out.write_char('"')
  Some(out.to_string())
}

///|
/// Deterministic JSON text: object keys by UTF-16 code units, exact number
/// tokens, array order kept, no final newline. `Pretty` only adds layout.
pub fn write(
  value : Value,
  format~ : Format = Compact,
  limits~ : Limits = Limits::new(),
) -> Result[String, Diagnostic] {
  let pretty = format == Pretty
  let unpaired = () => {
    Diagnostic::new(
      InvalidValue,
      "String contains an unpaired UTF-16 surrogate and is not Unicode text",
    )
  }
  let newline = (depth : Int) => {
    let out = StringBuilder()
    out.write_char('\n')
    for _ in 0..<depth {
      out.write_string("  ")
    }
    Text(out.to_string())
  }
  let out = StringBuilder()
  let stack = [WriteItem::Item(value, 0)]
  let mut count = 0
  let mut reserved = 1
  let mut length = 0
  while stack.pop() is Some(item) {
    match item {
      Text(text) => {
        if text.length() > limits.max_source - length {
          return Err(
            Diagnostic::new(LimitExceeded, "JSON output size limit exceeded"),
          )
        }
        length += text.length()
        out.write_string(text)
      }
      Item(value, depth) => {
        count += 1
        if count > limits.max_nodes {
          return Err(
            Diagnostic::new(LimitExceeded, "JSON output node limit exceeded"),
          )
        }
        match value.kind {
          Null => stack.push(Text("null"))
          Boolean(v) => stack.push(Text(if v { "true" } else { "false" }))
          String(v) =>
            match quote(v) {
              Some(text) => stack.push(Text(text))
              None => return Err(unpaired())
            }
          Numeric(n) => {
            if n.token.length() > limits.max_number {
              return Err(
                Diagnostic::new(
                  LimitExceeded,
                  "JSON number token limit exceeded",
                ),
              )
            }
            stack.push(Text(n.token))
          }
          Array(items) => {
            if items.length() > limits.max_nodes - reserved {
              return Err(
                Diagnostic::new(
                  LimitExceeded,
                  "JSON output node limit exceeded",
                ),
              )
            }
            reserved += items.length()
            if depth >= limits.max_depth {
              return Err(
                Diagnostic::new(
                  LimitExceeded,
                  "JSON output nesting limit exceeded",
                ),
              )
            }
            stack.push(Text("]"))
            if pretty && !items.is_empty() {
              stack.push(newline(depth))
            }
            for i = items.length() - 1; i >= 0; i = i - 1 {
              stack.push(Item(items[i], depth + 1))
              if pretty {
                stack.push(newline(depth + 1))
              }
              if i > 0 {
                stack.push(Text(","))
              }
            }
            stack.push(Text("["))
          }
          Object(entries) => {
            if entries.length() > limits.max_nodes - reserved {
              return Err(
                Diagnostic::new(
                  LimitExceeded,
                  "JSON output node limit exceeded",
                ),
              )
            }
            reserved += entries.length()
            if depth >= limits.max_depth {
              return Err(
                Diagnostic::new(
                  LimitExceeded,
                  "JSON output nesting limit exceeded",
                ),
              )
            }
            let fields = entries.copy()
            fields.sort_by((a, b) => key_compare(a.0, b.0))
            stack.push(Text("}"))
            if pretty && !fields.is_empty() {
              stack.push(newline(depth))
            }
            for i = fields.length() - 1; i >= 0; i = i - 1 {
              stack.push(Item(fields[i].1, depth + 1))
              stack.push(Text(if pretty { ": " } else { ":" }))
              match quote(fields[i].0) {
                Some(text) => stack.push(Text(text))
                None => return Err(unpaired())
              }
              if pretty {
                stack.push(newline(depth + 1))
              }
              if i > 0 {
                stack.push(Text(","))
              }
            }
            stack.push(Text("{"))
          }
        }
      }
    }
  }
  Ok(out.to_string())
}

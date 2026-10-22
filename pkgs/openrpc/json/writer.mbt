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
pub fn write(
  value : Value,
  limits~ : Limits = Limits::new(),
) -> Result[String, Diagnostic] {
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
          String(v) => stack.push(Text(Json::string(v).stringify()))
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
            for i = items.length() - 1; i >= 0; i = i - 1 {
              stack.push(Item(items[i], depth + 1))
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
            for i = fields.length() - 1; i >= 0; i = i - 1 {
              stack.push(Item(fields[i].1, depth + 1))
              stack.push(Text(":"))
              stack.push(Text(Json::string(fields[i].0).stringify()))
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

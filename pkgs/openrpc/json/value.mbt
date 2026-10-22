///|
/// Compare decoded JSON values. Object member order is insignificant.
/// Numeric token spelling is significant unless `numeric` is selected.
pub fn Value::equals(
  self : Value,
  other : Value,
  numeric~ : Bool = false,
  limits~ : Limits = Limits::new(),
) -> Result[Bool, Diagnostic] {
  let stack = [(self, other, 0)]
  let mut reserved = 1
  let mut left_text = 0
  let mut right_text = 0
  let charge_text = fn(a : String, b : String) -> Bool {
    if a.length() > limits.max_source - left_text ||
      b.length() > limits.max_source - right_text {
      return false
    }
    left_text += a.length()
    right_text += b.length()
    true
  }
  if limits.max_nodes < 1 {
    return Err(
      Diagnostic::new(LimitExceeded, "JSON equality node limit exceeded"),
    )
  }
  while stack.pop() is Some((left, right, depth)) {
    match (left.kind, right.kind) {
      (Null, Null) => ()
      (Boolean(a), Boolean(b)) => if a != b { return Ok(false) }
      (String(a), String(b)) => {
        if !charge_text(a, b) {
          return Err(
            Diagnostic::new(LimitExceeded, "JSON equality text limit exceeded"),
          )
        }
        if a != b {
          return Ok(false)
        }
      }
      (Numeric(a), Numeric(b)) => {
        if a.token.length() > limits.max_number ||
          b.token.length() > limits.max_number {
          return Err(
            Diagnostic::new(
              LimitExceeded,
              "JSON equality number token limit exceeded",
            ),
          )
        }
        if !charge_text(a.token, b.token) {
          return Err(
            Diagnostic::new(LimitExceeded, "JSON equality text limit exceeded"),
          )
        }
        if numeric {
          if !a.numeric_equal(b) {
            return Ok(false)
          }
        } else if a != b {
          return Ok(false)
        }
      }
      (Array(a), Array(b)) => {
        if a.length() != b.length() {
          return Ok(false)
        }
        if depth >= limits.max_depth {
          return Err(
            Diagnostic::new(
              LimitExceeded,
              "JSON equality nesting limit exceeded",
            ),
          )
        }
        if a.length() > limits.max_nodes - reserved {
          return Err(
            Diagnostic::new(LimitExceeded, "JSON equality node limit exceeded"),
          )
        }
        reserved += a.length()
        for i in 0..<a.length() {
          stack.push((a[i], b[i], depth + 1))
        }
      }
      (Object(a), Object(b)) => {
        if a.length() != b.length() {
          return Ok(false)
        }
        if depth >= limits.max_depth {
          return Err(
            Diagnostic::new(
              LimitExceeded,
              "JSON equality nesting limit exceeded",
            ),
          )
        }
        if a.length() > limits.max_nodes - reserved {
          return Err(
            Diagnostic::new(LimitExceeded, "JSON equality node limit exceeded"),
          )
        }
        reserved += a.length()
        for (key, _) in a {
          if !charge_text(key, "") {
            return Err(
              Diagnostic::new(
                LimitExceeded,
                "JSON equality key text limit exceeded",
              ),
            )
          }
        }
        for (key, _) in b {
          if !charge_text("", key) {
            return Err(
              Diagnostic::new(
                LimitExceeded,
                "JSON equality key text limit exceeded",
              ),
            )
          }
        }
        let lookup = Map::from_array(b)
        for (key, value) in a {
          guard lookup.get(key) is Some(found) else { return Ok(false) }
          stack.push((value, found, depth + 1))
        }
      }
      _ => return Ok(false)
    }
  }
  Ok(true)
}

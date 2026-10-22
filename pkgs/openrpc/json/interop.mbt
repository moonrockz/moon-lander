///|
priv enum CoreStep {
  VisitCore(Json, Int32)
  CoreArray(Int32)
  CoreObject(Array[String])
}

///|
/// Capture the representation the caller's core Json still has.
/// Missing original numeric digits cannot be recovered.
pub fn from_core_json(
  value : Json,
  limits~ : Limits = Limits::new(),
) -> Result[Value, Diagnostic] {
  let stack = [CoreStep::VisitCore(value, 0)]
  let values : Array[Value] = []
  let mut count = 0
  let mut reserved = 1
  let mut text_size = 0
  while stack.pop() is Some(step) {
    match step {
      CoreArray(size) => {
        let start = values.length() - size
        let value = Value::array(Array::makei(size, i => values[start + i]))
        values.truncate(start)
        values.push(value)
      }
      CoreObject(keys) => {
        let start = values.length() - keys.length()
        let value = Value::object(
          keys.mapi((i, key) => (key, values[start + i])),
        ).unwrap()
        values.truncate(start)
        values.push(value)
      }
      VisitCore(core, depth) => {
        if count >= limits.max_nodes {
          return Err(
            Diagnostic::new(
              LimitExceeded,
              "Core JSON import node limit exceeded",
            ),
          )
        }
        count += 1
        let charge = match core {
          Json::String(text) => text.length()
          Json::Number(_, repr~) => repr.map(s => s.length()).unwrap_or(0)
          _ => 1
        }
        if charge > limits.max_source - text_size {
          return Err(
            Diagnostic::new(
              LimitExceeded,
              "Core JSON import text limit exceeded",
            ),
          )
        }
        text_size += charge
        match core {
          Json::Null => values.push(Value::null())
          Json::True => values.push(Value::boolean(true))
          Json::False => values.push(Value::boolean(false))
          Json::String(text) => values.push(Value::string(text))
          Json::Number(number, repr~) => {
            let token = repr.unwrap_or_else(() => number.to_string())
            if token.length() > limits.max_number {
              return Err(
                Diagnostic::new(
                  LimitExceeded,
                  "Core JSON import number token limit exceeded",
                ),
              )
            }
            match Number::parse(token) {
              Ok(number) => values.push(Value::number(number))
              Err(d) => return Err(d)
            }
          }
          Json::Array(items) => {
            if items.length() > limits.max_nodes - reserved {
              return Err(
                Diagnostic::new(
                  LimitExceeded,
                  "Core JSON import node limit exceeded",
                ),
              )
            }
            reserved += items.length()
            if depth >= limits.max_depth {
              return Err(
                Diagnostic::new(
                  LimitExceeded,
                  "Core JSON import container limit exceeded",
                ),
              )
            }
            stack.push(CoreArray(items.length()))
            for i = items.length() - 1; i >= 0; i = i - 1 {
              stack.push(VisitCore(items[i], depth + 1))
            }
          }
          Json::Object(fields) => {
            if fields.length() > limits.max_nodes - reserved {
              return Err(
                Diagnostic::new(
                  LimitExceeded,
                  "Core JSON import node limit exceeded",
                ),
              )
            }
            reserved += fields.length()
            if depth >= limits.max_depth {
              return Err(
                Diagnostic::new(
                  LimitExceeded,
                  "Core JSON import container limit exceeded",
                ),
              )
            }
            let entries = fields.to_array()
            for (key, _) in entries {
              if key.length() > limits.max_source - text_size {
                return Err(
                  Diagnostic::new(
                    LimitExceeded,
                    "Core JSON import key text limit exceeded",
                  ),
                )
              }
              text_size += key.length()
            }
            stack.push(CoreObject(entries.map(entry => entry.0)))
            for i = entries.length() - 1; i >= 0; i = i - 1 {
              stack.push(VisitCore(entries[i].1, depth + 1))
            }
          }
        }
      }
    }
  }
  let value = values[0]
  match write(value, limits~) {
    Err(d) => Err(d)
    Ok(_) => Ok(value)
  }
}

///|
priv enum ExactStep {
  VisitExact(Value)
  ExactArray(Int32)
  ExactObject(Array[String])
}

///|
/// Set core numeric repr explicitly. Core arithmetic/equality still use Double.
pub fn to_core_json(
  value : Value,
  limits~ : Limits = Limits::new(),
) -> Result[Json, Diagnostic] {
  match write(value, limits~) {
    Err(d) => return Err(d)
    Ok(_) => ()
  }
  let stack = [ExactStep::VisitExact(value)]
  let values : Array[Json] = []
  while stack.pop() is Some(step) {
    match step {
      ExactArray(size) => {
        let start = values.length() - size
        let value = Json::array(Array::makei(size, i => values[start + i]))
        values.truncate(start)
        values.push(value)
      }
      ExactObject(keys) => {
        let start = values.length() - keys.length()
        let value = Json::object(
          Map::from_array(keys.mapi((i, key) => (key, values[start + i]))),
        )
        values.truncate(start)
        values.push(value)
      }
      VisitExact(exact) =>
        match exact.kind {
          Null => values.push(Json::null())
          Boolean(b) => values.push(Json::boolean(b))
          String(text) => values.push(Json::string(text))
          Numeric(number) => {
            let core = @core_json.parse(number.token[:]) catch {
              _ =>
                return Err(
                  Diagnostic::new(
                    InvalidNumber,
                    "Core JSON cannot represent this numeric token",
                  ),
                )
            }
            guard core is Json::Number(approximation, ..) else {
              return Err(
                Diagnostic::new(
                  InvalidNumber,
                  "Core JSON numeric conversion failed",
                ),
              )
            }
            values.push(Json::number(approximation, repr=number.token))
          }
          Array(items) => {
            stack.push(ExactArray(items.length()))
            for i = items.length() - 1; i >= 0; i = i - 1 {
              stack.push(VisitExact(items[i]))
            }
          }
          Object(fields) => {
            stack.push(ExactObject(fields.map(entry => entry.0)))
            for i = fields.length() - 1; i >= 0; i = i - 1 {
              stack.push(VisitExact(fields[i].1))
            }
          }
        }
    }
  }
  Ok(values[0])
}

///|
pub(all) enum Code {
  Syntax
  DuplicateKey
  LimitExceeded
  InvalidNumber
  InvalidReference
  UnresolvedReference
  WrongType
  MissingField
  UnsupportedVersion
  UnsupportedDialect
  UnsupportedCheck
  InvalidSchema
  ParameterOrder
  MissingBaseUri
  UnavailableResource
  ConflictingIdentifier
  ReferenceCycle
} derive(Eq, Debug)

///|
pub struct Span {
  start : Int32
  end : Int32
} derive(Eq, Debug)

///|
pub fn Span::new(start : Int32, end : Int32) -> Span? {
  if start >= 0 && end >= start {
    Some({ start, end, })
  } else {
    None
  }
}

///|
pub fn Span::start(self : Span) -> Int32 {
  self.start
}

///|
pub fn Span::end(self : Span) -> Int32 {
  self.end
}

///|
pub struct Diagnostic {
  code : Code
  message : String
  path : Array[String]
  span : Span?
  related : Array[Span]
} derive(Debug)

///|
pub fn Diagnostic::new(
  code : Code,
  message : String,
  path~ : Array[String] = [],
  span~ : Span? = None,
  related~ : Array[Span] = [],
) -> Diagnostic {
  { code, message, path: path.copy(), span, related: related.copy(), }
}

///|
pub fn Diagnostic::code(self : Diagnostic) -> Code {
  self.code
}

///|
pub fn Diagnostic::message(self : Diagnostic) -> String {
  self.message
}

///|
pub fn Diagnostic::path(self : Diagnostic) -> Array[String] {
  self.path.copy()
}

///|
pub fn Diagnostic::span(self : Diagnostic) -> Span? {
  self.span
}

///|
pub fn Diagnostic::related(self : Diagnostic) -> Array[Span] {
  self.related.copy()
}

///|
pub struct Limits {
  max_depth : Int32
  max_nodes : Int32
  max_source : Int32
  max_number : Int32
  max_findings : Int32
} derive(Debug)

///|
pub fn Limits::new(
  max_depth~ : Int32 = 256,
  max_nodes~ : Int32 = 100000,
  max_source~ : Int32 = 8388608,
  max_number~ : Int32 = 4096,
  max_findings~ : Int32 = 256,
) -> Limits {
  { max_depth, max_nodes, max_source, max_number, max_findings, }
}

///|
/// Remove policy bounds within the maximum representable String/Array sizes.
/// This does not guarantee available host memory.
pub fn Limits::unlimited() -> Limits {
  Limits::new(
    max_depth=2147483647,
    max_nodes=2147483647,
    max_source=2147483647,
    max_number=2147483647,
    max_findings=2147483647,
  )
}

///|
pub struct Number {
  token : String
} derive(Eq, Debug)

///|
pub fn Number::token(self : Number) -> String {
  self.token
}

///|
pub(all) enum Kind {
  Null
  Boolean(Bool)
  String(String)
  Numeric(Number)
  Array(Array[Value])
  Object(Array[(String, Value)])
} derive(Debug)

///|
pub struct Value {
  priv kind : Kind
} derive(Debug)

///|
pub fn Value::kind(self : Value) -> Kind {
  match self.kind {
    Array(items) => Array(items.copy())
    Object(fields) => Object(fields.copy())
    other => other
  }
}

///|
pub fn Value::null() -> Value {
  { kind: Null, }
}

///|
pub fn Value::boolean(value : Bool) -> Value {
  { kind: Boolean(value), }
}

///|
pub fn Value::string(value : String) -> Value {
  { kind: String(value), }
}

///|
pub fn Value::number(value : Number) -> Value {
  { kind: Numeric(value), }
}

///|
pub fn Value::array(items : Array[Value]) -> Value {
  { kind: Array(items.copy()), }
}

///|
pub fn Value::object(
  fields : Array[(String, Value)],
) -> Result[Value, Diagnostic] {
  let names : Set[String] = Set([])
  for (name, _) in fields {
    if names.contains(name) {
      return Err(
        Diagnostic::new(DuplicateKey, "Duplicate object member", path=[name]),
      )
    }
    names.add(name)
  }
  Ok({ kind: Object(fields.copy()), })
}

///|
pub fn Value::get(self : Value, name : String) -> Value? {
  match self.kind {
    Object(fields) => {
      for (key, value) in fields {
        if key == name {
          return Some(value)
        }
      }
      None
    }
    _ => None
  }
}

///|
pub fn Value::text(self : Value) -> String? {
  match self.kind {
    String(text) => Some(text)
    _ => None
  }
}

///|
/// Inspect array size without creating a copied collection view.
pub fn Value::array_length(self : Value) -> Int32? {
  match self.kind {
    Array(items) => Some(items.length())
    _ => None
  }
}

///|
/// Return an immutable array child, or None for a non-array or missing index.
pub fn Value::array_item(self : Value, index : Int32) -> Value? {
  match self.kind {
    Array(items) =>
      if index >= 0 && index < items.length() {
        Some(items[index])
      } else {
        None
      }
    _ => None
  }
}

///|
pub extend Code with Eq::{equal, not_equal}

///|
pub extend Code with @debug.Debug::{to_repr}

///|
pub extend Span with Eq::{equal, not_equal}

///|
pub extend Span with @debug.Debug::{to_repr}

///|
pub extend Diagnostic with @debug.Debug::{to_repr}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend Number with Eq::{equal, not_equal}

///|
pub extend Number with @debug.Debug::{to_repr}

///|
pub extend Kind with @debug.Debug::{to_repr}

///|
pub extend Value with @debug.Debug::{to_repr}

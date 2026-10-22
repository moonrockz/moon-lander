///|
pub(all) enum NodeKind {
  Scalar
  ArrayNode
  ObjectNode
} derive(Eq, Debug)

///|
pub struct Node {
  kind : NodeKind
  span : Span
  key : String?
  key_span : Span?
  children : Array[Int32]
  scalar : Value?
  parent : Int32?
  ordinal : Int32
} derive(Debug)

///|
pub fn Node::kind(self : Node) -> NodeKind {
  self.kind
}

///|
pub fn Node::span(self : Node) -> Span {
  self.span
}

///|
pub fn Node::key(self : Node) -> String? {
  self.key
}

///|
pub fn Node::key_span(self : Node) -> Span? {
  self.key_span
}

///|
pub fn Node::children(self : Node) -> Array[Int32] {
  self.children.copy()
}

///|
pub struct CstDocument {
  source : String
  source_id : String?
  nodes : Array[Node]
  limits : Limits
} derive(Debug)

///|
pub fn CstDocument::reproduce(self : CstDocument) -> String {
  self.source
}

///|
pub fn CstDocument::source_id(self : CstDocument) -> String? {
  self.source_id
}

///|
pub fn CstDocument::limits(self : CstDocument) -> Limits {
  self.limits
}

///|
pub fn CstDocument::nodes(self : CstDocument) -> Array[Node] {
  self.nodes.copy()
}

///|
pub fn CstDocument::path(self : CstDocument, index : Int32) -> Array[String]? {
  if index < 0 || index >= self.nodes.length() {
    return None
  }
  let path : Array[String] = []
  let mut current = self.nodes[index]
  while current.parent is Some(parent) {
    path.push(current.key.unwrap_or(current.ordinal.to_string()))
    current = self.nodes[parent]
  }
  Some(Array::makei(path.length(), i => path[path.length() - 1 - i]))
}

///|
pub fn CstDocument::span_at(self : CstDocument, path : Array[String]) -> Span? {
  let mut index = 0
  for part in path {
    let node = self.nodes[index]
    let mut next : Int32? = None
    for i, child in node.children {
      if self.nodes[child].key.unwrap_or(i.to_string()) == part {
        next = Some(child)
        break
      }
    }
    guard next is Some(found) else { return None }
    index = found
  }
  Some(self.nodes[index].span)
}

///|
pub fn CstDocument::lower(
  self : CstDocument,
) -> Result[Value, Array[Diagnostic]] {
  let values : Array[Value?] = Array::make(self.nodes.length(), None)
  let findings : Array[Diagnostic] = []
  for i = self.nodes.length() - 1; i >= 0; i = i - 1 {
    let node = self.nodes[i]
    match node.kind {
      Scalar => values[i] = node.scalar
      ArrayNode => {
        let items = []
        for child in node.children {
          if values[child] is Some(value) {
            items.push(value)
          }
        }
        values[i] = Some(Value::array(items))
      }
      ObjectNode => {
        let fields = []
        let seen : Map[String, Span] = Map([])
        for child in node.children {
          let entry = self.nodes[child]
          let name = entry.key.unwrap()
          if seen.get(name) is Some(first) {
            let bound = if self.limits.max_findings > 0 {
              self.limits.max_findings
            } else {
              1
            }
            if findings.length() >= bound - 1 {
              findings.push(
                Diagnostic::new(
                  LimitExceeded,
                  "JSON lowering finding limit exceeded",
                  path=self.path(child).unwrap(),
                  span=entry.key_span,
                ),
              )
              findings.sort_by((a, b) => {
                a.span.unwrap().start.compare(b.span.unwrap().start)
              })
              return Err(findings)
            }
            findings.push(
              Diagnostic::new(
                DuplicateKey,
                "Duplicate decoded object member",
                path=self.path(child).unwrap(),
                span=entry.key_span,
                related=[first],
              ),
            )
          } else {
            seen[name] = entry.key_span.unwrap()
          }
          if values[child] is Some(value) {
            fields.push((name, value))
          }
        }
        // Keep all occurrences in the CST. Never choose a duplicate's winner.
        values[i] = match Value::object(fields) {
          Ok(value) => Some(value)
          Err(_) => None
        }
      }
    }
  }
  if findings.is_empty() {
    Ok(values[0].unwrap())
  } else {
    findings.sort_by((a, b) => {
      a.span.unwrap().start.compare(b.span.unwrap().start)
    })
    Err(findings)
  }
}

///|
priv struct Frame {
  node : Int32
  object : Bool
  mut state : Int32
  mut key : (String, Span)?
}

///|
priv struct Parser {
  source : String
  limits : Limits
  mut pos : Int32
  nodes : Array[Node]
  frames : Array[Frame]
}

///|
priv suberror ReadError {
  ReadError(Diagnostic)
} derive(Debug)

///|
fn Parser::error(
  self : Parser,
  code : Code,
  message : String,
  start~ : Int32? = None,
) -> Diagnostic {
  Diagnostic::new(
    code,
    message,
    span=Some({ start: start.unwrap_or(self.pos), end: self.pos, }),
  )
}

///|
fn Parser::skip(self : Parser) -> Unit {
  while self.pos < self.source.length() {
    match self.source.code_unit_at(self.pos) {
      32 | 9 | 10 | 13 => self.pos += 1
      _ => break
    }
  }
}

///|
fn Parser::peek(self : Parser) -> UInt16? {
  if self.pos < self.source.length() {
    Some(self.source.code_unit_at(self.pos))
  } else {
    None
  }
}

///|
fn Parser::string_token(self : Parser) -> (String, Span) raise ReadError {
  let start = self.pos
  self.pos += 1
  let mut escaped = false
  let mut closed = false
  while self.pos < self.source.length() {
    let c = self.source.code_unit_at(self.pos)
    self.pos += 1
    if escaped {
      escaped = false
    } else if c == 92 {
      escaped = true
    } else if c == 34 {
      closed = true
      break
    }
  }
  if !closed {
    raise ReadError(
      self.error(Syntax, "Unterminated string", start=Some(start)),
    )
  }
  let value = @core_json.parse(self.source[start:self.pos]) catch {
    _ =>
      raise ReadError(
        self.error(Syntax, "Invalid JSON string", start=Some(start)),
      )
  }
  guard value is Json::String(text) else {
    raise ReadError(self.error(Syntax, "Expected string"))
  }
  (text, { start, end: self.pos, })
}

///|
fn Parser::value(self : Parser, key : (String, Span)?) -> Int32 raise ReadError {
  self.skip()
  if self.nodes.length() >= self.limits.max_nodes {
    raise ReadError(self.error(LimitExceeded, "JSON node limit exceeded"))
  }
  let start = self.pos
  let parent = self.frames.last().map(frame => frame.node)
  let ordinal = match parent {
    Some(index) => self.nodes[index].children.length()
    None => 0
  }
  let mut children = false
  let mut object = false
  let (kind, scalar) = match self.peek() {
    Some(123) | Some(91) => {
      if self.frames.length() >= self.limits.max_depth {
        raise ReadError(
          self.error(LimitExceeded, "JSON nesting limit exceeded"),
        )
      }
      object = self.peek() == Some(123)
      children = true
      self.pos += 1
      (if object { ObjectNode } else { ArrayNode }, None)
    }
    Some(34) => (Scalar, Some(Value::string(self.string_token().0)))
    None => raise ReadError(self.error(Syntax, "Expected a JSON value"))
    _ => {
      while self.peek() is Some(c) {
        if c == 32 ||
          c == 9 ||
          c == 10 ||
          c == 13 ||
          c == 44 ||
          c == 93 ||
          c == 125 {
          break
        }
        self.pos += 1
      }
      let token = self.source[start:self.pos].to_owned()
      let value = match token {
        "null" => Value::null()
        "true" => Value::boolean(true)
        "false" => Value::boolean(false)
        _ => {
          if token.length() > self.limits.max_number {
            raise ReadError(
              self.error(
                LimitExceeded,
                "JSON number token limit exceeded",
                start=Some(start),
              ),
            )
          }
          match Number::parse(token) {
            Ok(n) => Value::number(n)
            Err(_) =>
              raise ReadError(
                self.error(Syntax, "Invalid JSON scalar", start=Some(start)),
              )
          }
        }
      }
      (Scalar, Some(value))
    }
  }
  let index = self.nodes.length()
  self.nodes.push({
    kind,
    scalar,
    span: { start, end: self.pos, },
    key: key.map(k => k.0),
    key_span: key.map(k => k.1),
    children: [],
    parent,
    ordinal,
  })
  if children {
    self.frames.push({ node: index, object, state: 0, key: None, })
  }
  index
}

///|
fn Parser::close(self : Parser, frame : Frame) -> Unit {
  self.pos += 1
  let node = self.nodes[frame.node]
  self.nodes[frame.node] = {
    ..node,
    span: { start: node.span.start, end: self.pos, },
  }
  self.frames.pop() |> ignore
}

///|
fn Parser::run(self : Parser) -> Unit raise ReadError {
  self.value(None) |> ignore
  while !self.frames.is_empty() {
    self.skip()
    let frame = self.frames[self.frames.length() - 1]
    if frame.object {
      match frame.state {
        0 | 4 => {
          if frame.state == 0 && self.peek() == Some(125) {
            self.close(frame)
            continue
          }
          if self.peek() != Some(34) {
            raise ReadError(
              self.error(Syntax, "Expected an object member name"),
            )
          }
          frame.key = Some(self.string_token())
          frame.state = 1
        }
        1 => {
          if self.peek() != Some(58) {
            raise ReadError(self.error(Syntax, "Expected ':'"))
          }
          self.pos += 1
          frame.state = 2
        }
        2 => {
          frame.state = 3
          let child = self.value(frame.key)
          self.nodes[frame.node].children.push(child)
        }
        _ =>
          match self.peek() {
            Some(125) => self.close(frame)
            Some(44) => {
              self.pos += 1
              frame.state = 4
            }
            _ => raise ReadError(self.error(Syntax, "Expected ',' or '}'"))
          }
      }
    } else {
      match frame.state {
        0 | 2 => {
          if frame.state == 0 && self.peek() == Some(93) {
            self.close(frame)
            continue
          }
          frame.state = 1
          let child = self.value(None)
          self.nodes[frame.node].children.push(child)
        }
        _ =>
          match self.peek() {
            Some(93) => self.close(frame)
            Some(44) => {
              self.pos += 1
              frame.state = 2
            }
            _ => raise ReadError(self.error(Syntax, "Expected ',' or ']'"))
          }
      }
    }
  }
  self.skip()
  if self.pos != self.source.length() {
    raise ReadError(self.error(Syntax, "Unexpected trailing input"))
  }
}

///|
pub fn parse(
  source : String,
  source_id~ : String? = None,
  limits~ : Limits = Limits::new(),
) -> Result[CstDocument, Diagnostic] {
  if source.length() > limits.max_source {
    return Err(Diagnostic::new(LimitExceeded, "JSON source limit exceeded"))
  }
  let parser = Parser::{ source, limits, pos: 0, nodes: [], frames: [], }
  try {
    parser.run()
    Ok({ source, source_id, nodes: parser.nodes, limits, })
  } catch {
    ReadError(diagnostic) => Err(diagnostic)
  }
}

///|
pub extend NodeKind with Eq::{equal, not_equal}

///|
pub extend NodeKind with @debug.Debug::{to_repr}

///|
pub extend Node with @debug.Debug::{to_repr}

///|
pub extend CstDocument with @debug.Debug::{to_repr}

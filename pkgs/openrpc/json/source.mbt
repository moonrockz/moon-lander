///|
pub(all) enum TokenKind {
  Whitespace
  OpenObject
  CloseObject
  OpenArray
  CloseArray
  Colon
  Comma
  StringToken
  NumberToken
  TrueToken
  FalseToken
  NullToken
} derive(Eq, Debug)

///|
pub struct Token {
  kind : TokenKind
  span : Span
  text : String
} derive(Debug)

///|
pub fn Token::kind(self : Token) -> TokenKind {
  self.kind
}

///|
pub fn Token::span(self : Token) -> Span {
  self.span
}

///|
pub fn Token::text(self : Token) -> String {
  self.text
}

///|
pub fn CstDocument::slice(self : CstDocument, span : Span) -> String? {
  if span.end > self.source.length() {
    None
  } else {
    Some(self.source[span.start:span.end].to_owned())
  }
}

///|
/// Tokenize the already-checked source, including every trivia occurrence.
pub fn CstDocument::tokens(self : CstDocument) -> Array[Token] {
  let tokens = []
  let mut pos = 0
  while pos < self.source.length() {
    let start = pos
    let c = self.source.code_unit_at(pos)
    pos += 1
    let kind = match c {
      123 => OpenObject
      125 => CloseObject
      91 => OpenArray
      93 => CloseArray
      58 => Colon
      44 => Comma
      32 | 9 | 10 | 13 => {
        while pos < self.source.length() {
          match self.source.code_unit_at(pos) {
            32 | 9 | 10 | 13 => pos += 1
            _ => break
          }
        }
        Whitespace
      }
      34 => {
        while pos < self.source.length() {
          let next = self.source.code_unit_at(pos)
          pos += 1
          if next == 92 {
            pos += 1
          } else if next == 34 {
            break
          }
        }
        StringToken
      }
      _ => {
        while pos < self.source.length() {
          match self.source.code_unit_at(pos) {
            32 | 9 | 10 | 13 | 44 | 93 | 125 => break
            _ => pos += 1
          }
        }
        match c {
          116 => TrueToken
          102 => FalseToken
          110 => NullToken
          _ => NumberToken
        }
      }
    }
    tokens.push({
      kind,
      span: { start, end: pos, },
      text: self.source[start:pos].to_owned(),
    })
  }
  tokens
}

///|
pub struct Position {
  line : Int32
  column : Int32
} derive(Eq, Debug)

///|
pub fn Position::line(self : Position) -> Int32 {
  self.line
}

///|
pub fn Position::column(self : Position) -> Int32 {
  self.column
}

///|
pub struct Location {
  source_id : String?
  node_index : Int32
  value_span : Span
  key_span : Span?
} derive(Debug)

///|
pub fn Location::source_id(self : Location) -> String? {
  self.source_id
}

///|
/// Index into the owning CST only. It is not stable across parses or edits.
pub fn Location::node_index(self : Location) -> Int32 {
  self.node_index
}

///|
pub fn Location::value_span(self : Location) -> Span {
  self.value_span
}

///|
pub fn Location::key_span(self : Location) -> Span? {
  self.key_span
}

///|
pub struct SourceMap {
  cst : CstDocument
  line_starts : Array[Int32]
} derive(Debug)

///|
pub fn CstDocument::source_map(self : CstDocument) -> SourceMap {
  let line_starts = [0]
  let mut i = 0
  while i < self.source.length() {
    let c = self.source.code_unit_at(i)
    i += 1
    if c == 13 {
      if i < self.source.length() && self.source.code_unit_at(i) == 10 {
        i += 1
      }
      line_starts.push(i)
    } else if c == 10 {
      line_starts.push(i)
    }
  }
  { cst: self, line_starts, }
}

///|
pub fn SourceMap::position(self : SourceMap, offset : Int32) -> Position? {
  if offset < 0 || offset > self.cst.source.length() {
    return None
  }
  let mut low = 0
  let mut high = self.line_starts.length()
  while low + 1 < high {
    let mid = low + (high - low) / 2
    if self.line_starts[mid] <= offset {
      low = mid
    } else {
      high = mid
    }
  }
  Some({ line: low + 1, column: offset - self.line_starts[low] + 1, })
}

///|
/// Return all occurrences. Duplicate object names have no implicit winner.
pub fn SourceMap::locations(
  self : SourceMap,
  path : Array[String],
) -> Array[Location] {
  let mut indices = [0]
  for part in path {
    let next = []
    for index in indices {
      let node = self.cst.nodes[index]
      for ordinal, child in node.children {
        if self.cst.nodes[child].key.unwrap_or(ordinal.to_string()) == part {
          next.push(child)
        }
      }
    }
    indices = next
    if indices.is_empty() {
      break
    }
  }
  indices.map(index => {
    let node = self.cst.nodes[index]
    {
      source_id: self.cst.source_id,
      node_index: index,
      value_span: node.span,
      key_span: node.key_span,
    }
  })
}

///|
pub extend TokenKind with Eq::{equal, not_equal}

///|
pub extend TokenKind with @debug.Debug::{to_repr}

///|
pub extend Token with @debug.Debug::{to_repr}

///|
pub extend Position with Eq::{equal, not_equal}

///|
pub extend Position with @debug.Debug::{to_repr}

///|
pub extend Location with @debug.Debug::{to_repr}

///|
pub extend SourceMap with @debug.Debug::{to_repr}

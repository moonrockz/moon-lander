///|
/// A handle to one CST node. It is valid only for a CST with exactly the same
/// source text as the parse that produced it.
pub struct NodeId {
  priv index : Int
  priv source : String
}

///|
pub impl @debug.Debug for NodeId with to_repr(self) {
  @debug.Repr::opaque_("NodeId", @debug.Repr::integer(self.index.to_string()))
}

///|
pub fn NodeId::index(self : NodeId) -> Int {
  self.index
}

///|
pub fn CstDocument::node_id(self : CstDocument, index : Int) -> NodeId? {
  if index >= 0 && index < self.nodes.length() {
    Some({ index, source: self.source })
  } else {
    None
  }
}

///|
/// The first node at a structured path. Duplicate names have several nodes;
/// `SourceMap::locations` lists them all.
pub fn CstDocument::node_at(
  self : CstDocument,
  path : Array[String],
) -> NodeId? {
  match self.source_map().locations(path) {
    [first, ..] => Some(first.node())
    [] => None
  }
}

///|
/// Replace the value at `node` with the compact encoding of `value` and parse
/// the result. Every code unit outside the value's span is kept, including a
/// member's key and the whitespace around it. The original CST is unchanged.
pub fn CstDocument::replace_value(
  self : CstDocument,
  node : NodeId,
  value : Value,
  limits? : Limits,
) -> Result[CstDocument, Diagnostic] {
  if node.source != self.source || node.index >= self.nodes.length() {
    return Err(
      Diagnostic::new(
        StaleNode,
        "Node identity belongs to a different source text",
      ),
    )
  }
  let limits = limits.unwrap_or(self.limits)
  let span = self.nodes[node.index].span
  let text = match write(value, limits~) {
    Ok(text) => text
    Err(d) => return Err(d)
  }
  let kept = self.source.length() - (span.end - span.start)
  if text.length() > limits.max_source - kept {
    return Err(Diagnostic::new(LimitExceeded, "JSON source limit exceeded"))
  }
  let edited = self.source[:span.start].to_owned() +
    text +
    self.source[span.end:].to_owned()
  parse(edited, source_id=self.source_id, limits~)
}

///|
pub extend NodeId with @debug.Debug::{to_repr}

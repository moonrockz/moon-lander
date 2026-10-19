///|
/// A consumer-defined format uses the shared engine without editing it.
priv enum OtherNode {
  Document(ReadOnlyArray[OtherNode])
  Snippet(String)
} derive(Eq)

///|
impl @notebooks.Node for OtherNode with fn children(self) {
  match self {
    Document(children) => children
    Snippet(_) => []
  }
}

///|
impl @notebooks.Node for OtherNode with fn kind(self) {
  match self {
    Document(_) => @notebooks.NodeKind::Notebook
    Snippet(_) => @notebooks.Cell(@notebooks.Code)
  }
}

///|
// Source and metadata intentionally use the trait's default implementation.
test "consumer-defined notebook nodes can use shared cursors and folds" {
  let root = OtherNode::Document([Snippet("source")])
  @expect.expect(own_metadata(root)).to_equal(None)
  let cursor = @notebooks.Cursor(root)
  guard cursor.first_child() is Some(child) else { fail("no child") }
  @expect.expect_all(s => {
    s.expect(child.path().to_string()).to_equal("$[0]")
    s.expect(@notebooks.Node::source(child.node())).to_equal(None)
    s.expect(@notebooks.fold(root, 0, (count, _) => count + 1)).to_equal(2)
  })
}

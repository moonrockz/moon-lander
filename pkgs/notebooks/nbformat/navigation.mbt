///|
/// A concrete Jupyter traversal node. Notebooks contain cells; code cells
/// contain outputs; Markdown and raw cells contain attachments. Output and
/// attachment nodes are leaves. Metadata and MIME JSON use their own accessors.
pub(all) enum Node {
  /// A root document whose children are its cells.
  Notebook(Notebook)
  /// A cell whose children are stored outputs or attachments.
  Cell(Cell)
  /// A stored output leaf with its typed payload.
  Output(Output)
  /// A named attachment leaf with its immutable MIME bundle.
  Attachment(name~ : String, data~ : MimeBundle)
} derive(Eq, Debug)

///|
pub extend Node with Eq::{equal, not_equal}

///|
pub extend Node with @debug.Debug::{to_repr}

///|
/// Wrap this notebook as the concrete root accepted by shared traversal.
pub fn Notebook::root(self : Notebook) -> Node {
  Notebook(self)
}

///|
/// Return immutable children. Cells and outputs retain stored order;
/// attachments use lexical filename order. Metadata is not a traversal child.
pub fn Node::children(self : Node) -> ReadOnlyArray[Node] {
  match self {
    Notebook(book) => book.cells.map(cell => Node::Cell(cell))
    Cell(cell) =>
      match cell.content {
        Code(outputs~, ..) => outputs.map(output => Node::Output(output))
        Markdown(attachments=Some(attachments), ..)
        | Raw(attachments=Some(attachments), ..) =>
          attachments.entries.map(entry => {
            Attachment(name=entry.0, data=entry.1)
          })
        _ => []
      }
    Output(_) | Attachment(_) => []
  }
}

///|
/// Shared navigation types. Explicit cursor annotations use Cursor[Node].
pub using @notebooks {type Cursor, type NodePath, type Control, type Metadata}

///|
/// Classify this node for format-independent traversal without converting
/// or discarding the concrete Jupyter payload.
pub fn Node::kind(self : Node) -> @notebooks.NodeKind {
  match self {
    Notebook(_) => @notebooks.NodeKind::Notebook
    Cell(cell) => @notebooks.NodeKind::Cell(cell.kind())
    Output(output) => @notebooks.NodeKind::Output(output.output_type())
    Attachment(name~, ..) => @notebooks.NodeKind::Attachment(name)
  }
}

///|
/// Return a recognized cell's normalized source. Notebook, output,
/// attachment and unknown-cell nodes return None.
pub fn Node::source(self : Node) -> String? {
  match self {
    Cell(cell) => cell.source()
    _ => None
  }
}

///|
pub impl @notebooks.Node for Node with fn children(self) {
  self.children()
}

///|
pub impl @notebooks.Node for Node with fn kind(self) {
  self.kind()
}

///|
pub impl @notebooks.Node for Node with fn source(self) {
  self.source()
}

///|
/// Start a typed Jupyter cursor at this notebook, with depth zero and path `$`.
pub fn Notebook::cursor(self : Notebook) -> Cursor[Node] {
  Cursor::Cursor(self.root())
}

///|
/// Start a new navigation root at this node. Use an existing cursor to
/// retain its original ancestors and paths.
pub fn Node::cursor(self : Node) -> Cursor[Node] {
  Cursor::Cursor(self)
}

///|
/// Resolve a shared child-index path relative to this node. Return None
/// for any invalid index. The path does not refer to JSON object fields.
pub fn Node::at(self : Node, path : NodePath) -> Node? {
  @notebooks.at(self, path)
}

///|
/// Use the shared engine to walk Jupyter positions from a new root.
/// Callbacks retain typed Node payloads. SkipChildren still receives leave;
/// Stop returns immediately without pending leave callbacks.
pub fn walk_cursor(
  root : Node,
  enter : (Cursor[Node]) -> Control,
  leave~ : (Cursor[Node]) -> Unit = _ => (),
) -> Unit {
  @notebooks.walk_cursor(root, enter, leave~)
}

///|
/// Walk Jupyter nodes in depth-first pre-order with the shared engine.
/// Use walk_cursor when callbacks need path, parent or sibling context.
pub fn walk(
  root : Node,
  enter : (Node) -> Control,
  leave~ : (Node) -> Unit = _ => (),
) -> Unit {
  @notebooks.walk(root, enter, leave~)
}

///|
/// Thread an accumulator through this notebook tree in pre-order. Callbacks
/// receive typed Jupyter cursors. Use walk for pruning or early termination.
pub fn[A] Notebook::fold(
  self : Notebook,
  init : A,
  f : (A, Cursor[Node]) -> A,
) -> A {
  @notebooks.fold(self.root(), init, f)
}

///|
/// Return this node's own metadata. Some(empty) retains an empty container;
/// None means this node has none. Ancestor metadata is never inherited.
pub fn Node::metadata(self : Node) -> Metadata? {
  match self {
    Notebook(book) => Some(book.metadata())
    Cell(cell) => Some(cell.metadata())
    Output(output) =>
      match output.content() {
        DisplayData(metadata~, ..) | ExecuteResult(metadata~, ..) =>
          Some(metadata)
        _ => None
      }
    Attachment(_) => None
  }
}

///|
pub impl @notebooks.Node for Node with fn metadata(self) {
  self.metadata()
}

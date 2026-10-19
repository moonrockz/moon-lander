///|
/// Shared navigation types. Explicit cursor annotations use Cursor[Node].
pub using @notebooks {type Cursor, type NodePath, type Control, type Metadata}

///|
/// A concrete DIB traversal node. Notebook children are cells in source
/// order; cell children are retained directives in source order. Directives
/// are leaves. Metadata and kernel registrations use their own accessors.
pub(all) enum Node {
  /// A root document whose children are its source cells.
  Notebook(Notebook)
  /// A source cell whose children are retained directives.
  Cell(Cell)
  /// A retained #! source line with unparsed arguments and a relative line.
  Directive(Directive)
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
/// Return immutable cells or directives in source order. Directive leaves
/// have no children. Kernel selectors are properties of cells, not children.
pub fn Node::children(self : Node) -> ReadOnlyArray[Node] {
  match self {
    Notebook(book) => book.cells.map(cell => Node::Cell(cell))
    Cell(cell) => cell.directives().map(directive => Node::Directive(directive))
    Directive(_) => []
  }
}

///|
/// Classify this concrete node for shared traversal. Directive kinds retain
/// the command name, while concrete nodes retain the complete directive.
pub fn Node::kind(self : Node) -> @notebooks.NodeKind {
  match self {
    Notebook(_) => @notebooks.NodeKind::Notebook
    Cell(cell) => @notebooks.NodeKind::Cell(cell.kind())
    Directive(directive) => @notebooks.NodeKind::Directive(directive.name)
  }
}

///|
/// Return normalized cell source or a directive's source line. Return None
/// for a notebook node.
pub fn Node::source(self : Node) -> String? {
  match self {
    Notebook(_) => None
    Cell(cell) => Some(cell.source)
    Directive(directive) => Some(directive.text)
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
/// Start a typed DIB cursor at this notebook with depth zero and path `$`.
pub fn Notebook::cursor(self : Notebook) -> Cursor[Node] {
  Cursor::Cursor(self.root())
}

///|
/// Establish a new navigation root at this node. Use an existing cursor
/// to retain its original paths and ancestors.
pub fn Node::cursor(self : Node) -> Cursor[Node] {
  Cursor::Cursor(self)
}

///|
/// Resolve a shared child-index path relative to this node, returning None
/// for any invalid index. Cell child indices refer to retained directives.
pub fn Node::at(self : Node, path : NodePath) -> Node? {
  @notebooks.at(self, path)
}

///|
/// Use the shared engine to walk typed DIB positions from a new root.
/// SkipChildren still receives leave; Stop cancels pending leave calls.
pub fn walk_cursor(
  root : Node,
  enter : (Cursor[Node]) -> Control,
  leave~ : (Cursor[Node]) -> Unit = _ => (),
) -> Unit {
  @notebooks.walk_cursor(root, enter, leave~)
}

///|
/// Walk concrete DIB nodes in depth-first pre-order with the shared engine.
/// Use walk_cursor when callbacks need path or ancestor context.
pub fn walk(
  root : Node,
  enter : (Node) -> Control,
  leave~ : (Node) -> Unit = _ => (),
) -> Unit {
  @notebooks.walk(root, enter, leave~)
}

///|
/// Thread an accumulator through this notebook tree in pre-order, supplying
/// typed DIB cursors. Use walk for pruning or early termination.
pub fn[A] Notebook::fold(
  self : Notebook,
  init : A,
  f : (A, Cursor[Node]) -> A,
) -> A {
  @notebooks.fold(self.root(), init, f)
}

///|
/// Resolve a canonical name or alias, then select matching cells in source
/// order. Return an empty immutable array for an unknown name. Markdown is
/// a selectable pseudo-kernel.
pub fn Notebook::cells_for_kernel(
  self : Notebook,
  name : String,
) -> ReadOnlyArray[Cell] {
  guard self.registry.resolve(name) is Some(kernel) else { return [] }
  ReadOnlyArray::from_iter(
    self.cells.iter().filter(cell => cell.kernel == kernel),
  )
}

///|
/// Return this node's own metadata. Some(empty) retains an empty container;
/// None means this node has none. Ancestor metadata is never inherited.
pub fn Node::metadata(self : Node) -> Metadata? {
  match self {
    Notebook(book) => Some(book.metadata())
    Cell(_) | Directive(_) => None
  }
}

///|
pub impl @notebooks.Node for Node with fn metadata(self) {
  self.metadata()
}

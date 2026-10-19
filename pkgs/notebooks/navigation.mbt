///|
/// The common role of a cell, independent of its file format.
/// Unknown retains the original format's cell-type name.
pub(all) enum CellKind {
  /// Executable source, with stored outputs when supported by the format.
  Code
  /// Markdown source; rendering is outside this library.
  Markdown
  /// Source intended to pass through an exporter without Markdown rendering.
  Raw
  /// A cell type introduced by a format extension or a future revision.
  Unknown(String)
} derive(Eq, Debug)

///|
pub extend CellKind with Eq::{equal, not_equal}

///|
pub extend CellKind with @debug.Debug::{to_repr}

///|
/// The role of a node during shared traversal. Output variants carry the
/// output type; attachments carry filenames; directives carry command names.
/// Use the concrete node value to inspect format-specific payloads.
pub(all) enum NodeKind {
  /// The root document containing ordered cells.
  Notebook
  /// A cell classified by its common source role.
  Cell(CellKind)
  /// A stored code result, carrying its format-specific output type name.
  Output(String)
  /// A cell attachment, carrying its filename.
  Attachment(String)
  /// A retained source directive, carrying its command name without #!.
  Directive(String)
} derive(Eq, Debug)

///|
pub extend NodeKind with Eq::{equal, not_equal}

///|
pub extend NodeKind with @debug.Debug::{to_repr}

///|
/// A contract for a finite, immutable notebook tree with stable child order.
/// The concrete Self type retains format-specific payloads. Implementations
/// must not return children that alias mutable state or introduce cycles.
pub(open) trait Node {
  /// Return direct children in stable document order, or an empty array for a leaf.
  fn children(Self) -> ReadOnlyArray[Self]
  /// Classify a node while leaving its complete payload in Self.
  fn kind(Self) -> NodeKind
  /// Return available source text. Defaults to None for nodes without source.
  fn source(Self) -> String? = _
  /// Return this node's own metadata, without inheriting from its ancestors.
  /// Some(empty) means an available empty container; None means no container.
  /// Defaults to None so implementations without metadata need no override.
  fn metadata(Self) -> Metadata? = _
}

///|
impl Node with fn metadata(_self) {
  None
}

///|
impl Node with fn source(_self) {
  None
}

///|
/// An immutable sequence of zero-based child indices relative to a tree root.
/// The empty path denotes that root. Paths describe traversal children, not
/// JSON keys or persistent cell IDs; they may not resolve in another tree.
struct NodePath {
  indices : ReadOnlyArray[Int32]
} derive(Eq, Debug)

///|
pub extend NodePath with Eq::{equal, not_equal}

///|
pub extend NodePath with @debug.Debug::{to_repr}

///|
/// Create a path from immutable child indices. Negative and out-of-range
/// indices are permitted here and cause `at` to return None when resolved.
///
/// ```mbt check
/// test "doc: describe a child path" {
///   let path = @notebooks.NodePath([1, 0])
///   @expect.expect_all(s => {
///     s.expect(path.indices()).to_equal([1, 0])
///     s.expect(path.to_string()).to_equal("$[1][0]")
///     s.expect(@notebooks.NodePath([]).to_string()).to_equal("$")
///   })
/// }
/// ```
pub fn NodePath::NodePath(indices : ReadOnlyArray[Int32]) -> NodePath {
  { indices, }
}

///|
/// Return the immutable child indices in root-to-node order.
pub fn NodePath::indices(self : NodePath) -> ReadOnlyArray[Int32] {
  self.indices
}

///|
/// Render a traversal path, such as `$`, `$[0]` or `$[0][1]`.
pub fn NodePath::to_string(self : NodePath) -> String {
  "$" + self.indices.map(index => "[\{index}]").join("")
}

///|
/// Resolve a traversal path relative to root. Return None for any invalid
/// child index, including a negative index. An empty path returns root.
pub fn[N : Node] at(root : N, path : NodePath) -> N? {
  let mut current = root
  for index in path.indices {
    guard current.children().get(index) is Some(child) else { return None }
    current = child
  }
  Some(current)
}

///|
priv enum CursorContext[N] {
  Root
  Child(parent~ : Cursor[N], siblings~ : ReadOnlyArray[N], index~ : Int32)
}

///|
/// An immutable position in a tree of concrete nodes N. Moves return new
/// positions; retaining a cursor saves its node, path and ancestors.
/// Parent navigation never goes above the root passed to the constructor.
struct Cursor[N] {
  node : N
  context : CursorContext[N]
  depth : Int32
}

///|
/// Establish a new navigation root at this node, with depth zero and path `$`.
/// Constructing from a descendant discards its previous ancestor context.
pub fn[N] Cursor::Cursor(root : N) -> Cursor[N] {
  { node: root, context: Root, depth: 0, }
}

///|
/// Return the concrete node at this position without converting its payload.
pub fn[N] Cursor::node(self : Cursor[N]) -> N {
  self.node
}

///|
/// Return the number of edges from this cursor's navigation root.
pub fn[N] Cursor::depth(self : Cursor[N]) -> Int32 {
  self.depth
}

///|
/// Build the path from this cursor's original root to its current node.
/// The result remains stable when other cursors navigate the same tree.
pub fn[N] Cursor::path(self : Cursor[N]) -> NodePath {
  let indices = []
  let mut current = self
  while current.context is Child(parent~, index~, ..) {
    indices.push(index)
    current = parent
  }
  { indices: ReadOnlyArray::from_iter(indices.rev_iter()), }
}

///|
/// Return the saved parent position, or None at the navigation root.
pub fn[N] Cursor::parent(self : Cursor[N]) -> Cursor[N]? {
  match self.context {
    Root => None
    Child(parent~, ..) => Some(parent)
  }
}

///|
fn[N] Cursor::child_at(
  self : Cursor[N],
  siblings : ReadOnlyArray[N],
  index : Int32,
) -> Cursor[N] {
  {
    node: siblings[index],
    context: Child(parent=self, siblings~, index~),
    depth: self.depth + 1,
  }
}

///|
/// Move to the first child in document order, or return None for a leaf.
pub fn[N : Node] Cursor::first_child(self : Cursor[N]) -> Cursor[N]? {
  let children = self.node.children()
  if children.is_empty() {
    None
  } else {
    Some(self.child_at(children, 0))
  }
}

///|
/// Move to the last child in document order, or return None for a leaf.
pub fn[N : Node] Cursor::last_child(self : Cursor[N]) -> Cursor[N]? {
  let children = self.node.children()
  if children.is_empty() {
    None
  } else {
    Some(self.child_at(children, children.length() - 1))
  }
}

///|
/// Move to the following sibling, retaining the same parent. Return None
/// at the last sibling or at the navigation root.
pub fn[N] Cursor::next_sibling(self : Cursor[N]) -> Cursor[N]? {
  match self.context {
    Child(parent~, siblings~, index~) if index + 1 < siblings.length() =>
      Some(parent.child_at(siblings, index + 1))
    _ => None
  }
}

///|
/// Move to the preceding sibling, retaining the same parent. Return None
/// at the first sibling or at the navigation root.
pub fn[N] Cursor::previous_sibling(self : Cursor[N]) -> Cursor[N]? {
  match self.context {
    Child(parent~, siblings~, index~) if index > 0 =>
      Some(parent.child_at(siblings, index - 1))
    _ => None
  }
}

///|
/// Return immutable positions for all direct children in document order.
/// Each position retains this cursor as its parent.
pub fn[N : Node] Cursor::children(self : Cursor[N]) -> ReadOnlyArray[Cursor[N]] {
  let children = self.node.children()
  children.mapi((i, _) => self.child_at(children, i))
}

///|
/// A decision returned by an enter callback during depth-first traversal.
/// Continue descends, SkipChildren prunes but still calls leave, and Stop
/// returns immediately without calling any pending leave callbacks.
pub(all) enum Control {
  /// Visit descendants, then call leave for this node.
  Continue
  /// Omit descendants, but still call leave for this node.
  SkipChildren
  /// End traversal immediately, without this or any pending leave callbacks.
  Stop
} derive(Eq, Debug)

///|
pub extend Control with Eq::{equal, not_equal}

///|
pub extend Control with @debug.Debug::{to_repr}

///|
priv enum WalkFrame[N] {
  Enter(Cursor[N])
  Leave(Cursor[N])
}

///|
/// Walk this subtree in depth-first pre-order, retaining original paths and
/// ancestors. Call leave after descendants, including for a pruned node.
/// Stop ends immediately without pending leaves. Saved positions and moves
/// inside callbacks do not affect the walk. Uses an explicit stack.
pub fn[N : Node] Cursor::walk(
  self : Cursor[N],
  enter : (Cursor[N]) -> Control,
  leave~ : (Cursor[N]) -> Unit = _ => (),
) -> Unit {
  let pending = [WalkFrame::Enter(self)]
  while pending.pop() is Some(frame) {
    match frame {
      Leave(cursor) => leave(cursor)
      Enter(cursor) =>
        match enter(cursor) {
          Stop => return
          SkipChildren => leave(cursor)
          Continue => {
            pending.push(Leave(cursor))
            let children = cursor.children()
            for i = children.length() - 1; i >= 0; i = i - 1 {
              pending.push(Enter(children[i]))
            }
          }
        }
    }
  }
}

///|
/// Walk from a new root, supplying typed cursor positions to callbacks.
/// Enter runs before children and leave after them. SkipChildren still
/// receives leave; Stop returns immediately without pending leave calls.
pub fn[N : Node] walk_cursor(
  root : N,
  enter : (Cursor[N]) -> Control,
  leave~ : (Cursor[N]) -> Unit = _ => (),
) -> Unit {
  Cursor::Cursor(root).walk(enter, leave~)
}

///|
/// Walk concrete nodes in depth-first pre-order from a new root.
/// Use walk_cursor when callbacks need parent, sibling or path context.
/// SkipChildren still receives leave; Stop cancels pending leave callbacks.
pub fn[N : Node] walk(
  root : N,
  enter : (N) -> Control,
  leave~ : (N) -> Unit = _ => (),
) -> Unit {
  walk_cursor(root, cursor => enter(cursor.node()), leave=cursor => {
    leave(cursor.node())
  })
}

///|
/// Thread an accumulator through every node of this subtree in pre-order.
/// Callbacks receive typed cursors with the original paths and ancestors.
/// Use walk when pruning or early termination is needed.
pub fn[N : Node, A] Cursor::fold(
  self : Cursor[N],
  init : A,
  f : (A, Cursor[N]) -> A,
) -> A {
  let mut acc = init
  self.walk(cursor => {
    acc = f(acc, cursor)
    Continue
  })
  acc
}

///|
/// Thread an accumulator through every node in pre-order, establishing a
/// new cursor root. The callback returns the next accumulator and receives
/// the concrete node through its typed cursor. Use walk for pruning or stop.
pub fn[N : Node, A] fold(root : N, init : A, f : (A, Cursor[N]) -> A) -> A {
  Cursor::Cursor(root).fold(init, f)
}

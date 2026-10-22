///|
/// The `package_data.json` of `moonrockz/notebooks`, written by `moon doc` in `pkgs/notebooks` with
/// the pinned MoonBit toolchain 0.10.17+093cb8f9c (moon 0.1.20261021). Copy it again when the pin
/// changes the format.
let notebooks_package_data : String =
  #|{
  #|  "name": "moonrockz/notebooks",
  #|  "traits": [
  #|    {
  #|      "name": "CellView",
  #|      "docstring": "\n An immutable, format-independent cell view suitable for mixed collections.\n All methods are object-safe, so cells from different formats can be stored\n together as &CellView. Tree navigation remains on each format's Node type.",
  #|      "signature": "pub(open) trait CellView {\n  fn kind(Self) -> <a href=\"moonrockz/notebooks#CellKind\">CellKind</a>\n  fn source(Self) -> String?\n  fn metadata(Self) -> <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>? = _\n  fn mime_capability(Self) -> &<a href=\"moonrockz/notebooks#MimeTyped\">MimeTyped</a>? = _\n}",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "cell.mbt",
  #|        "line": 5,
  #|        "column": 1
  #|      },
  #|      "impls": [],
  #|      "object_type_info": {
  #|        "name": "&CellView",
  #|        "impls": [],
  #|        "methods": []
  #|      }
  #|    },
  #|    {
  #|      "name": "MimeTyped",
  #|      "docstring": "\n An optional capability for querying the MIME representations of a cell.\n Implementing this trait means lookup is supported, even when a particular\n cell has no representations. Formats without MIME data should omit it.",
  #|      "signature": "pub(open) trait MimeTyped {\n  fn has_mime_type(Self, String) -> Bool\n}",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "mime_query.mbt",
  #|        "line": 5,
  #|        "column": 1
  #|      },
  #|      "impls": [],
  #|      "object_type_info": {
  #|        "name": "&MimeTyped",
  #|        "impls": [],
  #|        "methods": []
  #|      }
  #|    },
  #|    {
  #|      "name": "Node",
  #|      "docstring": "\n A contract for a finite, immutable notebook tree with stable child order.\n The concrete Self type retains format-specific payloads. Implementations\n must not return children that alias mutable state or introduce cycles.",
  #|      "signature": "pub(open) trait Node {\n  fn children(Self) -> ReadOnlyArray[Self]\n  fn kind(Self) -> <a href=\"moonrockz/notebooks#NodeKind\">NodeKind</a>\n  fn source(Self) -> String? = _\n  fn metadata(Self) -> <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>? = _\n}",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "navigation.mbt",
  #|        "line": 48,
  #|        "column": 1
  #|      },
  #|      "impls": [],
  #|      "object_type_info": {
  #|        "name": "&Node",
  #|        "impls": [],
  #|        "methods": []
  #|      }
  #|    }
  #|  ],
  #|  "errors": [
  #|    {
  #|      "name": "MetadataError",
  #|      "docstring": "\n A metadata shape or format-conversion failure.",
  #|      "signature": "pub(all) suberror MetadataError {\n  ExpectedObject\n  InvalidKey(String)\n  NotJson(path~ : String, reason~ : String)\n} derive(<a href=\"moonbitlang/core/builtin#Eq\">Eq</a>, <a href=\"moonbitlang/core/debug#Debug\">@moonbitlang/core/debug.Debug</a>)",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "metadata.mbt",
  #|        "line": 3,
  #|        "column": 19
  #|      },
  #|      "methods": [
  #|        {
  #|          "name": "equal",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>::equal(<a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>, <a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>) -> Bool",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 10,
  #|            "column": 36
  #|          }
  #|        },
  #|        {
  #|          "name": "message",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>::message(self : <a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>) -> String",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 16,
  #|            "column": 23
  #|          }
  #|        },
  #|        {
  #|          "name": "not_equal",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>::not_equal(x : <a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>, y : <a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>) -> Bool",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 10,
  #|            "column": 43
  #|          }
  #|        },
  #|        {
  #|          "name": "to_repr",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>::to_repr(<a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>) -> <a href=\"moonbitlang/core/debug#Repr\">@moonbitlang/core/debug.Repr</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 13,
  #|            "column": 46
  #|          }
  #|        }
  #|      ],
  #|      "impls": []
  #|    }
  #|  ],
  #|  "types": [
  #|    {
  #|      "name": "CellKind",
  #|      "docstring": "\n The common role of a cell, independent of its file format.\n Unknown retains the original format's cell-type name.",
  #|      "signature": "pub(all) enum CellKind {\n  Code\n  Markdown\n  Raw\n  Unknown(String)\n} derive(<a href=\"moonbitlang/core/builtin#Eq\">Eq</a>, <a href=\"moonbitlang/core/debug#Debug\">@moonbitlang/core/debug.Debug</a>)",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "navigation.mbt",
  #|        "line": 4,
  #|        "column": 15
  #|      },
  #|      "methods": [
  #|        {
  #|          "name": "equal",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#CellKind\">CellKind</a>::equal(<a href=\"moonrockz/notebooks#CellKind\">CellKind</a>, <a href=\"moonrockz/notebooks#CellKind\">CellKind</a>) -> Bool",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 16,
  #|            "column": 31
  #|          }
  #|        },
  #|        {
  #|          "name": "not_equal",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#CellKind\">CellKind</a>::not_equal(x : <a href=\"moonrockz/notebooks#CellKind\">CellKind</a>, y : <a href=\"moonrockz/notebooks#CellKind\">CellKind</a>) -> Bool",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 16,
  #|            "column": 38
  #|          }
  #|        },
  #|        {
  #|          "name": "to_repr",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#CellKind\">CellKind</a>::to_repr(<a href=\"moonrockz/notebooks#CellKind\">CellKind</a>) -> <a href=\"moonbitlang/core/debug#Repr\">@moonbitlang/core/debug.Repr</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 19,
  #|            "column": 41
  #|          }
  #|        }
  #|      ],
  #|      "impls": []
  #|    },
  #|    {
  #|      "name": "Control",
  #|      "docstring": "\n A decision returned by an enter callback during depth-first traversal.\n Continue descends, SkipChildren prunes but still calls leave, and Stop\n returns immediately without calling any pending leave callbacks.",
  #|      "signature": "pub(all) enum Control {\n  Continue\n  SkipChildren\n  Stop\n} derive(<a href=\"moonbitlang/core/builtin#Eq\">Eq</a>, <a href=\"moonbitlang/core/debug#Debug\">@moonbitlang/core/debug.Debug</a>)",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "navigation.mbt",
  #|        "line": 253,
  #|        "column": 15
  #|      },
  #|      "methods": [
  #|        {
  #|          "name": "equal",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Control\">Control</a>::equal(<a href=\"moonrockz/notebooks#Control\">Control</a>, <a href=\"moonrockz/notebooks#Control\">Control</a>) -> Bool",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 263,
  #|            "column": 30
  #|          }
  #|        },
  #|        {
  #|          "name": "not_equal",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Control\">Control</a>::not_equal(x : <a href=\"moonrockz/notebooks#Control\">Control</a>, y : <a href=\"moonrockz/notebooks#Control\">Control</a>) -> Bool",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 263,
  #|            "column": 37
  #|          }
  #|        },
  #|        {
  #|          "name": "to_repr",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Control\">Control</a>::to_repr(<a href=\"moonrockz/notebooks#Control\">Control</a>) -> <a href=\"moonbitlang/core/debug#Repr\">@moonbitlang/core/debug.Repr</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 266,
  #|            "column": 40
  #|          }
  #|        }
  #|      ],
  #|      "impls": []
  #|    },
  #|    {
  #|      "name": "Cursor",
  #|      "docstring": "\n An immutable position in a tree of concrete nodes N. Moves return new\n positions; retaining a cursor saves its node, path and ancestors.\n Parent navigation never goes above the root passed to the constructor.",
  #|      "signature": "type Cursor[N]",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "navigation.mbt",
  #|        "line": 137,
  #|        "column": 8
  #|      },
  #|      "methods": [
  #|        {
  #|          "name": "Cursor",
  #|          "docstring": "\n Establish a new navigation root at this node, with depth zero and path `$`.\n Constructing from a descendant discards its previous ancestor context.",
  #|          "signature": "fn[N] <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>::Cursor(root : N) -> <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 146,
  #|            "column": 19
  #|          }
  #|        },
  #|        {
  #|          "name": "children",
  #|          "docstring": "\n Return immutable positions for all direct children in document order.\n Each position retains this cursor as its parent.",
  #|          "signature": "fn[N : <a href=\"moonrockz/notebooks#Node\">Node</a>] <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>::children(self : <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> ReadOnlyArray[<a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]]",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 244,
  #|            "column": 26
  #|          }
  #|        },
  #|        {
  #|          "name": "depth",
  #|          "docstring": "\n Return the number of edges from this cursor's navigation root.",
  #|          "signature": "fn[N] <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>::depth(self : <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> Int",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 158,
  #|            "column": 19
  #|          }
  #|        },
  #|        {
  #|          "name": "first_child",
  #|          "docstring": "\n Move to the first child in document order, or return None for a leaf.",
  #|          "signature": "fn[N : <a href=\"moonrockz/notebooks#Node\">Node</a>] <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>::first_child(self : <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]?",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 199,
  #|            "column": 26
  #|          }
  #|        },
  #|        {
  #|          "name": "fold",
  #|          "docstring": "\n Thread an accumulator through every node of this subtree in pre-order.\n Callbacks receive typed cursors with the original paths and ancestors.\n Use walk when pruning or early termination is needed.",
  #|          "signature": "fn[N : <a href=\"moonrockz/notebooks#Node\">Node</a>, A] <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>::fold(self : <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N], init : A, f : (A, <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> A) -> A",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 334,
  #|            "column": 29
  #|          }
  #|        },
  #|        {
  #|          "name": "last_child",
  #|          "docstring": "\n Move to the last child in document order, or return None for a leaf.",
  #|          "signature": "fn[N : <a href=\"moonrockz/notebooks#Node\">Node</a>] <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>::last_child(self : <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]?",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 210,
  #|            "column": 26
  #|          }
  #|        },
  #|        {
  #|          "name": "next_sibling",
  #|          "docstring": "\n Move to the following sibling, retaining the same parent. Return None\n at the last sibling or at the navigation root.",
  #|          "signature": "fn[N] <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>::next_sibling(self : <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]?",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 222,
  #|            "column": 19
  #|          }
  #|        },
  #|        {
  #|          "name": "node",
  #|          "docstring": "\n Return the concrete node at this position without converting its payload.",
  #|          "signature": "fn[N] <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>::node(self : <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> N",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 152,
  #|            "column": 19
  #|          }
  #|        },
  #|        {
  #|          "name": "parent",
  #|          "docstring": "\n Return the saved parent position, or None at the navigation root.",
  #|          "signature": "fn[N] <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>::parent(self : <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]?",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 177,
  #|            "column": 19
  #|          }
  #|        },
  #|        {
  #|          "name": "path",
  #|          "docstring": "\n Build the path from this cursor's original root to its current node.\n The result remains stable when other cursors navigate the same tree.",
  #|          "signature": "fn[N] <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>::path(self : <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 165,
  #|            "column": 19
  #|          }
  #|        },
  #|        {
  #|          "name": "previous_sibling",
  #|          "docstring": "\n Move to the preceding sibling, retaining the same parent. Return None\n at the first sibling or at the navigation root.",
  #|          "signature": "fn[N] <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>::previous_sibling(self : <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]?",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 233,
  #|            "column": 19
  #|          }
  #|        },
  #|        {
  #|          "name": "walk",
  #|          "docstring": "\n Walk this subtree in depth-first pre-order, retaining original paths and\n ancestors. Call leave after descendants, including for a pruned node.\n Stop ends immediately without pending leaves. Saved positions and moves\n inside callbacks do not affect the walk. Uses an explicit stack.",
  #|          "signature": "fn[N : <a href=\"moonrockz/notebooks#Node\">Node</a>] <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>::walk(self : <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N], enter : (<a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> <a href=\"moonrockz/notebooks#Control\">Control</a>, leave? : (<a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> Unit) -> Unit",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 279,
  #|            "column": 26
  #|          }
  #|        }
  #|      ],
  #|      "impls": []
  #|    },
  #|    {
  #|      "name": "Metadata",
  #|      "docstring": "\n Immutable Ion metadata with unique, textual top-level field names.\n Import and export copy nested containers and annotations defensively.",
  #|      "signature": "type Metadata derive(<a href=\"moonbitlang/core/debug#Debug\">@moonbitlang/core/debug.Debug</a>)",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "metadata.mbt",
  #|        "line": 27,
  #|        "column": 8
  #|      },
  #|      "methods": [
  #|        {
  #|          "name": "Metadata",
  #|          "docstring": "\n Construct from a JSON object. Use from_ion for the richer Ion data model.\n This JSON input adapter retains the existing constructor's behavior.",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>::Metadata(value : <a href=\"moonbitlang/core/builtin#Json\">Json</a>) -> <a href=\"moonrockz/notebooks#Metadata\">Metadata</a> raise <a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 58,
  #|            "column": 18
  #|          }
  #|        },
  #|        {
  #|          "name": "empty",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>::empty() -> <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 81,
  #|            "column": 18
  #|          }
  #|        },
  #|        {
  #|          "name": "equal",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>::equal(self : <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>, other : <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>) -> Bool",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 37,
  #|            "column": 31
  #|          }
  #|        },
  #|        {
  #|          "name": "from_ion",
  #|          "docstring": "\n Require a non-null Ion struct with unique, textual top-level field names.\n Nested Ion values retain their types, annotations and repeated fields.",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>::from_ion(value : <a href=\"moonrockz/ion/ion#Ion\">@moonrockz/ion/ion.Ion</a>) -> <a href=\"moonrockz/notebooks#Metadata\">Metadata</a> raise <a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 65,
  #|            "column": 18
  #|          }
  #|        },
  #|        {
  #|          "name": "get",
  #|          "docstring": "\n Look up a field as an independent Ion value. Typed nulls are present;\n an absent field is None. No format conversion is performed.",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>::get(self : <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>, key : String) -> <a href=\"moonrockz/ion/ion#Ion\">@moonrockz/ion/ion.Ion</a>?",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 88,
  #|            "column": 18
  #|          }
  #|        },
  #|        {
  #|          "name": "get_json",
  #|          "docstring": "\n Explicit JSON lookup. Raise NotJson if the selected value needs Ion's\n richer types; None still means the key is absent.",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>::get_json(self : <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>, key : String) -> <a href=\"moonbitlang/core/builtin#Json\">Json</a>? raise <a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 102,
  #|            "column": 18
  #|          }
  #|        },
  #|        {
  #|          "name": "is_empty",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>::is_empty(self : <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>) -> Bool",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 117,
  #|            "column": 18
  #|          }
  #|        },
  #|        {
  #|          "name": "keys",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>::keys(self : <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>) -> ReadOnlyArray[String]",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 107,
  #|            "column": 18
  #|          }
  #|        },
  #|        {
  #|          "name": "not_equal",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>::not_equal(x : <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>, y : <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>) -> Bool",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 37,
  #|            "column": 38
  #|          }
  #|        },
  #|        {
  #|          "name": "to_ion",
  #|          "docstring": "\n Export a defensive copy of the native Ion value, retaining every type.",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>::to_ion(self : <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>) -> <a href=\"moonrockz/ion/ion#Ion\">@moonrockz/ion/ion.Ion</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 126,
  #|            "column": 18
  #|          }
  #|        },
  #|        {
  #|          "name": "to_json",
  #|          "docstring": "\n Export independent JSON. Reject annotations, typed nulls, non-finite\n floats, symbols, timestamps, lob values, sexps and repeated struct fields.\n Integers and decimals retain their exact numeric spelling.",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>::to_json(self : <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>) -> <a href=\"moonbitlang/core/builtin#Json\">Json</a> raise <a href=\"moonrockz/notebooks#MetadataError\">MetadataError</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 134,
  #|            "column": 18
  #|          }
  #|        },
  #|        {
  #|          "name": "to_repr",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>::to_repr(<a href=\"moonrockz/notebooks#Metadata\">Metadata</a>) -> <a href=\"moonbitlang/core/debug#Repr\">@moonbitlang/core/debug.Repr</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "metadata.mbt",
  #|            "line": 40,
  #|            "column": 41
  #|          }
  #|        }
  #|      ],
  #|      "impls": [
  #|        {
  #|          "self": {
  #|            "kind": "constr",
  #|            "constructor": {
  #|              "name": "Metadata",
  #|              "path": "moonrockz/notebooks"
  #|            },
  #|            "arguments": []
  #|          },
  #|          "trait": {
  #|            "name": "Eq",
  #|            "path": "moonbitlang/core/builtin"
  #|          },
  #|          "methods": [
  #|            {
  #|              "name": "equal",
  #|              "docstring": "",
  #|              "signature": "fn equal(self : <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>, other : <a href=\"moonrockz/notebooks#Metadata\">Metadata</a>) -> Bool",
  #|              "loc": {
  #|                "path": "moonrockz/notebooks",
  #|                "file": "metadata.mbt",
  #|                "line": 32,
  #|                "column": 34
  #|              }
  #|            }
  #|          ]
  #|        }
  #|      ]
  #|    },
  #|    {
  #|      "name": "NodeKind",
  #|      "docstring": "\n The role of a node during shared traversal. Output variants carry the\n output type; attachments carry filenames; directives carry command names.\n Use the concrete node value to inspect format-specific payloads.",
  #|      "signature": "pub(all) enum NodeKind {\n  Notebook\n  Cell(<a href=\"moonrockz/notebooks#CellKind\">CellKind</a>)\n  Output(String)\n  Attachment(String)\n  Directive(String)\n} derive(<a href=\"moonbitlang/core/builtin#Eq\">Eq</a>, <a href=\"moonbitlang/core/debug#Debug\">@moonbitlang/core/debug.Debug</a>)",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "navigation.mbt",
  #|        "line": 25,
  #|        "column": 15
  #|      },
  #|      "methods": [
  #|        {
  #|          "name": "equal",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#NodeKind\">NodeKind</a>::equal(<a href=\"moonrockz/notebooks#NodeKind\">NodeKind</a>, <a href=\"moonrockz/notebooks#NodeKind\">NodeKind</a>) -> Bool",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 39,
  #|            "column": 31
  #|          }
  #|        },
  #|        {
  #|          "name": "not_equal",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#NodeKind\">NodeKind</a>::not_equal(x : <a href=\"moonrockz/notebooks#NodeKind\">NodeKind</a>, y : <a href=\"moonrockz/notebooks#NodeKind\">NodeKind</a>) -> Bool",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 39,
  #|            "column": 38
  #|          }
  #|        },
  #|        {
  #|          "name": "to_repr",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#NodeKind\">NodeKind</a>::to_repr(<a href=\"moonrockz/notebooks#NodeKind\">NodeKind</a>) -> <a href=\"moonbitlang/core/debug#Repr\">@moonbitlang/core/debug.Repr</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 42,
  #|            "column": 41
  #|          }
  #|        }
  #|      ],
  #|      "impls": []
  #|    },
  #|    {
  #|      "name": "NodePath",
  #|      "docstring": "\n An immutable sequence of zero-based child indices relative to a tree root.\n The empty path denotes that root. Paths describe traversal children, not\n JSON keys or persistent cell IDs; they may not resolve in another tree.",
  #|      "signature": "type NodePath derive(<a href=\"moonbitlang/core/builtin#Eq\">Eq</a>, <a href=\"moonbitlang/core/debug#Debug\">@moonbitlang/core/debug.Debug</a>)",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "navigation.mbt",
  #|        "line": 75,
  #|        "column": 8
  #|      },
  #|      "methods": [
  #|        {
  #|          "name": "NodePath",
  #|          "docstring": "\n Create a path from immutable child indices. Negative and out-of-range\n indices are permitted here and cause `at` to return None when resolved.\n\n ```mbt check\n test \"doc: describe a child path\" {\n   let path = @notebooks.NodePath([1, 0])\n   @expect.expect_all(s => {\n     s.expect(path.indices()).to_equal([1, 0])\n     s.expect(path.to_string()).to_equal(\"$[1][0]\")\n     s.expect(@notebooks.NodePath([]).to_string()).to_equal(\"$\")\n   })\n }\n ```",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>::NodePath(indices : ReadOnlyArray[Int]) -> <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 99,
  #|            "column": 18
  #|          }
  #|        },
  #|        {
  #|          "name": "equal",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>::equal(<a href=\"moonrockz/notebooks#NodePath\">NodePath</a>, <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>) -> Bool",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 80,
  #|            "column": 31
  #|          }
  #|        },
  #|        {
  #|          "name": "indices",
  #|          "docstring": "\n Return the immutable child indices in root-to-node order.",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>::indices(self : <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>) -> ReadOnlyArray[Int]",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 105,
  #|            "column": 18
  #|          }
  #|        },
  #|        {
  #|          "name": "not_equal",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>::not_equal(x : <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>, y : <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>) -> Bool",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 80,
  #|            "column": 38
  #|          }
  #|        },
  #|        {
  #|          "name": "to_repr",
  #|          "docstring": "",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>::to_repr(<a href=\"moonrockz/notebooks#NodePath\">NodePath</a>) -> <a href=\"moonbitlang/core/debug#Repr\">@moonbitlang/core/debug.Repr</a>",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 83,
  #|            "column": 41
  #|          }
  #|        },
  #|        {
  #|          "name": "to_string",
  #|          "docstring": "\n Render a traversal path, such as `$`, `$[0]` or `$[0][1]`.",
  #|          "signature": "fn <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>::to_string(self : <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>) -> String",
  #|          "loc": {
  #|            "path": "moonrockz/notebooks",
  #|            "file": "navigation.mbt",
  #|            "line": 111,
  #|            "column": 18
  #|          }
  #|        }
  #|      ],
  #|      "impls": []
  #|    }
  #|  ],
  #|  "typealias": [],
  #|  "values": [
  #|    {
  #|      "name": "at",
  #|      "docstring": "\n Resolve a traversal path relative to root. Return None for any invalid\n child index, including a negative index. An empty path returns root.",
  #|      "signature": "fn[N : <a href=\"moonrockz/notebooks#Node\">Node</a>] at(root : N, path : <a href=\"moonrockz/notebooks#NodePath\">NodePath</a>) -> N?",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "navigation.mbt",
  #|        "line": 118,
  #|        "column": 18
  #|      }
  #|    },
  #|    {
  #|      "name": "cells_by_mime_type",
  #|      "docstring": "\n Select MIME-capable cells in input order, retaining each matching input\n position once. The immutable result preserves the concrete cell type.\n The trait bound rejects unsupported cell types at compile time.",
  #|      "signature": "fn[C : <a href=\"moonrockz/notebooks#MimeTyped\">MimeTyped</a>] cells_by_mime_type(cells : ReadOnlyArray[C], mime_type : String) -> ReadOnlyArray[C]",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "mime_query.mbt",
  #|        "line": 16,
  #|        "column": 23
  #|      }
  #|    },
  #|    {
  #|      "name": "fold",
  #|      "docstring": "\n Thread an accumulator through every node in pre-order, establishing a\n new cursor root. The callback returns the next accumulator and receives\n the concrete node through its typed cursor. Use walk for pruning or stop.",
  #|      "signature": "fn[N : <a href=\"moonrockz/notebooks#Node\">Node</a>, A] fold(root : N, init : A, f : (A, <a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> A) -> A",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "navigation.mbt",
  #|        "line": 351,
  #|        "column": 21
  #|      }
  #|    },
  #|    {
  #|      "name": "walk",
  #|      "docstring": "\n Walk concrete nodes in depth-first pre-order from a new root.\n Use walk_cursor when callbacks need parent, sibling or path context.\n SkipChildren still receives leave; Stop cancels pending leave callbacks.",
  #|      "signature": "fn[N : <a href=\"moonrockz/notebooks#Node\">Node</a>] walk(root : N, enter : (N) -> <a href=\"moonrockz/notebooks#Control\">Control</a>, leave? : (N) -> Unit) -> Unit",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "navigation.mbt",
  #|        "line": 320,
  #|        "column": 18
  #|      }
  #|    },
  #|    {
  #|      "name": "walk_cursor",
  #|      "docstring": "\n Walk from a new root, supplying typed cursor positions to callbacks.\n Enter runs before children and leave after them. SkipChildren still\n receives leave; Stop returns immediately without pending leave calls.",
  #|      "signature": "fn[N : <a href=\"moonrockz/notebooks#Node\">Node</a>] walk_cursor(root : N, enter : (<a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> <a href=\"moonrockz/notebooks#Control\">Control</a>, leave? : (<a href=\"moonrockz/notebooks#Cursor\">Cursor</a>[N]) -> Unit) -> Unit",
  #|      "loc": {
  #|        "path": "moonrockz/notebooks",
  #|        "file": "navigation.mbt",
  #|        "line": 308,
  #|        "column": 18
  #|      }
  #|    }
  #|  ],
  #|  "misc": []
  #|}

///|
/// The `module_index.json` of `moonrockz/notebooks`, from the same `moon doc` run.
let notebooks_module_index : String =
  #|{
  #|  "name": "moonrockz",
  #|  "package": null,
  #|  "childs": [
  #|    {
  #|      "name": "notebooks",
  #|      "package": {
  #|        "path": "moonrockz/notebooks",
  #|        "traits": [
  #|          {
  #|            "name": "CellView",
  #|            "impls": []
  #|          },
  #|          {
  #|            "name": "MimeTyped",
  #|            "impls": []
  #|          },
  #|          {
  #|            "name": "Node",
  #|            "impls": []
  #|          }
  #|        ],
  #|        "errors": [
  #|          {
  #|            "name": "MetadataError",
  #|            "impls": [],
  #|            "methods": [
  #|              "equal",
  #|              "message",
  #|              "not_equal",
  #|              "to_repr"
  #|            ]
  #|          }
  #|        ],
  #|        "types": [
  #|          {
  #|            "name": "CellKind",
  #|            "impls": [],
  #|            "methods": [
  #|              "equal",
  #|              "not_equal",
  #|              "to_repr"
  #|            ]
  #|          },
  #|          {
  #|            "name": "Control",
  #|            "impls": [],
  #|            "methods": [
  #|              "equal",
  #|              "not_equal",
  #|              "to_repr"
  #|            ]
  #|          },
  #|          {
  #|            "name": "Cursor",
  #|            "impls": [],
  #|            "methods": [
  #|              "Cursor",
  #|              "children",
  #|              "depth",
  #|              "first_child",
  #|              "fold",
  #|              "last_child",
  #|              "next_sibling",
  #|              "node",
  #|              "parent",
  #|              "path",
  #|              "previous_sibling",
  #|              "walk"
  #|            ]
  #|          },
  #|          {
  #|            "name": "Metadata",
  #|            "impls": [
  #|              {
  #|                "self": {
  #|                  "kind": "constr",
  #|                  "constructor": {
  #|                    "name": "Metadata",
  #|                    "path": "moonrockz/notebooks"
  #|                  },
  #|                  "arguments": []
  #|                },
  #|                "trait": {
  #|                  "name": "Eq",
  #|                  "path": "moonbitlang/core/builtin"
  #|                },
  #|                "methods": [
  #|                  "equal"
  #|                ]
  #|              }
  #|            ],
  #|            "methods": [
  #|              "Metadata",
  #|              "empty",
  #|              "equal",
  #|              "from_ion",
  #|              "get",
  #|              "get_json",
  #|              "is_empty",
  #|              "keys",
  #|              "not_equal",
  #|              "to_ion",
  #|              "to_json",
  #|              "to_repr"
  #|            ]
  #|          },
  #|          {
  #|            "name": "NodeKind",
  #|            "impls": [],
  #|            "methods": [
  #|              "equal",
  #|              "not_equal",
  #|              "to_repr"
  #|            ]
  #|          },
  #|          {
  #|            "name": "NodePath",
  #|            "impls": [],
  #|            "methods": [
  #|              "NodePath",
  #|              "equal",
  #|              "indices",
  #|              "not_equal",
  #|              "to_repr",
  #|              "to_string"
  #|            ]
  #|          }
  #|        ],
  #|        "typealias": [],
  #|        "values": [
  #|          "at",
  #|          "cells_by_mime_type",
  #|          "fold",
  #|          "walk",
  #|          "walk_cursor"
  #|        ],
  #|        "misc": []
  #|      },
  #|      "childs": [
  #|        {
  #|          "name": "dib",
  #|          "package": {
  #|            "path": "moonrockz/notebooks/dib",
  #|            "traits": [],
  #|            "errors": [
  #|              {
  #|                "name": "FormatError",
  #|                "impls": [],
  #|                "methods": [
  #|                  "equal",
  #|                  "not_equal",
  #|                  "to_repr"
  #|                ]
  #|              }
  #|            ],
  #|            "types": [
  #|              {
  #|                "name": "Cell",
  #|                "impls": [
  #|                  {
  #|                    "self": {
  #|                      "kind": "constr",
  #|                      "constructor": {
  #|                        "name": "Cell",
  #|                        "path": "moonrockz/notebooks/dib"
  #|                      },
  #|                      "arguments": []
  #|                    },
  #|                    "trait": {
  #|                      "name": "CellView",
  #|                      "path": "moonrockz/notebooks"
  #|                    },
  #|                    "methods": [
  #|                      "kind",
  #|                      "source"
  #|                    ]
  #|                  }
  #|                ],
  #|                "methods": [
  #|                  "Cell",
  #|                  "directives",
  #|                  "equal",
  #|                  "kernel",
  #|                  "kind",
  #|                  "metadata",
  #|                  "mime_capability",
  #|                  "not_equal",
  #|                  "source",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "Directive",
  #|                "impls": [],
  #|                "methods": [
  #|                  "arguments",
  #|                  "equal",
  #|                  "line",
  #|                  "name",
  #|                  "not_equal",
  #|                  "text",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "KernelInfo",
  #|                "impls": [],
  #|                "methods": [
  #|                  "KernelInfo",
  #|                  "aliases",
  #|                  "equal",
  #|                  "language",
  #|                  "name",
  #|                  "not_equal",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "KernelName",
  #|                "impls": [],
  #|                "methods": [
  #|                  "KernelName",
  #|                  "equal",
  #|                  "not_equal",
  #|                  "to_repr",
  #|                  "to_string"
  #|                ]
  #|              },
  #|              {
  #|                "name": "KernelRegistry",
  #|                "impls": [],
  #|                "methods": [
  #|                  "KernelRegistry",
  #|                  "default_kernel",
  #|                  "equal",
  #|                  "kernels",
  #|                  "not_equal",
  #|                  "resolve",
  #|                  "standard",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "MetadataOutput",
  #|                "impls": [],
  #|                "methods": [
  #|                  "equal",
  #|                  "not_equal",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "Node",
  #|                "impls": [
  #|                  {
  #|                    "self": {
  #|                      "kind": "constr",
  #|                      "constructor": {
  #|                        "name": "Node",
  #|                        "path": "moonrockz/notebooks/dib"
  #|                      },
  #|                      "arguments": []
  #|                    },
  #|                    "trait": {
  #|                      "name": "Node",
  #|                      "path": "moonrockz/notebooks"
  #|                    },
  #|                    "methods": [
  #|                      "children",
  #|                      "kind",
  #|                      "metadata",
  #|                      "source"
  #|                    ]
  #|                  }
  #|                ],
  #|                "methods": [
  #|                  "at",
  #|                  "children",
  #|                  "cursor",
  #|                  "equal",
  #|                  "kind",
  #|                  "metadata",
  #|                  "not_equal",
  #|                  "source",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "Notebook",
  #|                "impls": [],
  #|                "methods": [
  #|                  "Notebook",
  #|                  "cell",
  #|                  "cells",
  #|                  "cells_for_kernel",
  #|                  "cursor",
  #|                  "equal",
  #|                  "fold",
  #|                  "metadata",
  #|                  "not_equal",
  #|                  "registry",
  #|                  "root",
  #|                  "to_repr",
  #|                  "to_string"
  #|                ]
  #|              }
  #|            ],
  #|            "typealias": [
  #|              "Control",
  #|              "Cursor",
  #|              "Metadata",
  #|              "NodePath"
  #|            ],
  #|            "values": [
  #|              "parse",
  #|              "walk",
  #|              "walk_cursor"
  #|            ],
  #|            "misc": []
  #|          },
  #|          "childs": []
  #|        },
  #|        {
  #|          "name": "nbformat",
  #|          "package": {
  #|            "path": "moonrockz/notebooks/nbformat",
  #|            "traits": [],
  #|            "errors": [
  #|              {
  #|                "name": "FormatError",
  #|                "impls": [],
  #|                "methods": [
  #|                  "equal",
  #|                  "not_equal",
  #|                  "to_repr"
  #|                ]
  #|              }
  #|            ],
  #|            "types": [
  #|              {
  #|                "name": "Attachments",
  #|                "impls": [],
  #|                "methods": [
  #|                  "Attachments",
  #|                  "equal",
  #|                  "get",
  #|                  "names",
  #|                  "not_equal",
  #|                  "to_json",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "Cell",
  #|                "impls": [
  #|                  {
  #|                    "self": {
  #|                      "kind": "constr",
  #|                      "constructor": {
  #|                        "name": "Cell",
  #|                        "path": "moonrockz/notebooks/nbformat"
  #|                      },
  #|                      "arguments": []
  #|                    },
  #|                    "trait": {
  #|                      "name": "CellView",
  #|                      "path": "moonrockz/notebooks"
  #|                    },
  #|                    "methods": [
  #|                      "kind",
  #|                      "metadata",
  #|                      "mime_capability",
  #|                      "source"
  #|                    ]
  #|                  },
  #|                  {
  #|                    "self": {
  #|                      "kind": "constr",
  #|                      "constructor": {
  #|                        "name": "Cell",
  #|                        "path": "moonrockz/notebooks/nbformat"
  #|                      },
  #|                      "arguments": []
  #|                    },
  #|                    "trait": {
  #|                      "name": "MimeTyped",
  #|                      "path": "moonrockz/notebooks"
  #|                    },
  #|                    "methods": [
  #|                      "has_mime_type"
  #|                    ]
  #|                  }
  #|                ],
  #|                "methods": [
  #|                  "Cell",
  #|                  "cell_type",
  #|                  "content",
  #|                  "equal",
  #|                  "extensions",
  #|                  "has_mime_type",
  #|                  "id",
  #|                  "kind",
  #|                  "metadata",
  #|                  "mime_capability",
  #|                  "not_equal",
  #|                  "outputs",
  #|                  "source",
  #|                  "to_json",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "CellContent",
  #|                "impls": [],
  #|                "methods": [
  #|                  "equal",
  #|                  "not_equal",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "CellId",
  #|                "impls": [],
  #|                "methods": [
  #|                  "CellId",
  #|                  "equal",
  #|                  "not_equal",
  #|                  "to_repr",
  #|                  "to_string"
  #|                ]
  #|              },
  #|              {
  #|                "name": "ExecutionCount",
  #|                "impls": [],
  #|                "methods": [
  #|                  "ExecutionCount",
  #|                  "equal",
  #|                  "from_json",
  #|                  "not_equal",
  #|                  "to_json",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "JsonObject",
  #|                "impls": [],
  #|                "methods": [
  #|                  "JsonObject",
  #|                  "equal",
  #|                  "get",
  #|                  "keys",
  #|                  "not_equal",
  #|                  "to_json",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "MimeBundle",
  #|                "impls": [],
  #|                "methods": [
  #|                  "MimeBundle",
  #|                  "equal",
  #|                  "get",
  #|                  "mime_types",
  #|                  "not_equal",
  #|                  "to_json",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "Node",
  #|                "impls": [
  #|                  {
  #|                    "self": {
  #|                      "kind": "constr",
  #|                      "constructor": {
  #|                        "name": "Node",
  #|                        "path": "moonrockz/notebooks/nbformat"
  #|                      },
  #|                      "arguments": []
  #|                    },
  #|                    "trait": {
  #|                      "name": "Node",
  #|                      "path": "moonrockz/notebooks"
  #|                    },
  #|                    "methods": [
  #|                      "children",
  #|                      "kind",
  #|                      "metadata",
  #|                      "source"
  #|                    ]
  #|                  }
  #|                ],
  #|                "methods": [
  #|                  "at",
  #|                  "children",
  #|                  "cursor",
  #|                  "equal",
  #|                  "kind",
  #|                  "metadata",
  #|                  "not_equal",
  #|                  "source",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "Notebook",
  #|                "impls": [],
  #|                "methods": [
  #|                  "Notebook",
  #|                  "cell",
  #|                  "cell_by_id",
  #|                  "cells",
  #|                  "cells_by_mime_type",
  #|                  "cursor",
  #|                  "equal",
  #|                  "extensions",
  #|                  "fold",
  #|                  "from_json",
  #|                  "metadata",
  #|                  "nbformat",
  #|                  "nbformat_minor",
  #|                  "not_equal",
  #|                  "root",
  #|                  "to_json",
  #|                  "to_repr",
  #|                  "to_string"
  #|                ]
  #|              },
  #|              {
  #|                "name": "Output",
  #|                "impls": [],
  #|                "methods": [
  #|                  "Output",
  #|                  "content",
  #|                  "equal",
  #|                  "extensions",
  #|                  "not_equal",
  #|                  "output_type",
  #|                  "to_json",
  #|                  "to_repr"
  #|                ]
  #|              },
  #|              {
  #|                "name": "OutputContent",
  #|                "impls": [],
  #|                "methods": [
  #|                  "equal",
  #|                  "not_equal",
  #|                  "to_repr"
  #|                ]
  #|              }
  #|            ],
  #|            "typealias": [
  #|              "Control",
  #|              "Cursor",
  #|              "Metadata",
  #|              "NodePath"
  #|            ],
  #|            "values": [
  #|              "parse",
  #|              "walk",
  #|              "walk_cursor"
  #|            ],
  #|            "misc": []
  #|          },
  #|          "childs": []
  #|        }
  #|      ]
  #|    }
  #|  ]
  #|}

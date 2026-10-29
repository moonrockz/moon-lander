# Notebooks

`moonrockz/notebooks` provides immutable notebook models and shared navigation
and traversal. It lives in Moon-Lander and has no dependency on the framework
module.

The module, usage guides and notebook acceptance and law suites were migrated
from [Moonbase at `fd5f9ca`](https://github.com/moonrockz/Moonbase/tree/fd5f9ca7b0cdd2fb1b96c63a5783843d2474bfb9/pkgs/notebooks).
The `moonrockz/notebooks` module name and package imports are unchanged.

| Package | Purpose |
| --- | --- |
| `moonrockz/notebooks` | Open node contract, common node kinds, typed cursors, paths, walks and folds |
| `moonrockz/notebooks/nbformat` | Jupyter v4 JSON, cells, outputs, attachments and metadata |
| `moonrockz/notebooks/dib` | .NET Interactive source notebooks, kernels, metadata and directives |

Add the module with `moon add moonrockz/notebooks`. In `moon.pkg`, import the
packages you use:

```moonbit notest
import {
  "moonrockz/notebooks" @notebooks,
  "moonrockz/notebooks/nbformat" @nbformat,
  "moonrockz/notebooks/dib" @dib,
}
```

All packages support wasm, wasm-gc, JavaScript and native targets.
See the [Jupyter API](nbformat/README.md) and [DIB API](dib/README.md) for
format-specific codecs and constraints.

## Runnable usage guides

The following guides contain complete examples with assertions. MoonBit
compiles and runs their `mbt check` blocks as documentation tests, and
`mise run test` includes them on all four targets.

| Guide | Recipes |
| --- | --- |
| [Shared navigation](examples.mbt.md) | Cross-format queries, cursor moves, saved paths, prune/stop callbacks, folds, subtree roots and consumer-defined formats |
| [Jupyter notebooks](nbformat/examples.mbt.md) | Reading, construction, rich outputs, attachments, immutable metadata, ID lookup, errors, extensions and edits |
| [DIB notebooks](dib/examples.mbt.md) | Selectors, aliases, construction, custom environments, metadata, directive navigation, errors and empty-cell normalization |

Run all usage guides and package tests on one target:

```shell
mise exec -- moon test pkgs/notebooks pkgs/notebooks/nbformat pkgs/notebooks/dib --target js --deny-warn
```

## Shared navigation with concrete payloads

Each format has its own `Notebook`, `Cell` and `Node` values. Its `Node`
implements the open `@notebooks.Node` trait:

- `children()` returns immutable children in document order.
- `kind()` classifies a notebook, cell, output, attachment or directive.
- `source()` returns available source text, with `None` as the default.
- `metadata()` returns node-local `Metadata?`, with `None` as the default.

`CellKind` distinguishes code, Markdown, raw and unknown cells. The shared
classification leaves the concrete format's payload intact. The traversal
engine does not convert notebooks or discard format-specific data.

Write a generic function once and call it with either format's root:

```moonbit notest
fn[N : @notebooks.Node] cell_sources(root : N) -> ReadOnlyArray[String] {
  let sources = []
  @notebooks.walk(root, node => {
    if node.kind() is Cell(_) {
      if node.source() is Some(source) { sources.push(source) }
    }
    Continue
  })
  ReadOnlyArray::from_array(sources[:])
}

let jupyter = @nbformat.parse(jupyter_json)
let interactive = @dib.parse(dib_source)
let jupyter_sources = cell_sources(jupyter.root())
let dib_sources = cell_sources(interactive.root())
```

`Cursor[N]` retains the concrete node type `N`. For a Jupyter root,
`cursor.node()` returns `@nbformat.Node`; for a DIB root, it returns
`@dib.Node`. Pattern match that value to inspect outputs, attachment MIME
bundles, kernel names or directive arguments. Both format packages expose
`book.cursor()`, `node.cursor()`, `node.at(path)`, `walk`, `walk_cursor` and
`book.fold` as convenience methods backed by the shared engine.

The trees differ where their formats differ. Jupyter cells have outputs or
attachments as children. DIB cells have directives as children. A generic
algorithm should use `kind()` to select the nodes it needs, rather than assume
identical tree shapes.

## Cursors, paths and traversal

Construct a cursor with `Cursor(root)`. Moves return a new position or `None`
at a boundary. Use `parent`, `first_child`, `last_child`, `next_sibling`,
`previous_sibling` and `children`. Saved positions retain their node and
ancestors. `depth()` starts at zero; `path()` returns a `NodePath` of child
indices. `@notebooks.at(root, path)` resolves it, or returns `None` for an
invalid index. Paths are relative to their original traversal root and refer
to child order, not JSON object keys or persistent cell IDs.

`walk(root, enter, leave~)` supplies nodes. `walk_cursor` supplies positions.
Both walk depth-first in pre-order. `Continue` visits children;
`SkipChildren` skips descendants but still calls `leave`; `Stop` returns
immediately without pending leave calls. `cursor.walk` retains the original
paths and ancestors while walking that subtree. Starting a cursor from the
node itself establishes a new root. Traversal uses an explicit stack.

`fold(root, init, f)` and `cursor.fold(init, f)` thread an accumulator through
the same pre-order, supplying cursor context. They visit every descendant.
Use a walk when pruning or early termination is needed.

## Additional notebook formats

### MIME lookup capability

`MimeTyped` is a separate, optional trait for cells that support MIME lookup.
Its `has_mime_type(cell, mime_type)` method tests for a representation with
that exact key. Implementing the trait indicates support for the query;
a particular cell can still have no matching representation.

Jupyter `@nbformat.Cell` implements `MimeTyped` for rich outputs and attachments.
DIB cells omit this trait because the format has no stored MIME bundles.
The generic helper requires the capability at compile time:

```moonbit notest
let cells = @notebooks.cells_by_mime_type(jupyter.cells(), "image/png")
// cells is ReadOnlyArray[@nbformat.Cell].
```

The result preserves input order and concrete cell types. Calling this helper
with DIB cells is a compile-time error. The trait is independent of `Node`, so
consumer-defined cell types can implement it without adopting tree navigation.
See the [checked capability example](examples.mbt.md#query-mime-capable-cells).

### Runtime cell inspection

`CellView` is the shared, object-safe interface for inspecting individual
cells. Both Jupyter and DIB cells implement it, so a
`ReadOnlyArray[&@notebooks.CellView]` can hold a mixture of formats. It exposes
`kind()`, `source()`, `metadata()` and `mime_capability()`.

`mime_capability()` returns `Option[&@notebooks.MimeTyped]`. Jupyter cells
return `Some`, including cells with no stored representations. DIB cells
return `None`. Query a returned capability with `has_mime_type(mime_type)`
to distinguish a match from supported lookup with no match.

Concrete cells expose the same accessor, so inspection also works without
building a mixed collection. Consumer-defined cells implement `CellView`'s
`kind` and `source` methods. Metadata and MIME capability default to `None`;
supporting consumers explicitly override `mime_capability` to return
`Some(self as &@notebooks.MimeTyped)`.

See the [checked mixed-collection example](examples.mbt.md#inspect-capabilities-in-a-mixed-cell-collection).
Tree navigation continues to use each format's concrete `Node` and typed
cursors. The cell view provides runtime capability inspection without
changing that navigation contract.

### Navigation contract

A consumer can implement `@notebooks.Node` on its own immutable tree and use
the same cursors, path resolution, walks and folds. Children must be stable,
ordered, finite and immutable. Neither this package nor existing formats need
to change when another format implements the contract.

This module does not convert between file formats. Reading and writing remain
explicit operations on each format's notebook type, so saving a DIB notebook
cannot silently discard Jupyter outputs or attachments.

## Migration from moonbase-nbformat

Replace the module dependency `moonrockz/moonbase-nbformat` with
`moonrockz/notebooks` at the workspace version. Replace the package import
`moonrockz/moonbase-nbformat` with `moonrockz/notebooks/nbformat`, keeping the
`@nbformat` alias. Existing Jupyter codecs and convenience navigation methods
remain available. Explicit cursor annotations now use
`@nbformat.Cursor[@nbformat.Node]`, or `@notebooks.Cursor[@nbformat.Node]`.
`Control` and `NodePath` are shared types re-exported by both format packages.

## Shared metadata

`Metadata` stores an Ion struct using `moonrockz/ion@0.6.0`. Construct native
metadata with `Metadata::from_ion(value)`, or import an existing JSON object
with `Metadata(json)`. `Metadata::empty()` creates an empty struct. Top-level
field names must have known text and be unique. Other shapes raise
`MetadataError::ExpectedObject`; invalid keys raise `InvalidKey`.

`get(key)` returns `Option[@ion.Ion]`; `to_ion()` exports the complete native
value. Integers, decimals, timestamps, typed nulls, annotations and nested
Ion values retain their types. Imports, lookups and exports defensively copy
mutable containers and annotation arrays. A present null, including a typed
null, is `Some(value)`; an absent key is `None`. `keys()` returns immutable
field names. `is_empty()` means no fields and no root annotations.

`get_json(key)` and `to_json()` are explicit, fallible JSON adapters. They
raise `MetadataError::NotJson` with a field path instead of dropping
annotations, typed nulls, non-finite floats, timestamps, symbols, lob values,
sexps or repeated nested struct fields. Exact integer and decimal spelling
is retained in JSON numbers. Code that previously expected JSON from `get`
should use `get_json`, or inspect the native value's `kind()`.

DIB accepts JSON, YAML, TOML and Ion metadata sections. Its default output
uses JSON only when it preserves the entire Ion value, otherwise Ion.
Jupyter continues to require JSON-compatible metadata and reports a field
validation error for Ion-only values. See the
[native metadata example](examples.mbt.md#use-native-ion-metadata) and
[DIB format rules](dib/README.md#metadata).

`Node.metadata()` returns the node's own attributes. `Some(Metadata::empty())`
means the node has an empty metadata container. `None` means the format defines
no metadata container for that node. Metadata is never inherited. Use a cursor's
`parent()` explicitly when a query needs ancestor attributes. Metadata remains
an attribute, rather than a traversal child.

| Node | Common metadata |
| --- | --- |
| Jupyter notebook and every cell type | `Some`, including empty objects |
| Jupyter display_data and execute_result outputs | `Some`, including empty objects |
| Jupyter stream, error and unknown output types; attachments | `None` |
| DIB notebook | `Some`, including an absent or empty #!meta section |
| DIB cell and directive | `None` |

Unknown output fields remain available through the specialized output payload.
Both format packages re-export the same `Metadata` type. Jupyter notebook,
cell and rich-output constructors accept it, and their accessors return it.
Jupyter's `JsonObject` remains the type for extension fields and unknown payloads.
Replace metadata arguments built with `@nbformat.JsonObject(json)` with
`@notebooks.Metadata(json)` or `@nbformat.Metadata(json)`. Existing
`@dib.Metadata(json)` calls use the shared constructor and now raise
`MetadataError`; DIB parsing continues to report `FormatError::InvalidMetadata`
with the source line. Jupyter codecs retain field-path validation errors.

## Describe virtual file trees

The pure [file-tree model](files/README.mbt.md) represents LF-normalized text
files and explicit empty directories with typed relative paths. DIB uses
first-line file declarations and a directory manifest. Jupyter uses the neutral
`metadata.vfs` version-1 convention and keeps file source free of directives.
Both formats map to the same immutable tree and perform no filesystem I/O.

## Convert notebook formats

The [source converter](conversion/README.mbt.md) converts ordinary DIB and
Jupyter source cells with explicit typed loss reports. Strict policy refuses
unsupported state; SourceOnly is an explicit choice. Use `files.convert_tree`
with file-tree formats when paths and directory declarations must change
between DIB directives and `metadata.vfs`.

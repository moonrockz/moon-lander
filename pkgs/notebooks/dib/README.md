# DIB notebooks

`moonrockz/notebooks/dib` reads and writes the plain-text `.dib` format used by
.NET Interactive and Polyglot Notebooks. Behavior follows the upstream
[code-submission parser](https://github.com/dotnet/interactive/blob/main/src/Microsoft.DotNet.Interactive.Documents/CodeSubmission.cs)
and its [format tests](https://github.com/dotnet/interactive/blob/main/src/Microsoft.DotNet.Interactive.Documents.Tests/CodeSubmissionFormatTests.cs).

The [runnable usage guide](examples.mbt.md) contains complete, tested examples
for parsing, construction, custom registries, document metadata, directive
navigation, errors and normalization. The
[shared navigation guide](../examples.mbt.md) covers generic walks and folds.

```moonbit
let book = @dib.parse("#!markdown\n# Results\n#!csharp\n1 + 1\n")
let code = book.cells_for_kernel("c#")
let serialized = book.to_string()
```

## Cells and selectors

Each immutable cell has `source()`, `kernel()` and a common `kind()`. Markdown
uses the pseudo-kernel `markdown`; other registered kernels produce code cells.
DIB stores source without persisted execution outputs or attachments.

A selector must start at column zero and match a registered kernel name or
alias exactly. `#!fsharp` starts a cell; `#!fsharp --help` is source. Commands
such as `#!share`, `#!connect` and unknown `#!something` remain source. The
parser does not execute directives or infer new kernels from `#!connect`.

The standard registry includes C#, F#, PowerShell, JavaScript, HTML, SQL, KQL,
HTTP, value and Mermaid kernels, plus Markdown. Aliases include `cs`, `c#`,
`C#`, `fs`, `f#`, `F#`, `powershell`, `js` and `md`. Matching is case-sensitive.
Unmarked source uses C# by default. An explicit registry can change it:

```moonbit
let kernel = @dib.KernelName("example")
let registry = @dib.KernelRegistry(
  [@dib.KernelInfo(kernel, aliases=[@dib.KernelName("ex")])],
  default_kernel=kernel,
)
let book = @dib.parse("#!ex\nrun()", registry~)
```

Registry construction checks duplicate names and aliases and validates the
default kernel. All names and aliases are typed `KernelName` values. Markdown
is available independently of the execution environment. Notebook construction
resolves cell aliases to their canonical kernel names.

## Metadata

The first recognized metadata header introduces document metadata. Headers
are exact, lowercase and at column zero. The section continues until the next
line beginning with `#!`, or the end of the document.

| Header | Input format |
| --- | --- |
| `#!meta` | Standard DIB JSON |
| `#!meta json` | JSON |
| `#!meta yaml` | YAML mapping |
| `#!meta toml` | TOML table |
| `#!meta ion` | Ion struct |

Format-qualified headers are Moon-Lander extensions. There is no format
auto-detection under bare `#!meta`. All inputs normalize to the shared Ion
metadata model. The top-level value must be an object, mapping, table or struct
with unique textual keys. Empty or comment-only YAML and TOML sections become
empty structs. YAML accepts a single document with string mapping keys.
Malformed input raises `InvalidMetadata` with the section's first payload
line and a parser diagnostic. Later metadata headers remain cell source.

```text
#!meta
{"title":"Example","kernelInfo":{"defaultKernelName":"csharp","items":[{"name":"custom","aliases":["alt"]}]}}

#!alt
custom()
```

`kernelInfo.items` registers custom names and aliases. Metadata declarations
take precedence over environment kernels of the same name. The registry also
recognizes default-kernel metadata in `polyglot_notebook` and the legacy
`dotnet_interactive` namespace. A default declared in a leading metadata
section applies to the notebook's initial kernel.

`Metadata` is the shared Ion-backed `@notebooks.Metadata` type, re-exported
here. `metadata.get(key)` returns an independent Ion value, and `to_ion()`
exports the full struct. Use `Metadata::from_ion(value)` for native values or
`Metadata(json)` to import JSON. `get_json` and `to_json` are explicit adapters
that reject Ion-only data with `MetadataError::NotJson`.

YAML and TOML integers become Ion integers; real numbers become Ion floats,
including infinity and NaN. YAML dates follow the YAML parser's string
resolution. TOML dates and datetimes become Ion timestamps. Local datetimes
retain an unknown offset, and date-free local times become strings annotated
`toml_local_time`, since Ion has no date-free time type. Native Ion input also
retains exact decimals, typed nulls, annotations, blobs and other Ion values.
The original YAML/TOML syntax and comments are not retained.

`book.to_string()` uses `MetadataOutput::Auto`. It emits standard JSON
metadata when parsing that JSON recreates the same Ion value; otherwise it
emits `#!meta ion`. To choose explicitly:

```moonbit
let ion_source = book.to_string(metadata_output=@dib.MetadataOutput::Ion)
let json_source = book.to_string(metadata_output=@dib.MetadataOutput::Json)
```

Explicit JSON output raises `InvalidMetadata` if conversion would lose
information. YAML and TOML are input formats; output uses JSON or Ion.

## Writing and construction

```moonbit
let cell = @dib.Cell::Cell("Console.WriteLine(1);", kernel=@dib.KernelName("csharp"))
let book = @dib.Notebook::Notebook([cell])
```

LF, CRLF and CR normalize to LF. Leading and trailing empty lines are trimmed
from cells; whitespace-only lines and internal blank lines remain. Empty
sections are omitted, and parsing an empty document yields one empty cell.
Writing omits empty cells, emits canonical selectors, and adds a blank line
after each selector and between cells. A leading BOM is accepted.

`to_string()` raises `UnrepresentableSource` if a constructed cell contains a
registered selector that would change its structure when
read again. It identifies the cell index and the one-based line within the
cell. This avoids silently splitting source into more cells. If cell source
contains a later recognized metadata directive, the writer emits a document metadata header,
using `{}` when needed, so that directive remains source on the next read.

When custom kernels come from the caller's registry rather than document
metadata, supply that same registry on subsequent reads. The writer preserves
metadata and does not inject environment configuration. Use `book.registry()`
to retain that context. Persist custom kernel definitions in `#!meta` when a
file needs to describe its own selectors.

## Specialized navigation

`Cell.directives()` returns immutable directive values with `name`,
`arguments`, original `text` and a one-based line relative to cell source.
`cells_for_kernel(name)` resolves aliases before selecting cells.

`Cell` implements `@notebooks.CellView` for mixed-format collections and
runtime capability inspection. `cell.mime_capability()` returns `None`,
because DIB stores no MIME bundles. Its shared view returns the cell's kind,
`Some(source)` and `None` for cell-local metadata. It can be stored beside
Jupyter cells in a `ReadOnlyArray[&@notebooks.CellView]`.

`Node` has `Notebook`, `Cell` and `Directive` variants. Notebook children are
cells in source order; cell children are directives in source order. Directive
nodes are leaves. Kernel selectors are cell properties, not source directives.

Use `book.cursor()`, `node.at(path)`, `walk`, `walk_cursor` and `book.fold`, or
pass `book.root()` to the shared `@notebooks` functions. Cursors retain
`@dib.Node`, so a caller can pattern match `Directive(directive)` and inspect
its arguments during otherwise generic traversal.

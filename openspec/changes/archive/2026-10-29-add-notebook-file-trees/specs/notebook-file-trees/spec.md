# Notebook file trees

## ADDED Requirements

### Requirement: Typed relative paths

TreePath SHALL have private fields and a smart constructor. Parsing SHALL reject
empty, absolute or drive-qualified paths, backslashes, NUL and line breaks, empty
segments, dot and parent segments. Failures SHALL name the input and broken rule.

#### Scenario: Relative path rules

- **WHEN** a raw tree path violates any path rule
- **THEN** parsing raises a typed error naming the input and rule

### Requirement: Immutable text tree

The library SHALL provide private-field TextFile and immutable FileTree values.
Files SHALL retain LF-normalized source and typed kernel names. Trees SHALL infer
parents, preserve explicit empty directories and declaration order, and reject
duplicate files and file/directory conflicts. Repeated directory declarations
SHALL be idempotent. No operation SHALL perform I/O or execute source.

#### Scenario: Text tree round trip

- **WHEN** a tree with MoonBit, Python, Markdown and empty text files and an explicit empty directory is round-tripped through either format
- **THEN** its paths, sources, canonical kernels, file order and explicit directories remain equal

#### Scenario: Conflicting file parent

- **WHEN** a tree declares both a file at src and a file at src/main.mbt
- **THEN** construction raises a typed file/directory conflict

### Requirement: DIB file cells

The DIB adapter SHALL use Lossless and register tree and text kernels. A file
cell SHALL begin with a first-line #!file path declaration. All remaining source
SHALL be content, including later directives. Unmarked cells SHALL be outside
the projection. Reading SHALL not change the original notebook.

#### Scenario: Empty file and source directives

- **WHEN** a file declaration has no following source, or contains a later #!file directive as content
- **THEN** the result is an empty file, or retains that later directive as content

### Requirement: DIB directories and path arguments

A tree manifest cell SHALL contain #!directory declarations for explicit
directories. Empty manifest lines SHALL be allowed. Path arguments SHALL accept
raw paths or JSON strings. Writing SHALL quote paths as JSON strings.

#### Scenario: Quoted paths

- **WHEN** a file path contains spaces or quotes
- **THEN** DIB writing and reading retain the exact path

### Requirement: DIB export refusal

Existing selector-collision refusal SHALL apply. Tree export SHALL reject
unregistered kernels, the reserved tree manifest kernel as a file kernel, and
aliases that would change kernel identity. A format file constructor SHALL
resolve aliases to canonical names at construction.

#### Scenario: Unrepresentable DIB source

- **WHEN** file content contains a registered selector at column zero
- **THEN** DIB export raises its existing typed representation error

#### Scenario: Alias resolution

- **WHEN** a file is constructed through the format using an alias
- **THEN** it stores the canonical name and round-trips without further registration

### Requirement: Jupyter VFS cell metadata

Jupyter file cells SHALL use metadata.vfs with required textual path and kernel
fields. A malformed declaration SHALL raise a typed mapping error. Source SHALL
require no DIB transport directive. Only marked source cells SHALL become files;
outputs and attachments SHALL remain outside the projection. Reading SHALL not
modify the original notebook.

#### Scenario: Namespaced source-only files

- **WHEN** Jupyter source cells carry metadata.vfs paths and kernels and unrelated output or metadata
- **THEN** extraction retains file source and ignores output without modifying the notebook

### Requirement: Jupyter VFS directory metadata

Notebook metadata.vfs SHALL contain version 1 and an optional directories array.
An absent notebook VFS header SHALL allow independently marked file cells. A
present malformed or unsupported header SHALL raise a typed mapping error.

#### Scenario: Invalid header

- **WHEN** notebook VFS metadata has an unsupported version or malformed directories
- **THEN** extraction raises a typed mapping error

### Requirement: Fresh Jupyter export

Tree writing SHALL create a valid v4.5 notebook with VFS version 1, stable IDs,
empty outputs and null execution counts. Text files SHALL use raw cells,
Markdown files markdown cells, and other kernels code cells. Export SHALL not
claim to reproduce unrelated notebook metadata, notes or execution state.

#### Scenario: Notebook portability

- **WHEN** a tree is written as Jupyter and read through the public API
- **THEN** the document is valid and the resulting tree equals the original

### Requirement: Portable public API

The model, codecs, descriptor implementations, examples and isolated public
consumers SHALL build and run on wasm, wasm-gc, js and native. Existing notebook
APIs and tests SHALL remain compatible.

#### Scenario: Four-target verification

- **WHEN** the notebook suites and public examples run on all four targets
- **THEN** every target executes and passes the tree and compatibility cases

# dib-source-roundtrip Specification

## Purpose
Let source notebook consumers preserve DIB cell boundaries and source through the
public API without changing the published normalized behavior for existing users.

## Requirements

### Requirement: Compatible source mode

Cell construction, parsing and writing SHALL offer a typed lossless source mode.
The omitted mode SHALL keep the published normalized behavior, including trimming
empty boundary lines, omitting empty sections and emitting normalized padding.

#### Scenario: Existing default behavior

- **WHEN** a caller parses empty selector sections without selecting lossless mode
- **THEN** those sections remain omitted and the existing normalized output is unchanged

### Requirement: Lossless source-cell round trip

With lossless mode selected throughout construction, writing and parsing, the
result SHALL retain cell count, cell order, canonical kernels and source. Empty
code and Markdown cells SHALL remain cells, including consecutive empty cells.
An empty notebook SHALL remain empty.

#### Scenario: Empty Markdown before code

- **WHEN** an empty Markdown cell and a Scheme cell containing 42 are constructed and round-tripped in lossless mode with the same registry
- **THEN** the result contains both cells in order with their original source and kernels

#### Scenario: Consecutive empty cells

- **WHEN** leading, middle and trailing empty cells, including repeated selectors for the same kernel, are round-tripped in lossless mode
- **THEN** every cell boundary and kernel is retained

#### Scenario: Zero cells

- **WHEN** a zero-cell notebook is written and read in lossless mode
- **THEN** the result has zero cells rather than one implicit empty cell

### Requirement: Lossless boundary lines

Lossless cell construction SHALL normalize CRLF and CR to LF without trimming
leading or trailing empty source lines. Lossless writing and reading SHALL retain
those normalized boundary lines and whitespace-only lines exactly. Writer framing
SHALL be distinct from payload and SHALL not insert source padding.

#### Scenario: Boundary and whitespace lines

- **WHEN** sources containing empty text, one or several newlines, leading and trailing newlines, and whitespace-only lines are round-tripped in lossless mode
- **THEN** each source equals its input after line-ending normalization only

### Requirement: Metadata and registry composition

Lossless source mode SHALL retain document metadata under the existing metadata
output policy. The existing custom registry and alias rules SHALL apply. When
metadata directives occur inside cell source, writing SHALL preserve them as
source under the existing first-metadata-header rule.

#### Scenario: Source metadata directive

- **WHEN** a lossless cell contains a recognized metadata directive as source
- **THEN** writing and rereading retains that source rather than treating it as document metadata

#### Scenario: Custom kernels and metadata

- **WHEN** empty and nonempty custom-kernel cells with metadata are written and reread with the same registry in lossless mode
- **THEN** metadata, canonical kernels and all source cells are retained

### Requirement: Refuse unrepresentable selectors

Writing SHALL retain the existing typed refusal when a cell contains a registered
column-zero selector that would split it on reread. The error SHALL identify the
cell and source line in either source mode. Unknown or non-exact selectors SHALL
remain ordinary source.

#### Scenario: Selector collision

- **WHEN** a lossless source cell contains a registered selector at line two
- **THEN** writing raises the existing unrepresentable-source error for that cell and line

### Requirement: Portable public evidence

The lossless public API, examples and acceptance tests SHALL build and run on wasm,
wasm-gc, js and native. Tests SHALL include the issue #109 public reproduction and
retain the existing normalized-mode test cases.

#### Scenario: Four-target source preservation

- **WHEN** the notebooks DIB suite runs on each target
- **THEN** the lossless round-trip tests and unchanged normalized tests pass on all four

### Requirement: Nested kernel registration namespaces

The DIB codec SHALL accept nested polyglot_notebook.kernelInfo and legacy
dotnet_interactive.kernelInfo declarations. Existing top-level kernelInfo and
flat namespace forms SHALL remain compatible. Names, aliases and default kernels
SHALL use the existing typed registry rules.

#### Scenario: Self-describing converted source

- **WHEN** a document declares Python and its alias in a nested kernelInfo namespace
- **THEN** reading resolves that alias and rereading its output retains the same cells

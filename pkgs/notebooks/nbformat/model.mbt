///|
/// An immutable Jupyter cell identifier containing 1 to 64 ASCII letters,
/// digits, hyphens or underscores. Notebook construction checks uniqueness.
struct CellId {
  value : String
} derive(Eq, Debug)

///|
pub extend CellId with Eq::{equal, not_equal}

///|
pub extend CellId with @debug.Debug::{to_repr}

///|
/// Validate a cell identifier. Raise InvalidField for an empty, oversized
/// or otherwise invalid ID. This constructor does not generate an ID.
///
/// ```mbt check
/// test "doc: construct a stable cell ID" {
///   let id = @nbformat.CellId("results-01")
///   @expect.expect(id.to_string()).to_equal("results-01")
/// }
/// ```
pub fn CellId::CellId(value : String) -> CellId raise FormatError {
  cell_id_at(Json(value), "$.id")
}

///|
fn cell_id_at(value : Json, path : String) -> CellId raise FormatError {
  let value = string_at(value, path)
  guard value.length() >= 1 && value.length() <= 64 else {
    invalid(path, "cell ID of 1 to 64 ASCII letters, digits, '-' or '_'")
  }
  for unit in value.code_units() {
    guard (unit >= 65 && unit <= 90) ||
      (unit >= 97 && unit <= 122) ||
      (unit >= 48 && unit <= 57) ||
      unit == 45 ||
      unit == 95 else {
      invalid(path, "cell ID of 1 to 64 ASCII letters, digits, '-' or '_'")
    }
  }
  { value, }
}

///|
/// Return the validated identifier unchanged.
pub fn CellId::to_string(self : CellId) -> String {
  self.value
}

///|
/// A nonnegative integral JSON number. Preserve its available JSON
/// representation instead of converting large counts to a machine integer.
/// Use None, rather than an ExecutionCount value, for an unexecuted cell.
struct ExecutionCount {
  value : Json
} derive(Eq, Debug)

///|
pub extend ExecutionCount with Eq::{equal, not_equal}

///|
pub extend ExecutionCount with @debug.Debug::{to_repr}

///|
/// Construct a count from a nonnegative 32-bit integer. Raise InvalidField
/// for a negative value. Use from_json for larger JSON numbers.
pub fn ExecutionCount::ExecutionCount(
  value : Int32,
) -> ExecutionCount raise FormatError {
  count_at(Json(value), "$.execution_count")
}

///|
/// Validate a finite, nonnegative integral JSON number and retain its
/// representation. Raise InvalidField for null, negative or fractional values,
/// non-numbers and non-finite values. Null counts are represented by None.
pub fn ExecutionCount::from_json(
  value : Json,
) -> ExecutionCount raise FormatError {
  count_at(value, "$.execution_count")
}

///|
fn count_at(value : Json, path : String) -> ExecutionCount raise FormatError {
  guard value is Number(n, ..) &&
    n >= 0 &&
    n < @double.infinity &&
    n.floor() == n else {
    invalid(path, "nonnegative integer")
  }
  { value, }
}

///|
/// Export the numeric JSON value without converting it to an integer string.
pub fn ExecutionCount::to_json(self : ExecutionCount) -> Json {
  self.value
}

///|
/// The typed payload of a Jupyter output. Rich display and execution results
/// carry MIME bundles and metadata; None denotes a null execution count.
/// Unknown preserves an unrecognized output type and its additional fields.
pub(all) enum OutputContent {
  /// Text written to a named stream, commonly stdout or stderr.
  Stream(name~ : String, text~ : String)
  /// A MIME bundle displayed without an execution count.
  DisplayData(data~ : MimeBundle, metadata~ : Metadata)
  /// A MIME bundle returned by execution; None denotes a null count.
  ExecuteResult(
    data~ : MimeBundle,
    metadata~ : Metadata,
    execution_count~ : ExecutionCount?
  )
  /// A failed execution with an exception name, message and ordered frames.
  Error(ename~ : String, evalue~ : String, traceback~ : ReadOnlyArray[String])
  /// An unrecognized type and its fields, excluding output_type itself.
  Unknown(output_type~ : String, fields~ : JsonObject)
} derive(Eq, Debug)

///|
pub extend OutputContent with Eq::{equal, not_equal}

///|
pub extend OutputContent with @debug.Debug::{to_repr}

///|
/// An immutable validated output, including preserved extension fields.
/// Construct with Output(content), or obtain outputs from a parsed code cell.
struct Output {
  content : OutputContent
  extensions : JsonObject
} derive(Eq, Debug)

///|
pub extend Output with Eq::{equal, not_equal}

///|
pub extend Output with @debug.Debug::{to_repr}

///|
/// Validate a typed output payload using the JSON codec's boundary rules.
/// Unknown must use an unrecognized output_type and must not repeat that
/// key inside fields. Raise InvalidField for invalid payload or metadata.
pub fn Output::Output(content : OutputContent) -> Output raise FormatError {
  if content is Unknown(output_type~, fields~) {
    if ["stream", "display_data", "execute_result", "error"].contains(
        output_type,
      ) {
      invalid("$.output_type", "unrecognized output type for Unknown")
    }
    if fields.fields.contains("output_type") {
      invalid("$.output_type", "output_type supplied separately")
    }
  }
  let output = Output::{ content, extensions: { fields: {}, }, }
  // Use the codec boundary for the same validation as imported notebooks.
  output_at(output.to_json(), "$")
}

///|
/// Return the typed output payload for exhaustive pattern matching.
pub fn Output::content(self : Output) -> OutputContent {
  self.content
}

///|
/// Return extra JSON fields preserved when reading a recognized output.
/// For an unknown output, additional fields live in its Unknown payload.
pub fn Output::extensions(self : Output) -> JsonObject {
  self.extensions
}

///|
/// Return the wire-format discriminator, such as `stream` or `display_data`.
/// An unknown output retains its original discriminator.
pub fn Output::output_type(self : Output) -> String {
  match self.content {
    Stream(_) => "stream"
    DisplayData(_) => "display_data"
    ExecuteResult(_) => "execute_result"
    Error(_) => "error"
    Unknown(output_type~, ..) => output_type
  }
}

///|
/// The source and format-specific payload of a cell. Only code cells carry
/// outputs and execution counts; only Markdown and raw cells carry attachments.
/// Unknown preserves the original cell type and its additional JSON fields.
pub(all) enum CellContent {
  /// Markdown source with optional filename-keyed attachments.
  Markdown(source~ : String, attachments~ : Attachments?)
  /// Raw exporter source with optional attachments.
  Raw(source~ : String, attachments~ : Attachments?)
  /// Executable source, a nullable execution count and ordered stored outputs.
  Code(
    source~ : String,
    execution_count~ : ExecutionCount?,
    outputs~ : ReadOnlyArray[Output]
  )
  /// An unrecognized type and fields excluding cell_type, id and metadata.
  Unknown(cell_type~ : String, fields~ : JsonObject)
} derive(Eq, Debug)

///|
pub extend CellContent with Eq::{equal, not_equal}

///|
pub extend CellContent with @debug.Debug::{to_repr}

///|
/// An immutable validated Jupyter cell. IDs may be absent in pre-4.5 files;
/// the containing notebook enforces version-specific ID presence and uniqueness.
struct Cell {
  id : CellId?
  metadata : Metadata
  content : CellContent
  extensions : JsonObject
} derive(Eq, Debug)

///|
pub extend Cell with Eq::{equal, not_equal}

///|
pub extend Cell with @debug.Debug::{to_repr}

///|
/// Validate a typed payload and cell metadata. Defaults to no ID and empty
/// metadata; Notebook construction requires IDs for v4.5 and later.
/// Unknown fields must not repeat cell_type, id or metadata. Raises
/// InvalidField for invalid metadata or a conflicting Unknown payload.
pub fn Cell::Cell(
  content : CellContent,
  id~ : CellId? = None,
  metadata~ : Metadata = Metadata::empty(),
) -> Cell raise FormatError {
  if content is Unknown(cell_type~, fields~) {
    if ["markdown", "raw", "code"].contains(cell_type) {
      invalid("$.cell_type", "unrecognized cell type for Unknown")
    }
    for key in ["cell_type", "id", "metadata"] {
      if fields.fields.contains(key) {
        invalid("$." + key, "common cell field supplied separately")
      }
    }
  }
  let cell = Cell::{ id, metadata, content, extensions: { fields: {}, }, }
  cell_at(cell.to_json(), "$", 0)
}

///|
/// Return the validated ID, or None when reading or constructing an older cell.
pub fn Cell::id(self : Cell) -> CellId? {
  self.id
}

///|
/// Return the immutable cell metadata object.
pub fn Cell::metadata(self : Cell) -> Metadata {
  self.metadata
}

///|
/// Return the typed cell payload for exhaustive pattern matching.
pub fn Cell::content(self : Cell) -> CellContent {
  self.content
}

///|
/// Return extra fields preserved when reading a recognized cell. Additional
/// fields of an unknown cell are stored in its Unknown payload instead.
pub fn Cell::extensions(self : Cell) -> JsonObject {
  self.extensions
}

///|
/// Return the wire-format cell type, retaining unknown type names unchanged.
pub fn Cell::cell_type(self : Cell) -> String {
  match self.content {
    Markdown(_) => "markdown"
    Raw(_) => "raw"
    Code(_) => "code"
    Unknown(cell_type~, ..) => cell_type
  }
}

///|
/// Return normalized source for code, Markdown and raw cells. Return None
/// for unknown cells, whose uninterpreted source may remain in their fields.
pub fn Cell::source(self : Cell) -> String? {
  match self.content {
    Markdown(source~, ..) | Raw(source~, ..) | Code(source~, ..) => Some(source)
    Unknown(_) => None
  }
}

///|
/// Return code outputs in stored order. Return an empty immutable array for
/// Markdown, raw and unknown cells.
pub fn Cell::outputs(self : Cell) -> ReadOnlyArray[Output] {
  match self.content {
    Code(outputs~, ..) => outputs
    _ => []
  }
}

///|
/// An immutable Jupyter v4 document with metadata, ordered cells and
/// preserved extension fields. The file's minor version is retained.
struct Notebook {
  minor : Int32
  metadata : Metadata
  cells : ReadOnlyArray[Cell]
  extensions : JsonObject
} derive(Eq, Debug)

///|
pub extend Notebook with Eq::{equal, not_equal}

///|
pub extend Notebook with @debug.Debug::{to_repr}

///|
/// Construct a v4 notebook, defaulting to file format 4.5 and empty metadata.
/// Raise UnsupportedVersion for a negative minor version, InvalidField for
/// invalid metadata or a missing required ID, and DuplicateCellId or
/// DuplicateCellName for repeated identities. v4.5 and later require IDs.
pub fn Notebook::Notebook(
  cells : ReadOnlyArray[Cell],
  minor~ : Int32 = 5,
  metadata~ : Metadata = Metadata::empty(),
) -> Notebook raise FormatError {
  if minor < 0 {
    raise UnsupportedVersion(major=4, minor~)
  }
  validate_notebook_metadata(metadata, "$.metadata")
  validate_cells(cells, minor)
  { minor, metadata, cells, extensions: { fields: {}, }, }
}

///|
/// Return the notebook file format's major version, always 4.
/// This is independent of the upstream Python library's release number.
pub fn Notebook::nbformat(_self : Notebook) -> Int32 {
  4
}

///|
/// Return the retained notebook file format minor version.
pub fn Notebook::nbformat_minor(self : Notebook) -> Int32 {
  self.minor
}

///|
/// Return immutable notebook metadata, including custom namespaces.
pub fn Notebook::metadata(self : Notebook) -> Metadata {
  self.metadata
}

///|
/// Return immutable cells in document order.
pub fn Notebook::cells(self : Notebook) -> ReadOnlyArray[Cell] {
  self.cells
}

///|
/// Return notebook-level fields outside metadata, cells and version fields.
pub fn Notebook::extensions(self : Notebook) -> JsonObject {
  self.extensions
}

///|
/// Look up a cell by zero-based document index. Return None for negative
/// indices or an index at or beyond the cell count.
pub fn Notebook::cell(self : Notebook, index : Int32) -> Cell? {
  self.cells.get(index)
}

///|
/// Find a cell by its validated ID. Return None if no cell has that ID.
pub fn Notebook::cell_by_id(self : Notebook, id : CellId) -> Cell? {
  for cell in self.cells {
    if cell.id == Some(id) {
      return Some(cell)
    }
  }
  None
}

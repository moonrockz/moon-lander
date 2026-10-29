///|
/// How conversion handles state without an equivalent in the target format.
pub(all) enum LossPolicy {
  Reject
  SourceOnly
} derive(Eq, Debug)

///|
pub extend LossPolicy with Eq::{equal, not_equal}

///|
pub extend LossPolicy with @debug.Debug::{to_repr}

///|
/// A discarded source-format value. Cell positions are zero-based.
pub(all) enum Loss {
  CellIdentity(cell~ : Int)
  CellMetadata(cell~ : Int)
  Outputs(cell~ : Int)
  ExecutionCount(cell~ : Int)
  Attachments(cell~ : Int)
  CellExtensions(cell~ : Int)
  NotebookExtensions
  NotebookKernelMetadata
} derive(Eq, Debug)

///|
pub extend Loss with Eq::{equal, not_equal}

///|
pub extend Loss with @debug.Debug::{to_repr}

///|
/// Conversion refuses unknown source payloads and malformed kernel metadata.
/// Strict policy additionally refuses every reported loss.
pub(all) suberror ConversionError {
  Lossy(ReadOnlyArray[Loss])
  UnsupportedCell(cell~ : Int, cell_type~ : String)
  InvalidKernelMetadata(path~ : String)
} derive(Eq, Debug)

///|
pub extend ConversionError with Eq::{equal, not_equal}

///|
pub extend ConversionError with @debug.Debug::{to_repr}

///|
/// A converted immutable notebook, its already serialized text and loss report.
struct Conversion[T] {
  notebook : T
  text : String
  losses : ReadOnlyArray[Loss]
}

///|
/// Return the converted notebook value.
pub fn[T] Conversion::notebook(self : Conversion[T]) -> T { self.notebook }

///|
/// Return the serialized target representation, checked during conversion.
pub fn[T] Conversion::text(self : Conversion[T]) -> String { self.text }

///|
/// Return the immutable report of discarded source-format state.
pub fn[T] Conversion::losses(self : Conversion[T]) -> ReadOnlyArray[Loss] { self.losses }

///|
/// A lossless-source kernel configuration and explicit conversion loss policy.
struct Converter {
  codec : @dib.Codec
  policy : LossPolicy
}

///|
/// Use standard kernels or a custom default descriptor. Strict conversion is
/// the default; SourceOnly permits reported losses. Plain text maps to raw cells.
pub fn Converter::new(
  default? : &@dib.KernelDescriptor,
  policy~ : LossPolicy = Reject,
) -> Converter raise @dib.FormatError {
  let codec = @dib.Codec::lossless(default?)
  let codec = if codec.registry().resolve("text") == Some(@dib.KernelName("text")) {
    codec
  } else {
    codec.with_kernel(@dib.KernelInfo(@dib.KernelName("text")))
  }
  { codec, policy, }
}

///|
/// Register a kernel descriptor in a new converter.
pub fn Converter::with_kernel(
  self : Converter,
  descriptor : &@dib.KernelDescriptor,
) -> Converter raise @dib.FormatError {
  { ..self, codec: self.codec.with_kernel(descriptor), }
}

///|
fn[T] Converter::finish(
  self : Converter,
  notebook : T,
  text : String,
  losses : Array[Loss],
) -> Conversion[T] raise ConversionError {
  let losses = ReadOnlyArray::from_array(losses[:])
  if self.policy == Reject && !losses.is_empty() { raise Lossy(losses) }
  { notebook, text, losses, }
}

///|
fn registry_json(registry : @dib.KernelRegistry) -> Json {
  let items : Array[Json] = []
  for info in registry.kernels() {
    let fields : Map[String, Json] = {
      "name": Json(info.name().to_string()),
      "aliases": Json(info.aliases().map(name => name.to_string()).iter().to_array()),
    }
    if info.language() is Some(language) { fields["languageName"] = Json(language) }
    items.push(Json(fields))
  }
  { "defaultKernelName": Json(registry.default_kernel().to_string()), "items": Json(items), }
}

///|
/// Convert every DIB source cell, including empty cells. Per-cell Polyglot
/// kernel metadata and notebook registrations retain custom kernel identity.
/// Non-JSON Ion metadata is refused by the existing typed JSON conversion error.
pub fn Converter::to_jupyter(
  self : Converter,
  notebook : @dib.Notebook,
) -> Conversion[@nbformat.Notebook] raise {
  let losses : Array[Loss] = []
  guard notebook.metadata().to_json() is Object(fields) else {
    raise InvalidKernelMetadata(path="$.metadata")
  }
  let polyglot = match fields.get("polyglot_notebook") {
    None => Map([])
    Some(Object(value)) => value.copy()
    Some(_) => raise InvalidKernelMetadata(path="$.metadata.polyglot_notebook")
  }
  let registration = registry_json(notebook.registry())
  if polyglot.get("kernelInfo") is Some(previous) && previous != registration {
    losses.push(NotebookKernelMetadata)
  }
  polyglot["kernelInfo"] = registration
  fields["polyglot_notebook"] = Json(polyglot)
  let cells = []
  for index, cell in notebook.cells() {
    let source = cell.source()
    let kernel = cell.kernel().to_string()
    let content = match kernel {
      "markdown" => @nbformat.Markdown(source~, attachments=None)
      "text" => @nbformat.Raw(source~, attachments=None)
      _ => @nbformat.Code(source~, execution_count=None, outputs=[])
    }
    cells.push(@nbformat.Cell::Cell(content,
      id=Some(@nbformat.CellId("cell-\{index}")),
      metadata=@notebooks.Metadata({ "polyglot_notebook": { "kernelName": Json(kernel), }, }),
    ))
  }
  let converted = @nbformat.Notebook::Notebook(
    ReadOnlyArray::from_array(cells[:]), metadata=@notebooks.Metadata(Json(fields)),
  )
  self.finish(converted, converted.to_string(), losses)
}

///|
fn has_extra_cell_metadata(cell : @nbformat.Cell) -> Bool raise @notebooks.MetadataError {
  let keys = cell.metadata().keys()
  if keys.is_empty() { return false }
  if keys.length() != 1 || keys[0] != "polyglot_notebook" { return true }
  match cell.metadata().get_json("polyglot_notebook") {
    Some(Object(fields)) => {
      if fields.length() != 1 { return true }
      guard fields.get("kernelName") is Some(String(name)) else { return true }
      match cell.cell_type() {
        "markdown" => name != "markdown"
        "raw" => name != "text"
        _ => false
      }
    }
    _ => true
  }
}

///|
fn cell_kernel(
  cell : @nbformat.Cell,
  index : Int,
  default_kernel : @dib.KernelName,
  registry : @dib.KernelRegistry,
) -> @dib.KernelName raise {
  if cell.cell_type() == "markdown" { return @dib.KernelName("markdown") }
  if cell.cell_type() == "raw" { return @dib.KernelName("text") }
  let name = match cell.metadata().get_json("polyglot_notebook") {
    None => None
    Some(Object(fields)) => {
      guard fields.get("kernelName") is Some(String(name)) else {
        raise InvalidKernelMetadata(path="$.cells[\{index}].metadata.polyglot_notebook.kernelName")
      }
      Some(name)
    }
    Some(_) => raise InvalidKernelMetadata(path="$.cells[\{index}].metadata.polyglot_notebook")
  }
  if name is Some(name) {
    guard registry.resolve(name) is Some(kernel) else { raise @dib.UnknownKernel(name) }
    return kernel
  }
  default_kernel
}

///|
fn notebook_default(
  notebook : @nbformat.Notebook,
  registry : @dib.KernelRegistry,
) -> @dib.KernelName raise {
  if notebook.metadata().get("kernelInfo") is Some(_) { return registry.default_kernel() }
  if notebook.metadata().get_json("polyglot_notebook") is Some(Object(info)) && info.contains("kernelInfo") {
    return registry.default_kernel()
  }
  if notebook.metadata().get_json("kernelspec") is Some(Object(fields)) && fields.get("name") is Some(String(name)) {
    if registry.resolve(name) is Some(kernel) { return kernel }
    if notebook.metadata().get_json("language_info") is Some(Object(language)) && language.get("name") is Some(String(name)) && registry.resolve(name) is Some(kernel) {
      return kernel
    }
    raise @dib.UnknownKernel(name)
  }
  registry.default_kernel()
}

///|
/// Convert recognized Jupyter source cells to lossless DIB. Strict mode refuses
/// IDs, metadata or execution state that DIB cannot store. SourceOnly returns
/// those losses with the converted notebook. Registered selector collisions
/// are refused during serialization, before any conversion result is returned.
pub fn Converter::to_dib(
  self : Converter,
  notebook : @nbformat.Notebook,
) -> Conversion[@dib.Notebook] raise {
  let registry = self.codec.notebook([], metadata=notebook.metadata()).registry()
  let needs_default = notebook.cells().iter().any(cell => {
    cell.cell_type() == "code" && cell.metadata().get("polyglot_notebook") is None
  })
  let default_kernel = if needs_default {
    notebook_default(notebook, registry)
  } else {
    registry.default_kernel()
  }
  let losses = []
  if !notebook.extensions().keys().is_empty() { losses.push(NotebookExtensions) }
  let cells = []
  for index, cell in notebook.cells() {
    guard cell.source() is Some(source) else {
      raise UnsupportedCell(cell=index, cell_type=cell.cell_type())
    }
    if cell.id() is Some(_) { losses.push(CellIdentity(cell=index)) }
    if has_extra_cell_metadata(cell) { losses.push(CellMetadata(cell=index)) }
    if !cell.extensions().keys().is_empty() { losses.push(CellExtensions(cell=index)) }
    match cell.content() {
      Code(execution_count~, outputs~, ..) => {
        if execution_count is Some(_) { losses.push(ExecutionCount(cell=index)) }
        if !outputs.is_empty() { losses.push(Outputs(cell=index)) }
      }
      Markdown(attachments~, ..) | Raw(attachments~, ..) =>
        if attachments is Some(_) { losses.push(Attachments(cell=index)) }
      Unknown(_) => raise UnsupportedCell(cell=index, cell_type=cell.cell_type())
    }
    let kernel = cell_kernel(cell, index, default_kernel, registry)
    cells.push(@dib.Cell::Cell(source, kernel~, source_mode=@dib.Lossless))
  }
  let converted = @dib.Notebook::Notebook(
    ReadOnlyArray::from_array(cells[:]), registry~, metadata=notebook.metadata(),
  )
  self.finish(converted, converted.to_string(source_mode=@dib.Lossless), losses)
}

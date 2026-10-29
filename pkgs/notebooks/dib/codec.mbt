///|
fn normalize_line_endings(source : String) -> String {
  source
  .replace_all(old="\r\n", new="\n")
  .replace_all(old="\r", new="\n")
}

///|
fn lines(source : String) -> Array[String] {
  normalize_line_endings(source)
  .split("\n")
  .map(line => line.to_owned())
  .to_array()
}

///|
fn normalize_source(source : String) -> String {
  let lines = lines(source)
  let mut first = 0
  let mut last = lines.length()
  while first < last && lines[first].is_empty() {
    first += 1
  }
  while last > first && lines[last - 1].is_empty() {
    last -= 1
  }
  lines[first:last].join("\n")
}

///|
fn source_in_mode(source : String, mode : SourceMode) -> String {
  match mode {
    Normalized => normalize_source(source)
    Lossless => normalize_line_endings(source)
  }
}

///|
fn with_markdown(registry : KernelRegistry) -> KernelRegistry raise FormatError {
  if registry.resolve("markdown") is Some(_) {
    return registry
  }
  KernelRegistry::KernelRegistry(
    ReadOnlyArray::from_iter(
      registry.kernels
      .iter()
      .concat(
        [
          KernelInfo::KernelInfo(KernelName("markdown"), aliases=[
            KernelName("md"),
          ]),
        ].iter(),
      ),
    ),
    default_kernel=registry.default_kernel,
  )
}

///|
fn registry_from_metadata(
  metadata : Metadata,
  registry : KernelRegistry,
) -> KernelRegistry raise FormatError {
  let mut kernels = registry.kernels
  let mut default_kernel = registry.default_kernel
  let mut info = registry_metadata_field(metadata, "kernelInfo")
  if info is None {
    info = registry_metadata_field(metadata, "polyglot_notebook")
    if info is None {
      info = registry_metadata_field(metadata, "dotnet_interactive")
    }
    // Polyglot notebooks nest registrations under kernelInfo; retain the
    // existing flat namespace form as well as the top-level form.
    if info is Some(Object(fields)) && fields.get("kernelInfo") is Some(nested) {
      info = Some(nested)
    }
  }
  if info is Some(value) {
    guard value is Object(fields) else {
      raise InvalidMetadata(line=1, message="kernel info must be an object")
    }
    if fields.get("items") is Some(value) {
      guard value is Array(items) else {
        raise InvalidMetadata(
          line=1,
          message="kernelInfo.items must be an array",
        )
      }
      let declared = []
      for item in items {
        guard item is Object(fields) && fields.get("name") is Some(String(name)) else {
          raise InvalidMetadata(line=1, message="each kernel needs a name")
        }
        let name = KernelName(name)
        let aliases : ReadOnlyArray[KernelName] = match fields.get("aliases") {
          None | Some(Null) => []
          Some(Array(items)) =>
            ReadOnlyArray::from_array(
              items.map(item => {
                guard item is String(alternate) else {
                  raise InvalidMetadata(
                    line=1,
                    message="kernel aliases must be strings",
                  )
                }
                KernelName(alternate)
              })[:],
            )
          _ =>
            raise InvalidMetadata(
              line=1,
              message="kernel aliases must be an array",
            )
        }
        let language = match fields.get("languageName") {
          None | Some(Null) => None
          Some(String(language)) => Some(language)
          _ =>
            raise InvalidMetadata(
              line=1,
              message="languageName must be a string",
            )
        }
        declared.push(KernelInfo::KernelInfo(name, aliases~, language~))
      }
      // Metadata definitions take precedence; retain environment-only kernels.
      let names = declared.map(info => info.name)
      for kernel in kernels {
        if !names.contains(kernel.name) {
          declared.push(kernel)
        }
      }
      kernels = ReadOnlyArray::from_array(declared[:])
    }
    match fields.get("defaultKernelName") {
      Some(String(name)) => default_kernel = KernelName(name)
      None | Some(Null) => ()
      _ =>
        raise InvalidMetadata(
          line=1,
          message="defaultKernelName must be a string",
        )
    }
  }
  with_markdown(KernelRegistry::KernelRegistry(kernels, default_kernel~))
}

///|
/// Read a DIB source notebook without executing it. Registered, exact
/// column-zero selectors start cells; other directives remain source. Read
/// the first exact metadata section and apply its registrations. #!meta and
/// #!meta json read JSON; #!meta yaml, #!meta toml and #!meta ion are extensions.
/// Normalize line endings. Normalized mode trims empty boundary lines and
/// omits empty sections; an empty document yields one empty cell. Lossless
/// retains explicit cells and boundary lines; empty text yields no cells.
/// Accept a leading BOM.
/// Raise FormatError for invalid metadata or conflicting kernel registrations.
pub fn parse(
  source : String,
  registry~ : KernelRegistry = KernelRegistry::standard(),
  source_mode~ : SourceMode = Normalized,
) -> Notebook raise FormatError {
  let source = if source.has_prefix("\u{FEFF}") {
    source[1:].to_owned()
  } else {
    source
  }
  let lines = lines(source)
  // A final LF terminates the last source line. Its split sentinel is framing,
  // not another empty payload line, in the lossless representation.
  let line_count = if source_mode == Lossless && lines.last() == Some("") {
    lines.length() - 1
  } else {
    lines.length()
  }
  let mut registry = with_markdown(registry)
  let mut kernel = registry.default_kernel
  let cells = []
  let pending : Array[String] = []
  let mut metadata = Metadata::empty()
  let mut found_metadata = false
  let mut explicit_cell = false
  let mut i = 0
  while i < line_count {
    let line = lines[i]
    if !found_metadata && metadata_format(line) is Some(format) {
      found_metadata = true
      let start = i + 1
      i += 1
      while i < line_count && !lines[i].has_prefix("#!") {
        i += 1
      }
      metadata = parse_metadata(lines[start:i].join("\n"), format, start + 1)
      registry = registry_from_metadata(metadata, registry)
      if cells.is_empty() && pending.iter().all(line => line.is_empty()) {
        kernel = registry.default_kernel
      }
      continue
    }
    let selector = if line.has_prefix("#!") {
      registry.resolve(line[2:].to_owned())
    } else {
      None
    }
    if selector is Some(next_kernel) {
      let source = source_in_mode(pending.join("\n"), source_mode)
      if !source.is_empty() ||
        (source_mode == Lossless && (explicit_cell || !pending.is_empty())) {
        cells.push(Cell::{ source, kernel, })
      }
      pending.clear()
      kernel = next_kernel
      explicit_cell = true
    } else {
      pending.push(line)
    }
    i += 1
  }
  let source = source_in_mode(pending.join("\n"), source_mode)
  if !source.is_empty() ||
    (source_mode == Lossless && (explicit_cell || !pending.is_empty())) {
    cells.push(Cell::{ source, kernel, })
  }
  if cells.is_empty() && source_mode == Normalized {
    cells.push(Cell::{ source: "", kernel, })
  }
  { cells: ReadOnlyArray::from_array(cells[:]), metadata, registry, }
}

///|
/// Serialize normalized DIB source using canonical kernel selectors.
/// Normalized mode omits empty cells and pads selectors. Lossless emits every
/// cell without payload padding, retaining empty cells and boundary lines when
/// reread in Lossless mode. Retain document metadata. Auto output uses JSON when
/// it preserves the metadata, otherwise Ion. Explicit Json rejects data loss.
/// Emit a header when needed to preserve later metadata directives as source. Raise
/// UnrepresentableSource if embedded registered selectors would split a cell.
/// Custom kernels supplied only by the environment require the same registry
/// on subsequent reads; the writer does not inject those registrations.
pub fn Notebook::to_string(
  self : Notebook,
  metadata_output~ : MetadataOutput = Auto,
  source_mode~ : SourceMode = Normalized,
) -> String raise FormatError {
  let output = []
  let contains_metadata_directive = self.cells
    .iter()
    .any(cell => lines(cell.source).iter().any(line => metadata_format(line) is Some(_)))
  if !self.metadata.is_empty() || contains_metadata_directive {
    output.push(write_metadata(self.metadata, metadata_output))
  }
  for i, cell in self.cells {
    if cell.source.is_empty() && source_mode == Normalized {
      continue
    }
    for j, line in lines(cell.source) {
      if line.has_prefix("#!") &&
        self.registry.resolve(line[2:].to_owned()) is Some(_) {
        raise UnrepresentableSource(cell=i, line=j + 1)
      }
    }
    let padding = if source_mode == Normalized { "\n" } else { "" }
    output.push("#!" + cell.kernel.value + "\n" + padding + cell.source + "\n")
  }
  output.join(if source_mode == Normalized { "\n" } else { "" })
}

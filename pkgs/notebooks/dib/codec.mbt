///|
fn lines(source : String) -> Array[String] {
  source
  .replace_all(old="\r\n", new="\n")
  .replace_all(old="\r", new="\n")
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
  }
  if info is None {
    info = registry_metadata_field(metadata, "dotnet_interactive")
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
/// Normalize line endings, trim empty boundary lines and omit empty sections;
/// an empty document yields one empty cell. Accept a leading BOM.
/// Raise FormatError for invalid metadata or conflicting kernel registrations.
pub fn parse(
  source : String,
  registry~ : KernelRegistry = KernelRegistry::standard(),
) -> Notebook raise FormatError {
  let source = if source.has_prefix("\u{FEFF}") {
    source[1:].to_owned()
  } else {
    source
  }
  let lines = lines(source)
  let mut registry = with_markdown(registry)
  let mut kernel = registry.default_kernel
  let cells = []
  let pending : Array[String] = []
  let mut metadata = Metadata::empty()
  let mut found_metadata = false
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    if !found_metadata && metadata_format(line) is Some(format) {
      found_metadata = true
      let start = i + 1
      i += 1
      while i < lines.length() && !lines[i].has_prefix("#!") {
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
      let source = normalize_source(pending.join("\n"))
      if !source.is_empty() {
        cells.push(Cell::{ source, kernel, })
      }
      pending.clear()
      kernel = next_kernel
    } else {
      pending.push(line)
    }
    i += 1
  }
  let source = normalize_source(pending.join("\n"))
  if !source.is_empty() {
    cells.push(Cell::{ source, kernel, })
  }
  if cells.is_empty() {
    cells.push(Cell::{ source: "", kernel, })
  }
  { cells: ReadOnlyArray::from_array(cells[:]), metadata, registry, }
}

///|
/// Serialize normalized DIB source using canonical kernel selectors.
/// Omit empty cells and retain document metadata. Auto output uses JSON when
/// it preserves the metadata, otherwise Ion. Explicit Json rejects data loss.
/// Emit a header when needed to preserve later metadata directives as source. Raise
/// UnrepresentableSource if embedded registered selectors would split a cell.
/// Custom kernels supplied only by the environment require the same registry
/// on subsequent reads; the writer does not inject those registrations.
pub fn Notebook::to_string(self : Notebook, metadata_output~ : MetadataOutput = Auto) -> String raise FormatError {
  let output = []
  let contains_metadata_directive = self.cells
    .iter()
    .any(cell => lines(cell.source).iter().any(line => metadata_format(line) is Some(_)))
  if !self.metadata.is_empty() || contains_metadata_directive {
    output.push(write_metadata(self.metadata, metadata_output))
  }
  for i, cell in self.cells {
    if cell.source.is_empty() {
      continue
    }
    for j, line in lines(cell.source) {
      if line.has_prefix("#!") &&
        self.registry.resolve(line[2:].to_owned()) is Some(_) {
        raise UnrepresentableSource(cell=i, line=j + 1)
      }
    }
    output.push("#!" + cell.kernel.value + "\n\n" + cell.source + "\n")
  }
  output.join("\n")
}

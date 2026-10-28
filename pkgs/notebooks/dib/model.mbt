///|
/// A DIB metadata, kernel registration or serialization failure.
/// UnrepresentableSource identifies a zero-based cell index and a one-based
/// line within its normalized source. Metadata line numbers are one-based.
pub(all) suberror FormatError {
  /// Invalid metadata syntax, representation or structure. Line numbers are one-based;
  /// programmatic validation and registration diagnostics use line 1.
  InvalidMetadata(line~ : Int32, message~ : String)
  /// A blank, reserved, multiline or otherwise invalid kernel name.
  InvalidKernelName(String)
  /// A canonical name or alias occurs more than once in a registry.
  DuplicateKernelName(String)
  /// A default or cell kernel name cannot be resolved by the registry.
  UnknownKernel(String)
  /// A zero-based cell and one-based source line contain a selector that
  /// would split the cell if serialized.
  UnrepresentableSource(cell~ : Int32, line~ : Int32)
} derive(Eq, Debug)

///|
pub extend FormatError with Eq::{equal, not_equal}

///|
pub extend FormatError with @debug.Debug::{to_repr}

///|
/// A validated kernel name or alias. Names are case-sensitive and nonblank;
/// they cannot start with #, contain line breaks or name a metadata header.
struct KernelName {
  value : String
} derive(Eq, Debug)

///|
pub extend KernelName with Eq::{equal, not_equal}

///|
pub extend KernelName with @debug.Debug::{to_repr}

///|
/// Validate a case-sensitive kernel name or alias. Raise InvalidKernelName
/// for blank names, leading #, line breaks or reserved metadata selectors.
/// This validates spelling, not membership in a kernel registry.
///
/// ```mbt check
/// test "doc: resolve a kernel alias" {
///   let registry = @dib.KernelRegistry::standard()
///   let name = @dib.KernelName("csharp")
///   @expect.expect(registry.resolve("c#")).to_equal(Some(name))
/// }
/// ```
pub fn KernelName::KernelName(value : String) -> KernelName raise FormatError {
  if value.trim().is_empty() ||
    value.has_prefix("#") ||
    metadata_format("#!" + value) is Some(_) ||
    value.contains("\n") ||
    value.contains("\r") {
    raise InvalidKernelName(value)
  }
  { value, }
}

///|
/// Return the name or alias exactly as supplied.
pub fn KernelName::to_string(self : KernelName) -> String {
  self.value
}

///|
/// An immutable registration describing a canonical kernel name, its aliases
/// and an optional language label. Names alone do not execute or install a kernel.
struct KernelInfo {
  name : KernelName
  aliases : ReadOnlyArray[KernelName]
  language : String?
} derive(Eq, Debug)

///|
pub extend KernelInfo with Eq::{equal, not_equal}

///|
pub extend KernelInfo with @debug.Debug::{to_repr}

///|
/// Describe a kernel using validated names. Defaults to no aliases and no
/// language label. Registry construction checks name and alias collisions.
pub fn KernelInfo::KernelInfo(
  name : KernelName,
  aliases~ : ReadOnlyArray[KernelName] = [],
  language~ : String? = None,
) -> KernelInfo {
  { name, aliases, language, }
}

///|
/// Return this registration's canonical name.
pub fn KernelInfo::name(self : KernelInfo) -> KernelName {
  self.name
}

///|
/// Return immutable case-sensitive aliases for this kernel.
pub fn KernelInfo::aliases(self : KernelInfo) -> ReadOnlyArray[KernelName] {
  self.aliases
}

///|
/// Return the optional language label supplied by the registration.
pub fn KernelInfo::language(self : KernelInfo) -> String? {
  self.language
}

///|
/// An immutable execution environment used to distinguish cell selectors
/// from source directives. Lookups map canonical names and aliases to canonical
/// KernelName values. Parsing also supplies the Markdown pseudo-kernel.
struct KernelRegistry {
  kernels : ReadOnlyArray[KernelInfo]
  default_kernel : KernelName
  aliases : Map[String, KernelName]
} derive(Eq, Debug)

///|
pub extend KernelRegistry with Eq::{equal, not_equal}

///|
pub extend KernelRegistry with @debug.Debug::{to_repr}

///|
/// Build a registry and resolve its required default name or alias.
/// Raise DuplicateKernelName for any repeated name/alias, including within
/// one registration, or UnknownKernel if the default cannot be resolved.
pub fn KernelRegistry::KernelRegistry(
  kernels : ReadOnlyArray[KernelInfo],
  default_kernel~ : KernelName,
) -> KernelRegistry raise FormatError {
  let aliases = Map([])
  for kernel in kernels {
    for alternate in kernel.aliases.iter().concat([kernel.name].iter()) {
      if aliases.contains(alternate.value) {
        raise DuplicateKernelName(alternate.value)
      }
      aliases[alternate.value] = kernel.name
    }
  }
  guard aliases.get(default_kernel.value) is Some(default_kernel) else {
    raise UnknownKernel(default_kernel.value)
  }
  { kernels, default_kernel, aliases, }
}

///|
/// Return immutable registrations in their stored order.
pub fn KernelRegistry::kernels(
  self : KernelRegistry,
) -> ReadOnlyArray[KernelInfo] {
  self.kernels
}

///|
/// Return the default kernel's canonical name.
pub fn KernelRegistry::default_kernel(self : KernelRegistry) -> KernelName {
  self.default_kernel
}

///|
/// Resolve an exact, case-sensitive name or alias to its canonical name.
/// Return None for an unregistered name.
pub fn KernelRegistry::resolve(
  self : KernelRegistry,
  name : String,
) -> KernelName? {
  self.aliases.get(name)
}

///|
/// Return the standard execution-kernel registrations with C# as default.
/// Includes C#, F#, PowerShell, JavaScript, HTML, SQL, KQL, HTTP, value and
/// Mermaid. Parsing and Notebook construction also add Markdown as needed.
pub fn KernelRegistry::standard() -> KernelRegistry {
  let descriptions : Array[(String, Array[String])] = [
    ("csharp", ["cs", "C#", "c#"]),
    ("fsharp", ["fs", "F#", "f#"]),
    ("pwsh", ["powershell"]),
    ("javascript", ["js"]),
    ("html", []),
    ("sql", []),
    ("kql", []),
    ("http", []),
    ("value", []),
    ("mermaid", []),
  ]
  let kernels = []
  let aliases = Map([])
  for (name, names) in descriptions {
    let name = KernelName::{ value: name, }
    aliases[name.value] = name
    for alternate in names {
      aliases[alternate] = name
    }
    kernels.push(KernelInfo::{
      name,
      aliases: ReadOnlyArray::from_iter(
        names.iter().map(value => KernelName::{ value, }),
      ),
      language: None,
    })
  }
  {
    kernels: ReadOnlyArray::from_array(kernels[:]),
    default_kernel: { value: "csharp", },
    aliases,
  }
}

///|
/// Select the compatible normalized DIB representation or preserve source-cell
/// boundaries and LF-normalized payload exactly through the lossless codec.
pub(all) enum SourceMode {
  /// Trim empty boundary lines and omit empty source sections.
  Normalized
  /// Retain empty cells and boundary lines, without writer padding.
  Lossless
} derive(Eq, Debug)

///|
pub extend SourceMode with Eq::{equal, not_equal}

///|
pub extend SourceMode with @debug.Debug::{to_repr}

///|
/// An immutable source cell with a kernel name. Sources normalize line
/// endings and, by default, trim only empty boundary lines. Lossless mode
/// retains boundary lines. Notebook construction resolves kernel aliases;
/// a standalone cell may still contain an alias.
struct Cell {
  source : String
  kernel : KernelName
} derive(Eq, Debug)

///|
pub extend Cell with Eq::{equal, not_equal}

///|
pub extend Cell with @debug.Debug::{to_repr}

///|
/// Normalize LF, CRLF and CR to LF. Normalized mode removes empty boundary
/// lines; Lossless retains them. Retain whitespace-only and internal blank
/// lines in both modes. Registry membership is
/// checked by Notebook construction; selector conflicts are checked on writing.
pub fn Cell::Cell(
  source : String,
  kernel~ : KernelName,
  source_mode~ : SourceMode = Normalized,
) -> Cell {
  { source: source_in_mode(source, source_mode), kernel, }
}

///|
/// Return normalized cell source without its kernel selector.
pub fn Cell::source(self : Cell) -> String {
  self.source
}

///|
/// Return the cell's kernel name. Notebook construction canonicalizes
/// registered aliases; a standalone Cell retains the supplied name.
pub fn Cell::kernel(self : Cell) -> KernelName {
  self.kernel
}

///|
/// Classify markdown and md cells as Markdown and other kernels as Code.
pub fn Cell::kind(self : Cell) -> @notebooks.CellKind {
  if self.kernel.value == "markdown" || self.kernel.value == "md" {
    @notebooks.Markdown
  } else {
    @notebooks.Code
  }
}

///|
/// An immutable column-zero #! line retained in cell source, with a name,
/// unparsed arguments, exact normalized line text and one-based source line.
/// This view does not execute commands or interpret quoted arguments.
struct Directive {
  text : String
  name : String
  arguments : String
  line : Int32
} derive(Eq, Debug)

///|
pub extend Directive with Eq::{equal, not_equal}

///|
pub extend Directive with @debug.Debug::{to_repr}

///|
/// Return the complete #! source line, without a newline terminator.
pub fn Directive::text(self : Directive) -> String {
  self.text
}

///|
/// Return the command token after #!, stopping at the first space or tab.
pub fn Directive::name(self : Directive) -> String {
  self.name
}

///|
/// Return the remaining command text with leading whitespace removed.
/// Arguments remain uninterpreted; quoting is not parsed.
pub fn Directive::arguments(self : Directive) -> String {
  self.arguments
}

///|
/// Return the one-based line relative to normalized cell source, not the
/// line number in the original DIB document.
pub fn Directive::line(self : Directive) -> Int32 {
  self.line
}

///|
/// Return column-zero #! lines in source order as immutable directive views.
/// Indented lines are excluded. Kernel selectors consumed during parsing are
/// cell properties and do not appear in parsed cell source.
pub fn Cell::directives(self : Cell) -> ReadOnlyArray[Directive] {
  let directives = []
  for i, text in self.source.split("\n").to_array() {
    if text.has_prefix("#!") {
      let rest = text[2:]
      let mut end = 0
      while end < rest.length() &&
            rest.code_unit_at(end) != 32 &&
            rest.code_unit_at(end) != 9 {
        end += 1
      }
      directives.push({
        text: text.to_owned(),
        name: rest[:end].to_owned(),
        arguments: rest[end:].trim_start().to_owned(),
        line: i + 1,
      })
    }
  }
  ReadOnlyArray::from_array(directives[:])
}

///|
/// An immutable DIB source notebook with ordered cells, metadata and the
/// kernel registry needed to interpret its selectors. DIB stores no outputs.
struct Notebook {
  cells : ReadOnlyArray[Cell]
  metadata : Metadata
  registry : KernelRegistry
} derive(Eq, Debug)

///|
pub extend Notebook with Eq::{equal, not_equal}

///|
pub extend Notebook with @debug.Debug::{to_repr}

///|
/// Build a notebook with empty metadata and the standard registry by default.
/// Interpret metadata registrations and canonicalize each cell's kernel alias.
/// Raise FormatError for invalid registration metadata, duplicate kernel names
/// or unregistered cell kernels. Empty cells remain in the model; select
/// Lossless when writing and rereading to retain them through the codec.
pub fn Notebook::Notebook(
  cells : ReadOnlyArray[Cell],
  metadata~ : Metadata = Metadata::empty(),
  registry~ : KernelRegistry = KernelRegistry::standard(),
) -> Notebook raise FormatError {
  let registry = registry_from_metadata(metadata, registry)
  let cells = cells.map(cell => {
    guard registry.resolve(cell.kernel.value) is Some(kernel) else {
      raise UnknownKernel(cell.kernel.value)
    }
    Cell::{ source: cell.source, kernel, }
  })
  { cells, metadata, registry, }
}

///|
/// Return immutable cells in source order, including constructed empty cells.
pub fn Notebook::cells(self : Notebook) -> ReadOnlyArray[Cell] {
  self.cells
}

///|
/// Look up a zero-based cell index. Return None for negative or out-of-range
/// indices.
pub fn Notebook::cell(self : Notebook, index : Int32) -> Cell? {
  self.cells.get(index)
}

///|
/// Return immutable document metadata, retaining custom namespaces.
pub fn Notebook::metadata(self : Notebook) -> Metadata {
  self.metadata
}

///|
/// Return the effective registry, including metadata declarations and
/// Markdown. Retain it when rereading custom environment-dependent selectors.
pub fn Notebook::registry(self : Notebook) -> KernelRegistry {
  self.registry
}

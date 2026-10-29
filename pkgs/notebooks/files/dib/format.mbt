///|
/// A malformed tree declaration or unsupported export kernel. Declaration
/// coordinates use a zero-based cell index and one-based normalized source line.
pub(all) suberror DeclarationError {
  InvalidDeclaration(cell~ : Int, line~ : Int, text~ : String)
  ReservedKernel(@source_dib.KernelName)
  NonCanonicalKernel(name~ : @source_dib.KernelName, canonical~ : @source_dib.KernelName)
} derive(Eq, Debug)

///|
pub extend DeclarationError with Eq::{equal, not_equal}

///|
pub extend DeclarationError with @debug.Debug::{to_repr}

///|
/// A lossless DIB tree format. Reserved tree and text kernels describe manifest
/// cells and plain text files; other registrations come from the caller.
struct Format {
  codec : @source_dib.Codec
}

///|
/// Configure the default kernel and lossless tree transport once.
pub fn Format::new(default? : &@source_dib.KernelDescriptor) -> Format raise @source_dib.FormatError {
  let codec = @source_dib.Codec::lossless(default?)
    .with_kernel(@source_dib.KernelInfo(@source_dib.KernelName("tree")))
  let codec = if codec.registry().resolve("text") == Some(@source_dib.KernelName("text")) {
    codec
  } else {
    codec.with_kernel(@source_dib.KernelInfo(@source_dib.KernelName("text")))
  }
  { codec, }
}

///|
/// Add a kernel descriptor in a new format. Existing names and aliases cannot
/// be replaced; collisions raise DuplicateKernelName.
pub fn Format::with_kernel(
  self : Format,
  descriptor : &@source_dib.KernelDescriptor,
) -> Format raise @source_dib.FormatError {
  { codec: self.codec.with_kernel(descriptor), }
}

///|
/// Return this format's immutable DIB registry.
pub fn Format::registry(self : Format) -> @source_dib.KernelRegistry {
  self.codec.registry()
}

///|
/// Construct a file with the configured default or resolve a supplied kernel
/// alias once. The result stores the canonical name required for tree export.
pub fn Format::file(
  self : Format,
  path : @files.TreePath,
  source : String,
  kernel? : @source_dib.KernelName,
) -> @files.TextFile raise @source_dib.FormatError {
  let cell = self.codec.cell(source, kernel?)
  @files.TextFile::new(path, cell.source(), kernel=cell.kernel())
}

///|
fn declaration_path(
  text : String,
  command : String,
  cell : Int,
  line : Int,
) -> @files.TreePath raise {
  guard text.has_prefix(command + " ") || text.has_prefix(command + "\t") else {
    raise InvalidDeclaration(cell~, line~, text~)
  }
  let argument = text[command.length():].trim_start().to_owned()
  let raw = if argument.has_prefix("\"") {
    let json = @json.parse(argument) catch {
      _ => raise InvalidDeclaration(cell~, line~, text~)
    }
    guard json is String(value) else { raise InvalidDeclaration(cell~, line~, text~) }
    value
  } else {
    argument
  }
  @files.TreePath::parse(raw)
}

///|
/// Project marked file cells and tree manifests without changing the notebook.
/// Only a first-line file directive is transport; later directives are content.
/// Parse the notebook in Lossless mode first; earlier trimming cannot be undone.
pub fn Format::from_notebook(
  _self : Format,
  notebook : @source_dib.Notebook,
) -> @files.FileTree raise {
  let files = []
  let directories = []
  for cell_index, cell in notebook.cells() {
    let source = cell.source()
    let lines = source.split("\n").to_array()
    if cell.kernel().to_string() == "tree" {
      for index, line in lines {
        if line.is_empty() { continue }
        directories.push(declaration_path(line.to_owned(), "#!directory", cell_index, index + 1))
      }
    } else if lines[0] == "#!file" || lines[0].has_prefix("#!file ") || lines[0].has_prefix("#!file\t") {
      let path = declaration_path(lines[0].to_owned(), "#!file", cell_index, 1)
      files.push(@files.TextFile::new(path, lines[1:].join("\n"), kernel=cell.kernel()))
    }
  }
  @files.FileTree::new(ReadOnlyArray::from_array(files[:]), directories=ReadOnlyArray::from_array(directories[:]))
}

///|
/// Read DIB text into the explicit tree projection. No source is executed.
pub fn Format::read(self : Format, text : String) -> @files.FileTree raise {
  self.from_notebook(self.codec.parse(text))
}

///|
/// Create a fresh DIB notebook representing a tree. Notes and execution state
/// from a previously projected notebook are not part of this operation.
pub fn Format::to_notebook(
  self : Format,
  tree : @files.FileTree,
) -> @source_dib.Notebook raise {
  let cells = []
  if !tree.explicit_directories().is_empty() {
    let manifest = tree.explicit_directories().map(path => {
      "#!directory " + Json(path.to_string()).stringify()
    }).join("\n")
    cells.push(self.codec.cell(manifest, kernel=@source_dib.KernelName("tree")))
  }
  for file in tree.files() {
    if file.kernel().to_string() == "tree" {
      raise ReservedKernel(file.kernel())
    }
    if self.codec.registry().resolve(file.kernel().to_string()) is Some(canonical) && canonical != file.kernel() {
      raise NonCanonicalKernel(name=file.kernel(), canonical~)
    }
    cells.push(self.codec.cell(
      "#!file " + Json(file.path().to_string()).stringify() + "\n" + file.source(),
      kernel=file.kernel(),
    ))
  }
  self.codec.notebook(ReadOnlyArray::from_array(cells[:]))
}

///|
/// Write a fresh lossless tree document. Registered selector collisions in
/// file content retain the ordinary DIB UnrepresentableSource error.
pub fn Format::write(self : Format, tree : @files.FileTree) -> String raise {
  self.codec.write(self.to_notebook(tree))
}

///|
pub impl @files.TreeFormat for Format with fn read(self, text) { self.read(text) }

///|
pub impl @files.TreeFormat for Format with fn write(self, tree) { self.write(tree) }

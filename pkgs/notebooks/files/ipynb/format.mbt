///|
/// A malformed VFS metadata declaration or marked cell without source.
pub(all) suberror MappingError {
  InvalidMetadata(path~ : String, expected~ : String)
  UnsupportedCell(index~ : Int, cell_type~ : String)
} derive(Eq, Debug)

///|
pub extend MappingError with Eq::{equal, not_equal}

///|
pub extend MappingError with @debug.Debug::{to_repr}

///|
/// The version-1 metadata.vfs convention for virtual text trees in Jupyter.
/// It describes file content and never executes notebook cells.
struct Format {}

///|
/// Select the source-only Jupyter VFS projection.
pub fn Format::new() -> Format { Format::{} }

///|
fn invalid(path : String, expected : String) -> Unit raise MappingError {
  raise InvalidMetadata(path~, expected~)
}

///|
fn required_string(
  fields : Map[String, Json],
  name : String,
  path : String,
) -> String raise MappingError {
  guard fields.get(name) is Some(String(value)) else {
    raise InvalidMetadata(path=path + "." + name, expected="required string")
  }
  value
}

///|
/// Extract explicitly marked source cells. Notes, outputs and attachments are
/// outside the tree; the original immutable notebook remains unchanged.
pub fn Format::from_notebook(
  _self : Format,
  notebook : @nbformat.Notebook,
) -> @files.FileTree raise {
  let directories = []
  match notebook.metadata().get_json("vfs") {
    None => ()
    Some(Object(fields)) => {
      guard fields.get("version") is Some(Number(version, ..)) && version == 1.0 else {
        invalid("$.metadata.vfs.version", "VFS version 1")
      }
      match fields.get("directories") {
        None => ()
        Some(Array(items)) =>
          for index, value in items {
            guard value is String(path) else {
              raise InvalidMetadata(path="$.metadata.vfs.directories[\{index}]", expected="relative path string")
            }
            directories.push(@files.TreePath::parse(path))
          }
        Some(_) => invalid("$.metadata.vfs.directories", "array of relative path strings")
      }
    }
    Some(_) => invalid("$.metadata.vfs", "object")
  }
  let files = []
  for index, cell in notebook.cells() {
    let location = "$.cells[\{index}].metadata.vfs"
    match cell.metadata().get_json("vfs") {
      None => ()
      Some(Object(fields)) => {
        let path = @files.TreePath::parse(required_string(fields, "path", location))
        let kernel = @source_dib.KernelName(required_string(fields, "kernel", location))
        guard cell.source() is Some(source) else {
          raise UnsupportedCell(index~, cell_type=cell.cell_type())
        }
        files.push(@files.TextFile::new(path, source, kernel~))
      }
      Some(_) => invalid(location, "object with path and kernel strings")
    }
  }
  @files.FileTree::new(ReadOnlyArray::from_array(files[:]), directories=ReadOnlyArray::from_array(directories[:]))
}

///|
/// Read valid notebook JSON and extract the explicit VFS tree projection.
pub fn Format::read(self : Format, source : String) -> @files.FileTree raise {
  self.from_notebook(@nbformat.parse(source))
}

///|
/// Create a fresh v4.5 notebook with stable file-order IDs and VFS version 1.
/// File content is the entire source. Outputs and attachments are not generated.
/// text becomes raw, markdown becomes Markdown, and other kernels become code.
pub fn Format::to_notebook(
  _self : Format,
  tree : @files.FileTree,
) -> @nbformat.Notebook raise {
  let directories : Array[Json] = []
  for path in tree.explicit_directories() { directories.push(Json(path.to_string())) }
  let metadata = @notebooks.Metadata({ "vfs": { "version": 1, "directories": Json(directories), }, })
  let cells = []
  for index, file in tree.files() {
    let metadata = @notebooks.Metadata({ "vfs": {
      "path": Json(file.path().to_string()),
      "kernel": Json(file.kernel().to_string()),
    }, })
    let source = file.source()
    let content = match file.kernel().to_string() {
      "markdown" => @nbformat.Markdown(source~, attachments=None)
      "text" => @nbformat.Raw(source~, attachments=None)
      _ => @nbformat.Code(source~, execution_count=None, outputs=[])
    }
    cells.push(@nbformat.Cell::Cell(content, id=Some(@nbformat.CellId("file-\{index}")), metadata~))
  }
  @nbformat.Notebook::Notebook(ReadOnlyArray::from_array(cells[:]), metadata~)
}

///|
/// Write a fresh notebook representing a tree. This does not reproduce the
/// unrelated metadata, notes or execution state of an original notebook.
pub fn Format::write(self : Format, tree : @files.FileTree) -> String raise {
  self.to_notebook(tree).to_string()
}

///|
pub impl @files.TreeFormat for Format with fn read(self, text) { self.read(text) }

///|
pub impl @files.TreeFormat for Format with fn write(self, tree) { self.write(tree) }

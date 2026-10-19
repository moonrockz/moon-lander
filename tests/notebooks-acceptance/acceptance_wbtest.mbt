///|
enum Input {
  Dib(String)
  Jupyter(String)
}

///|
enum Parsed {
  Dib(@dib.Notebook)
  Jupyter(@nbformat.Notebook)
}

///|
enum State {
  Empty
  Source(Input)
  Ready(Parsed)
}

///|
struct NotebookWorld {
  mut state : State
}

///|
fn NotebookWorld::NotebookWorld() -> NotebookWorld {
  { state: Empty, }
}

///|
fn NotebookWorld::parsed(self : NotebookWorld) -> Parsed raise {
  guard self.state is Ready(book) else { fail("parse a notebook first") }
  book
}

///|
fn NotebookWorld::dib(self : NotebookWorld) -> @dib.Notebook raise {
  guard self.parsed() is Dib(book) else { fail("expected DIB") }
  book
}

///|
fn[N : @notebooks.Node] kinds(root : N) -> String {
  let kinds = []
  @notebooks.walk(root, node => {
    if node.kind() is Cell(kind) {
      kinds.push(
        match kind {
          Code => "code"
          Markdown => "markdown"
          Raw => "raw"
          Unknown(name) => name
        },
      )
    }
    Continue
  })
  kinds.join(",")
}

///|
fn[N : @notebooks.Node + Eq] paths_resolve(root : N) -> Bool {
  let mut valid = true
  @notebooks.walk_cursor(root, cursor => {
    valid = valid && @notebooks.at(root, cursor.path()) == Some(cursor.node())
    Continue
  })
  valid
}

///|
fn[N : @notebooks.Node] metadata_title(root : N) -> Json? raise @notebooks.MetadataError {
  match root.metadata() {
    Some(metadata) => metadata.get_json("title")
    None => None
  }
}

///|
impl @moonspec.World for NotebookWorld with fn configure(self, setup) {
  setup.given1("the DIB source:", (source : @moonspec.DocString) => {
    self.state = Source(Dib(source.content))
  })
  setup.given1("the Jupyter JSON:", (source : @moonspec.DocString) => {
    self.state = Source(Jupyter(source.content))
  })
  setup.when0("the notebook is parsed", () => {
    guard self.state is Source(input) else { fail("expected source") }
    self.state = Ready(
      match input {
        Dib(source) => Dib(@dib.parse(source))
        Jupyter(source) => Jupyter(@nbformat.parse(source))
      },
    )
  })
  setup.then1("the common notebook metadata title is {string}", (
    expected : String,
  ) => {
    let title = match self.parsed() {
      Dib(book) => metadata_title(book.root())
      Jupyter(book) => metadata_title(book.root())
    }
    @expect.expect(title).to_equal(Some(Json(expected)))
  })
  setup.then2("the metadata field {string} has Ion type {string}", (
    key : String,
    expected : String,
  ) => {
    let metadata = match self.parsed() {
      Dib(book) => book.metadata()
      Jupyter(book) => book.metadata()
    }
    guard metadata.get(key) is Some(value) else { fail("missing metadata field") }
    @expect.expect(value.ion_type().to_text()).to_equal(expected)
  })
  setup.then1("the common cell kinds are {string}", (expected : String) => {
    let actual = match self.parsed() {
      Dib(book) => kinds(book.root())
      Jupyter(book) => kinds(book.root())
    }
    @expect.expect(actual).to_equal(expected)
  })
  setup.then0("common cursor paths resolve to their concrete nodes", () => {
    let valid = match self.parsed() {
      Dib(book) => paths_resolve(book.root())
      Jupyter(book) => paths_resolve(book.root())
    }
    @expect.expect(valid).to_be_true()
  })
  setup.then2("the specialized directive is {string} with arguments {string}", (
    name : String,
    arguments : String,
  ) => {
    let book = self.dib()
    guard book.cursor().first_child() is Some(first) else {
      fail("no first cell")
    }
    guard first.next_sibling() is Some(code) else { fail("no code cell") }
    guard code.first_child() is Some(directive_cursor) else {
      fail("no directive")
    }
    guard directive_cursor.node() is Directive(directive) else {
      fail("wrong specialized node")
    }
    @expect.expect_all(s => {
      s.expect(directive.name()).to_equal(name)
      s.expect(directive.arguments()).to_equal(arguments)
      s
      .expect(directive_cursor.parent().map(parent => parent.path()))
      .to_equal(Some(code.path()))
    })
  })
  setup.then1("the custom kernel alias finds source {string}", (
    expected : String,
  ) => {
    let cells = self.dib().cells_for_kernel("alt")
    guard cells.get(0) is Some(cell) else { fail("no custom cell") }
    @expect.expect(cell.source()).to_equal(expected)
  })
  setup.then0("the DIB source round-trips", () => {
    let book = self.dib()
    @expect.expect(@dib.parse(book.to_string())).to_equal(book)
  })
  setup.then0(
    "specialized Jupyter navigation finds the stream and attachment",
    () => {
      guard self.parsed() is Jupyter(book) else { fail("expected Jupyter") }
      let seen = []
      @notebooks.walk(book.root(), node => {
        match node {
          Output(output) =>
            if output.content() is Stream(text~, ..) {
              seen.push(text)
            }
          Attachment(name~, ..) => seen.push(name)
          _ => ()
        }
        Continue
      })
      @expect.expect(seen).to_equal(["plot.png", "2"])
    },
  )
  setup.then1("the first DIB cell has {int} directives", (expected : Int32) => {
    @expect.expect(self.dib().cells()[0].directives().length()).to_equal(
      expected,
    )
  })
}

///|
async test "shared notebook acceptance scenarios" {
  @moonspec.run_or_fail(
    () => NotebookWorld::NotebookWorld(),
    @moonspec.RunOptions::RunOptions([
      @moonspec.FeatureSource::File(
        "notebooks-acceptance/features/notebooks.feature",
      ),
    ]),
  )
}

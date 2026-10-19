///|
enum State {
  Empty
  Source(String)
  Read(@nbformat.Notebook)
  Rejected(@nbformat.FormatError)
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
fn NotebookWorld::notebook(self : NotebookWorld) -> @nbformat.Notebook raise {
  guard self.state is Read(book) else { fail("expected a notebook") }
  book
}

///|
impl @moonspec.World for NotebookWorld with fn configure(self, setup) {
  setup.given1("the notebook JSON:", (source : @moonspec.DocString) => {
    self.state = Source(source.content)
  })
  setup.when0("the notebook is read", () => {
    guard self.state is Source(source) else { fail("expected JSON source") }
    self.state = Read(@nbformat.parse(source)) catch {
      error => Rejected(error)
    }
  })
  setup.then1("the cell types are {string}", (expected : String) => {
    @expect.expect(
      self.notebook().cells().map(cell => cell.cell_type()).join(","),
    ).to_equal(expected)
  })
  setup.then2("the cells containing MIME type {string} have IDs {string}", (
    mime_type : String,
    expected : String,
  ) => {
    @expect.expect(
      self.notebook().cells_by_mime_type(mime_type)
      .map(cell => cell.id().map(id => id.to_string()).unwrap_or(""))
      .join(","),
    ).to_equal(expected)
  })
  setup.then1("the first cell source is {string}", (expected : String) => {
    @expect.expect(self.notebook().cells()[0].source()).to_equal(
      Some(expected.replace(old="\\n", new="\n")),
    )
  })
  setup.then1("the attachment contains {string}", (expected : String) => {
    guard self.notebook().cells()[0].content()
      is Markdown(attachments=Some(attachments), ..) else {
      fail("no attachments")
    }
    guard attachments.get("plot.png") is Some(bundle) else { fail("no plot") }
    @expect.expect(bundle.get("image/png")).to_equal(Some(Json(expected)))
  })
  setup.then1("the code outputs are {string}", (expected : String) => {
    @expect.expect(
      self.notebook().cells()[1]
      .outputs()
      .map(output => output.output_type())
      .join(","),
    ).to_equal(expected)
  })
  setup.then0("cursor paths resolve to the visited nodes", () => {
    let root = self.notebook().root()
    let positions = []
    @nbformat.walk_cursor(root, cursor => {
      positions.push(cursor)
      Continue
    })
    @expect.expect_all(s => {
      for cursor in positions {
        s.expect(root.at(cursor.path())).to_equal(Some(cursor.node()))
        s.expect(cursor.depth()).to_equal(cursor.path().indices().length())
      }
    })
  })
  setup.then0("writing and reading preserves the notebook", () => {
    let book = self.notebook()
    @expect.expect(@nbformat.parse(book.to_string())).to_equal(book)
  })
  setup.then0("future payloads are retained", () => {
    let book = self.notebook()
    guard book.cells()[0].content() is Unknown(fields=cell_fields, ..) else {
      fail("no unknown cell")
    }
    guard book.cells()[1].outputs()[0].content()
      is Unknown(fields=output_fields, ..) else {
      fail("no unknown output")
    }
    @expect.expect_all(s => {
      s
      .expect(book.extensions().get("extension"))
      .to_equal(Some({ "payload": [1, 2] }))
      s
      .expect(cell_fields.get("diagram"))
      .to_equal(Some({ "nodes": ["a", "b"] }))
      s.expect(output_fields.get("state")).to_equal(Some({ "values": [1, 2] }))
    })
  })
  setup.then1("the invalid field is {string}", (expected : String) => {
    guard self.state is Rejected(InvalidField(path~, ..)) else {
      fail("no field error")
    }
    @expect.expect(path).to_equal(expected)
  })
  setup.then1("the duplicate cell ID is {string}", (expected : String) => {
    guard self.state is Rejected(DuplicateCellId(id)) else {
      fail("no duplicate error")
    }
    @expect.expect(id).to_equal(expected)
  })
}

///|
async test "notebook acceptance scenarios" {
  @moonspec.run_or_fail(
    () => NotebookWorld::NotebookWorld(),
    @moonspec.RunOptions::RunOptions([
      @moonspec.FeatureSource::File(
        "nbformat-acceptance/features/nbformat.feature",
      ),
    ]),
  )
}

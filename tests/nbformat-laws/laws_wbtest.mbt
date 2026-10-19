///|
/// Shrink generation choices, then rebuild validated cells with unique IDs.
priv struct NotebookCase {
  choices : ReadOnlyArray[UInt32]
  style : UInt32
} derive(Debug)

///|
impl @quickcheck.Arbitrary for NotebookCase with fn arbitrary(size, state) {
  let (choices, style) : (ReadOnlyArray[UInt32], UInt32) = @quickcheck.Arbitrary::arbitrary(
    size, state,
  )
  { choices, style, }
}

///|
impl @shrink.Shrink for NotebookCase with fn shrink(self) {
  @shrink.Shrink::shrink((self.choices, self.style)).map(parts => {
    let (choices, style) = parts
    { choices, style, }
  })
}

///|
fn NotebookCase::notebook(self : NotebookCase) -> @nbformat.Notebook raise {
  let cells = []
  let metadata = @nbformat.Metadata({
    "custom": { "values": ["🌙", "Café", "目標"] },
  })
  let bundle = @nbformat.MimeBundle({
    "text/plain": ["a\n", "b"],
    "application/json": [1, 2],
  })
  for i, choice in self.choices {
    let source = "🌙 cell \{i}\n\{choice}"
    let id = Some(@nbformat.CellId("cell-\{i}"))
    let content = match choice % 4 {
      0 =>
        @nbformat.CellContent::Markdown(
          source~,
          attachments=Some(
            @nbformat.Attachments({
              "z": bundle.to_json(),
              "a": bundle.to_json(),
            }),
          ),
        )
      1 => @nbformat.CellContent::Raw(source~, attachments=None)
      2 => {
        let count = Some(
          @nbformat.ExecutionCount((choice % 1000).reinterpret_as_int()),
        )
        let outputs = [
          @nbformat.Output::Output(@nbformat.Stream(name="stdout", text=source)),
          @nbformat.Output::Output(
            @nbformat.DisplayData(data=bundle, metadata~),
          ),
          @nbformat.Output::Output(
            @nbformat.ExecuteResult(
              data=bundle,
              metadata~,
              execution_count=count,
            ),
          ),
          @nbformat.Output::Output(
            @nbformat.OutputContent::Error(ename="Error", evalue=source, traceback=[
              source,
            ]),
          ),
          @nbformat.Output::Output(
            @nbformat.OutputContent::Unknown(
              output_type="future",
              fields=@nbformat.JsonObject(metadata.to_json()),
            ),
          ),
        ]
        @nbformat.CellContent::Code(
          source~,
          execution_count=count,
          outputs=ReadOnlyArray::from_array(outputs[:]),
        )
      }
      _ =>
        @nbformat.CellContent::Unknown(
          cell_type="future",
          fields=@nbformat.JsonObject(metadata.to_json()),
        )
    }
    cells.push(@nbformat.Cell::Cell(content, id~, metadata~))
  }
  @nbformat.Notebook::Notebook(
    ReadOnlyArray::from_array(cells[:]),
    minor=(self.style % 10).reinterpret_as_int(),
    metadata~,
  )
}

///|
test "law: notebook JSON and text codecs round-trip domain values" {
  @expect.for_all(
    (input : NotebookCase) => {
      let book = input.notebook()
      let rendered = book.to_string()
      @expect.expect_all(s => {
        s.expect(@nbformat.parse(rendered)).to_equal(book)
        s.expect(@nbformat.Notebook::from_json(book.to_json())).to_equal(book)
        s.expect(@nbformat.parse(rendered).to_string()).to_equal(rendered)
      })
    },
    count=200,
    max_size=16,
    max_shrinks=200,
    seed=3101,
  )
}

///|
fn recursive_nodes(root : @nbformat.Node) -> ReadOnlyArray[@nbformat.Node] {
  let nodes = [root]
  for child in root.children() {
    nodes.append(recursive_nodes(child)[:])
  }
  ReadOnlyArray::from_array(nodes[:])
}

///|
test "law: walk and fold agree with recursive document order" {
  @expect.for_all(
    (input : NotebookCase) => {
      let book = input.notebook()
      let expected = recursive_nodes(book.root())
      let walked = []
      @nbformat.walk(book.root(), node => {
        walked.push(node)
        Continue
      })
      let empty : ReadOnlyArray[@nbformat.Node] = []
      let folded = book.fold(empty, (nodes, cursor) => {
        ReadOnlyArray::from_iter(nodes.iter().concat([cursor.node()].iter()))
      })
      @expect.expect_all(s => {
        s.expect(ReadOnlyArray::from_array(walked[:])).to_equal(expected)
        s.expect(folded).to_equal(expected)
        s.expect(book.fold(7, (acc, _) => acc)).to_equal(7)
      })
    },
    count=200,
    max_size=16,
    max_shrinks=200,
    seed=3102,
  )
}

///|
test "law: cursor moves are reversible and saved paths resolve" {
  @expect.for_all(
    (input : NotebookCase) => {
      let root = input.notebook().root()
      let positions = []
      @nbformat.walk_cursor(root, cursor => {
        positions.push(cursor)
        Continue
      })
      @expect.expect_all(s => {
        for cursor in positions {
          let original = cursor.path()
          s.expect(root.at(original)).to_equal(Some(cursor.node()))
          s.expect(cursor.depth()).to_equal(original.indices().length())
          if cursor.first_child() is Some(child) {
            s
            .expect(child.parent().map(parent => parent.path()))
            .to_equal(Some(original))
          }
          if cursor.next_sibling() is Some(next) {
            s
            .expect(next.previous_sibling().map(previous => previous.path()))
            .to_equal(Some(original))
          }
          if cursor.previous_sibling() is Some(previous) {
            s
            .expect(previous.next_sibling().map(next => next.path()))
            .to_equal(Some(original))
          }
          s.expect(cursor.path()).to_equal(original)
        }
        s.expect(root.at(@nbformat.NodePath([-1]))).to_equal(None)
      })
    },
    count=200,
    max_size=16,
    max_shrinks=200,
    seed=3103,
  )
}

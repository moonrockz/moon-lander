# Jupyter notebook examples

These examples import `moonrockz/notebooks/nbformat` as `@nbformat` and
`moonrockz/expect` as `@expect`. MoonBit runs each `mbt check` block as a
documentation test.

## Read and write a notebook

The file format version is 4.5, including notebooks created by the upstream
`nbformat` 5.11 Python library.

```mbt check
///|
test "example: read and write Jupyter JSON" {
  let source =
    #|{"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[{"id":"intro","cell_type":"markdown","metadata":{},"source":["# Results\n","Hello"]}]}
  let book = @nbformat.parse(source)
  @expect.expect_all(s => {
    s.expect(book.nbformat()).to_equal(4)
    s.expect(book.nbformat_minor()).to_equal(5)
    s.expect(book.cells()[0].source()).to_equal(Some("# Results\nHello"))
    s.expect(@nbformat.parse(book.to_string())).to_equal(book)
  })
}
```

## Construct cells and all four output types

Use validated IDs for v4.5 notebooks. Rich output data is a MIME bundle;
`application/json` and `+json` payloads retain their JSON types. Other MIME
values normalize to strings. `None` represents a null execution count.

```mbt check
///|
test "example: construct cells and stored outputs" {
  let metadata = @nbformat.Metadata({ "isolated": false })
  let data = @nbformat.MimeBundle({
    "text/plain": ["answer: ", "42"],
    "application/json": { "answer": 42 },
    "application/vnd.example+json": [1, 2],
  })
  let count = Some(@nbformat.ExecutionCount(1))
  let outputs : ReadOnlyArray[@nbformat.Output] = [
    @nbformat.Output::Output(@nbformat.Stream(name="stdout", text="running\n")),
    @nbformat.Output::Output(@nbformat.DisplayData(data~, metadata~)),
    @nbformat.Output::Output(
      @nbformat.ExecuteResult(data~, metadata~, execution_count=count),
    ),
    @nbformat.Output::Output(
      @nbformat.OutputContent::Error(
        ename="ValueError",
        evalue="example failure",
        traceback=["frame 1", "frame 2"],
      ),
    ),
  ]
  let cells : ReadOnlyArray[@nbformat.Cell] = [
    @nbformat.Cell::Cell(
      @nbformat.Markdown(source="# Results", attachments=None),
      id=Some(@nbformat.CellId("intro")),
    ),
    @nbformat.Cell::Cell(
      @nbformat.Code(source="answer = 42", execution_count=count, outputs~),
      id=Some(@nbformat.CellId("calculate")),
    ),
    @nbformat.Cell::Cell(
      @nbformat.Raw(source="\\alpha", attachments=None),
      id=Some(@nbformat.CellId("latex")),
      metadata=@nbformat.Metadata({ "format": "text/latex" }),
    ),
  ]
  let book = @nbformat.Notebook::Notebook(cells)
  @expect.expect_all(s => {
    s
    .expect(book.cells().map(cell => cell.cell_type()))
    .to_equal(["markdown", "code", "raw"])
    s
    .expect(book.cells()[1].outputs().map(output => output.output_type()))
    .to_equal(["stream", "display_data", "execute_result", "error"])
    s.expect(data.get("text/plain")).to_equal(Some("answer: 42"))
    s.expect(data.get("application/json")).to_equal(Some({ "answer": 42 }))
    s.expect(data.get("application/vnd.example+json")).to_equal(Some([1, 2]))
    s.expect(book.cells_by_mime_type("application/json")).to_equal([cells[1]])
    s.expect(@nbformat.parse(book.to_string())).to_equal(book)
  })
}
```

`CellContent` and `OutputContent` can be pattern matched to access all the
typed fields. Stream names are strings, so custom stream names remain valid.
Use `ExecutionCount::from_json` when a numeric JSON count exceeds `Int32`.

## Attach images and inspect metadata safely

Attachments are filename-keyed MIME bundles. An absent attachment field and
an explicitly empty attachment object remain distinct. JSON imports and
exports make defensive copies, including nested metadata.

```mbt check
///|
test "example: attachments and independent metadata exports" {
  let attachments = @nbformat.Attachments({
    "plot.png": { "image/png": ["YW", "Jj"] },
    "data.json": { "application/json": [1, 2] },
  })
  let metadata = @nbformat.Metadata({ "vendor": { "tags": ["example"] } })
  let cell = @nbformat.Cell::Cell(
    @nbformat.Markdown(
      source="![plot](attachment:plot.png)",
      attachments=Some(attachments),
    ),
    id=Some(@nbformat.CellId("plot")),
    metadata~,
  )
  guard attachments.get("plot.png") is Some(image) else {
    fail("missing image")
  }
  guard metadata.get_json("vendor") is Some(Object(vendor)) else {
    fail("missing namespace")
  }
  guard vendor.get("tags") is Some(Array(tags)) else { fail("missing tags") }
  tags.clear()
  @expect.expect_all(s => {
    s.expect(attachments.names()).to_equal(["data.json", "plot.png"])
    s.expect(image.get("image/png")).to_equal(Some("YWJj"))
    s.expect(attachments.get("missing.png")).to_equal(None)
    s
    .expect(cell.metadata().get_json("vendor"))
    .to_equal(Some({ "tags": ["example"] }))
    s
    .expect(attachments.to_json())
    .to_equal({
      "plot.png": { "image/png": "YWJj" },
      "data.json": { "application/json": [1, 2] },
    })
  })
}
```

The library validates bundle structure and textual data, but does not decode
base64 or inspect image contents.

## Find cells and navigate their concrete output nodes

Indices are zero-based. ID lookup returns `None` if the ID is absent. A saved
cursor keeps its ancestors and path, while constructing a cursor from its
node establishes a new root.

```mbt check
///|
test "example: ID lookup and specialized output navigation" {
  let book = @nbformat.parse(
    "{\"nbformat\":4,\"nbformat_minor\":5,\"metadata\":{},\"cells\":[{\"id\":\"calculate\",\"cell_type\":\"code\",\"metadata\":{},\"source\":\"print(42)\",\"execution_count\":1,\"outputs\":[{\"output_type\":\"stream\",\"name\":\"stdout\",\"text\":\"42\\n\"}]}]}",
  )
  guard book.cell_by_id(@nbformat.CellId("calculate")) is Some(cell) else {
    fail("missing cell")
  }
  guard book.cursor().first_child() is Some(cell_cursor) else {
    fail("missing position")
  }
  guard cell_cursor.first_child() is Some(output_cursor) else {
    fail("missing output")
  }
  guard output_cursor.node() is Output(output) else {
    fail("expected output node")
  }
  guard output.content() is Stream(name~, text~) else {
    fail("expected stream")
  }
  @expect.expect_all(s => {
    s.expect(cell.source()).to_equal(Some("print(42)"))
    s.expect((name, text)).to_equal(("stdout", "42\n"))
    s.expect(output_cursor.path().to_string()).to_equal("$[0][0]")
    s
    .expect(book.root().at(output_cursor.path()))
    .to_equal(Some(output_cursor.node()))
    s
    .expect(output_cursor.parent().map(parent => parent.path()))
    .to_equal(Some(cell_cursor.path()))
    s.expect(book.cell(-1)).to_equal(None)
    s.expect(book.cell_by_id(@nbformat.CellId("missing"))).to_equal(None)
  })
}
```

`Node::Attachment(name~, data~)` provides the filename and MIME bundle during
a specialized walk. Metadata and individual MIME representations are queried
through their accessors rather than traversed as children.

## Handle syntax and validation errors

Catch `FormatError` at an input boundary. A missing or invalid field reports
a logical JSON path; duplicate IDs and names have distinct variants. An
upstream Python package release number does not belong in `nbformat`.

```mbt check
///|
test "example: typed input errors" {
  let malformed : @nbformat.FormatError? = try {
    ignore(@nbformat.parse("not JSON"))
    None
  } catch {
    error => Some(error)
  }
  let missing_id : @nbformat.FormatError? = try {
    ignore(
      @nbformat.Notebook::from_json({
        "nbformat": 4,
        "nbformat_minor": 5,
        "metadata": {},
        "cells": [{ "cell_type": "raw", "metadata": {}, "source": "" }],
      }),
    )
    None
  } catch {
    error => Some(error)
  }
  let unsupported : @nbformat.FormatError? = try {
    ignore(
      @nbformat.Notebook::from_json({ "nbformat": 5, "nbformat_minor": 11 }),
    )
    None
  } catch {
    error => Some(error)
  }
  @expect.expect_all(s => {
    s.expect(malformed is Some(InvalidJson(_))).to_be_true()
    s
    .expect(missing_id is Some(InvalidField(path="$.cells[0].id", ..)))
    .to_be_true()
    s
    .expect(unsupported)
    .to_equal(Some(@nbformat.UnsupportedVersion(major=5, minor=11)))
  })
}
```

## Read older versions and preserve future payloads

Older v4 files can omit IDs. Future v4 minor versions keep their version
number and retain unknown fields and types. Unknown payloads remain leaves
during traversal; they are never treated as executable code by this library.

```mbt check
///|
test "example: older cells and future extension payloads" {
  let older = @nbformat.Notebook::Notebook(
    [
      @nbformat.Cell::Cell(
        @nbformat.Raw(source="older source", attachments=None),
      ),
    ],
    minor=4,
  )
  let future = @nbformat.Notebook::from_json({
    "nbformat": 4,
    "nbformat_minor": 9,
    "metadata": {},
    "vendor": { "revision": 1 },
    "cells": [
      {
        "id": "diagram",
        "cell_type": "diagram",
        "metadata": {},
        "nodes": ["a", "b"],
      },
    ],
  })
  guard future.cells()[0].content() is Unknown(cell_type~, fields~) else {
    fail("expected future cell")
  }
  @expect.expect_all(s => {
    s.expect(older.cells()[0].id()).to_equal(None)
    s.expect(@nbformat.parse(older.to_string())).to_equal(older)
    s.expect(cell_type).to_equal("diagram")
    s.expect(fields.get("nodes")).to_equal(Some(["a", "b"]))
    s
    .expect(future.extensions().get("vendor"))
    .to_equal(Some({ "revision": 1 }))
    s.expect(future.root().children()[0].children().is_empty()).to_be_true()
    s.expect(@nbformat.parse(future.to_string())).to_equal(future)
  })
}
```

To construct an unknown cell, use `CellContent::Unknown` with a `JsonObject`
payload that excludes `cell_type`, `id` and `metadata`; supply those common
fields through the `Cell` constructor. Unknown outputs similarly exclude
`output_type` from their payload. Recognized values' extra fields are available
through `extensions()`.

## Edit an exported copy and validate the result

For edits that must preserve arbitrary extension fields, change an independent
JSON export and import it again. Reconstructing only the known fields would
discard any extensions omitted by that reconstruction.

```mbt check
///|
test "example: edit an exported copy without changing the original" {
  let original = @nbformat.Notebook::from_json({
    "nbformat": 4,
    "nbformat_minor": 5,
    "metadata": {},
    "vendor": { "keep": true },
    "cells": [
      {
        "id": "intro",
        "cell_type": "markdown",
        "metadata": {},
        "source": "old",
        "vendor_cell": [1],
      },
    ],
  })
  let exported = original.to_json()
  guard exported is Object(fields) else { fail("expected notebook object") }
  guard fields.get("cells") is Some(Array(cells)) else {
    fail("expected cells")
  }
  guard cells[0] is Object(cell_fields) else { fail("expected cell object") }
  cell_fields["source"] = "updated"
  let edited = @nbformat.Notebook::from_json(exported)
  @expect.expect_all(s => {
    s.expect(original.cells()[0].source()).to_equal(Some("old"))
    s.expect(edited.cells()[0].source()).to_equal(Some("updated"))
    s.expect(edited.extensions()).to_equal(original.extensions())
    s
    .expect(edited.cells()[0].extensions())
    .to_equal(original.cells()[0].extensions())
  })
}
```

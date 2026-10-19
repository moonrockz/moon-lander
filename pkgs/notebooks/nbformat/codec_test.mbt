///|
fn sample() -> @nbformat.Notebook raise {
  let source =
    #|{"nbformat":4,"nbformat_minor":5,"metadata":{"custom":{"items":[1,2]}},"future":{"x":[1]},"cells":[
    #|{"id":"md-1","cell_type":"markdown","metadata":{},"source":["# Hello\n","🌙"],"attachments":{"z.png":{"image/png":["a","b"]},"a.json":{"application/json":[1,2]}}},
    #|{"id":"code_2","cell_type":"code","metadata":{"scrolled":"auto"},"source":"print(1)","execution_count":1,"future_cell":[3],"outputs":[
    #|{"output_type":"stream","name":"stdout","text":["one\n","two"]},
    #|{"output_type":"display_data","data":{"text/plain":["a","b"],"application/vnd.test+json":["a","b"]},"metadata":{}},
    #|{"output_type":"execute_result","data":{"application/json":{"ok":true}},"metadata":{},"execution_count":null},
    #|{"output_type":"error","ename":"Error","evalue":"failed","traceback":["frame 1","frame 2"]},
    #|{"output_type":"future","payload":[{"ok":true}]}]},
    #|{"id":"raw","cell_type":"raw","metadata":{"format":"text/latex"},"source":"raw"},
    #|{"id":"future","cell_type":"future","metadata":{},"payload":[1,2]}]}
  @nbformat.parse(source)
}

///|
test "all cell and output types normalize text and preserve arbitrary JSON" {
  let book = sample()
  let cells = book.cells()
  @expect.expect_all(s => {
    s.expect(cells.length()).to_equal(4)
    s.expect(cells[0].source()).to_equal(Some("# Hello\n🌙"))
    s.expect(cells[1].outputs().length()).to_equal(5)
    s.expect(cells[2].cell_type()).to_equal("raw")
    s.expect(cells[3].source()).to_equal(None)
    s.expect(book.cell(-1)).to_equal(None)
    s.expect(book.cell(4)).to_equal(None)
    s
    .expect(book.cell_by_id(@nbformat.CellId("code_2")))
    .to_equal(Some(cells[1]))
    s.expect(book.extensions().get("future")).to_equal(Some({ "x": [1] }))
    s.expect(cells[1].extensions().get("future_cell")).to_equal(Some([3]))
    s.expect(@nbformat.parse(book.to_string())).to_equal(book)
  })
  guard cells[0].content() is Markdown(attachments=Some(attachments), ..) else {
    fail("attachments missing")
  }
  guard attachments.get("z.png") is Some(image) else { fail("image missing") }
  guard cells[1].outputs()[1].content() is DisplayData(data~, ..) else {
    fail("display missing")
  }
  @expect.expect_all(s => {
    s.expect(image.get("image/png")).to_equal(Some("ab"))
    s.expect(data.get("text/plain")).to_equal(Some("ab"))
    s.expect(data.get("application/vnd.test+json")).to_equal(Some(["a", "b"]))
    s.expect(attachments.names()).to_equal(["a.json", "z.png"])
  })
}

///|
fn error_for(value : Json) -> @nbformat.FormatError? {
  try {
    ignore(@nbformat.Notebook::from_json(value))
    None
  } catch {
    error => Some(error)
  }
}

///|
fn notebook_with(cell : Json, minor~ : Int32 = 5) -> Json {
  {
    "nbformat": 4,
    "nbformat_minor": Json(minor),
    "metadata": {},
    "cells": [cell],
  }
}

///|
test "versioned required fields and exact failure paths" {
  let old : Json = { "cell_type": "markdown", "metadata": {}, "source": [] }
  let code : Json = {
    "id": "code",
    "cell_type": "code",
    "metadata": {},
    "source": "",
    "execution_count": null,
    "outputs": [],
  }
  @expect.expect_all(s => {
    for minor in [0, 1, 2, 3, 4] {
      s.expect(error_for(notebook_with(old, minor~))).to_equal(None)
    }
    s
    .expect(error_for(notebook_with(old)))
    .to_equal(
      Some(
        @nbformat.InvalidField(
          path="$.cells[0].id",
          expected="required cell ID in nbformat 4.5 and later",
        ),
      ),
    )
    s.expect(error_for(notebook_with(code))).to_equal(None)
    s
    .expect(error_for({ "nbformat": 3, "nbformat_minor": 0 }))
    .to_equal(Some(@nbformat.UnsupportedVersion(major=3, minor=0)))
    s
    .expect(error_for({ "nbformat": 4, "nbformat_minor": -1 }))
    .to_equal(
      Some(
        @nbformat.InvalidField(
          path="$.nbformat_minor",
          expected="nonnegative 32-bit integer",
        ),
      ),
    )
  })
}

///|
test "malformed cell IDs counts outputs attachments and metadata are rejected" {
  let malformed : Array[Json] = [
    { "id": "", "cell_type": "raw", "metadata": {}, "source": "" },
    { "id": "🌙", "cell_type": "raw", "metadata": {}, "source": "" },
    { "id": "a b", "cell_type": "raw", "metadata": {}, "source": "" },
    { "id": "a", "cell_type": "raw", "metadata": {}, "source": [1] },
    {
      "id": "a",
      "cell_type": "markdown",
      "metadata": {},
      "source": "",
      "attachments": { "a": { "image/png": 1 } },
    },
    {
      "id": "a",
      "cell_type": "code",
      "metadata": {},
      "source": "",
      "outputs": [],
    },
    {
      "id": "a",
      "cell_type": "code",
      "metadata": {},
      "source": "",
      "execution_count": -1,
      "outputs": [],
    },
    {
      "id": "a",
      "cell_type": "code",
      "metadata": {},
      "source": "",
      "execution_count": 1.5,
      "outputs": [],
    },
    {
      "id": "a",
      "cell_type": "code",
      "metadata": {},
      "source": "",
      "execution_count": null,
      "outputs": [{ "output_type": "stream", "name": "stdout" }],
    },
    {
      "id": "a",
      "cell_type": "code",
      "metadata": {},
      "source": "",
      "execution_count": null,
      "outputs": [
        {
          "output_type": "error",
          "ename": "e",
          "evalue": "v",
          "traceback": [1],
        },
      ],
    },
    {
      "id": "a",
      "cell_type": "raw",
      "metadata": { "tags": ["a", "a"] },
      "source": "",
    },
    {
      "id": "a",
      "cell_type": "raw",
      "metadata": { "tags": ["a,b"] },
      "source": "",
    },
    {
      "id": "a",
      "cell_type": "code",
      "metadata": { "scrolled": "yes" },
      "source": "",
      "execution_count": null,
      "outputs": [],
    },
  ]
  @expect.expect_all(s => {
    for cell in malformed {
      s.expect(error_for(notebook_with(cell)) is Some(_)).to_be_true()
    }
    s
    .expect(
      error_for({
        "nbformat": 4,
        "nbformat_minor": 5,
        "metadata": { "kernelspec": { "name": "python" } },
        "cells": [],
      })
      is Some(_),
    )
    .to_be_true()
  })
}

///|
test "IDs must be unique and constructing notebook values enforces invariants" {
  let id = @nbformat.CellId("a")
  let cell = @nbformat.Cell::Cell(
    @nbformat.Markdown(source="", attachments=None),
    id=Some(id),
  )
  let duplicate : @nbformat.FormatError? = try {
    ignore(@nbformat.Notebook::Notebook([cell, cell]))
    None
  } catch {
    error => Some(error)
  }
  let missing : @nbformat.FormatError? = try {
    ignore(
      @nbformat.Notebook::Notebook([
        @nbformat.Cell::Cell(@nbformat.Raw(source="", attachments=None)),
      ]),
    )
    None
  } catch {
    error => Some(error)
  }
  @expect.expect_all(s => {
    s.expect(duplicate).to_equal(Some(@nbformat.DuplicateCellId("a")))
    s.expect(missing is Some(_)).to_be_true()
  })
}

///|
test "imports and exports cannot mutate notebook metadata or extension graphs" {
  let input = @json.parse(sample().to_string())
  let book = @nbformat.Notebook::from_json(input)
  let original = book.to_string()
  guard input is Object(fields) else { fail("object expected") }
  fields.clear()
  let exported = book.to_json()
  guard exported is Object(fields) else { fail("object expected") }
  fields.clear()
  guard book.metadata().get_json("custom") is Some(Object(custom)) else {
    fail("custom missing")
  }
  guard custom.get("items") is Some(Array(items)) else { fail("items missing") }
  items.clear()
  guard book.cells()[1].outputs()[4].content() is Unknown(fields~, ..) else {
    fail("unknown missing")
  }
  guard fields.to_json() is Object(exported_fields) else {
    fail("fields missing")
  }
  exported_fields.clear()
  @expect.expect(book.to_string()).to_equal(original)
}

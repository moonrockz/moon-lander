///|
test "metadata rejects non-objects and isolates nested JSON aliases" {
  let invalid : Array[Json] = [null, true, 1, "text", []]
  for value in invalid {
    try @notebooks.Metadata(value) catch {
      error => @expect.expect(error).to_equal(@notebooks.ExpectedObject)
    } noraise {
      _ => fail("expected invalid metadata to raise")
    }
  }
  let items = [Json("original")]
  let nested : Map[String, Json] = { "items": Json(items) }
  let fields : Map[String, Json] = { "vendor": Json(nested), "null": null }
  let metadata = @notebooks.Metadata(Json(fields))
  items[0] = Json("input changed")
  nested["extra"] = Json(true)
  fields.clear()
  guard metadata.get_json("vendor") is Some(Object(exported)) else {
    fail("missing vendor metadata")
  }
  guard exported.get("items") is Some(Array(values)) else {
    fail("missing items")
  }
  values[0] = Json("lookup changed")
  guard metadata.to_json() is Object(output) else { fail("expected object") }
  output.clear()
  @expect.expect_all(s => {
    s.expect(metadata.get_json("vendor")).to_equal(Some({ "items": ["original"] }))
    s.expect(metadata.get_json("null")).to_equal(Some(null))
    s.expect(metadata.get_json("missing")).to_equal(None)
    s.expect(metadata.keys().length()).to_equal(2)
    s.expect(metadata.keys().contains("vendor")).to_be_true()
    s.expect(metadata.is_empty()).to_be_false()
    s.expect(@notebooks.Metadata::empty().is_empty()).to_be_true()
  })
}

///|
fn[N : @notebooks.Node] metadata_presence(root : N) -> ReadOnlyArray[Bool?] {
  @notebooks.fold(root, [], (values : ReadOnlyArray[Bool?], cursor) => {
    ReadOnlyArray::from_iter(
      values
      .iter()
      .concat(
        [cursor.node().metadata().map(metadata => metadata.is_empty())].iter(),
      ),
    )
  })
}

///|
test "common metadata describes containers without inheriting attributes" {
  let book = @nbformat.Notebook::from_json({
    "nbformat": 4,
    "nbformat_minor": 5,
    "metadata": { "title": "Root" },
    "cells": [
      {
        "id": "code",
        "cell_type": "code",
        "metadata": {},
        "source": "x",
        "execution_count": null,
        "outputs": [
          { "output_type": "display_data", "metadata": {}, "data": {} },
          {
            "output_type": "execute_result",
            "metadata": { "isolated": true },
            "data": {},
            "execution_count": 1,
          },
          { "output_type": "stream", "name": "stdout", "text": "x" },
          {
            "output_type": "error",
            "ename": "Error",
            "evalue": "x",
            "traceback": [],
          },
          { "output_type": "future", "metadata": { "opaque": true } },
        ],
      },
      {
        "id": "md",
        "cell_type": "markdown",
        "metadata": {},
        "source": "x",
        "attachments": { "x": { "text/plain": "x" } },
      },
      { "id": "raw", "cell_type": "raw", "metadata": {}, "source": "x" },
      { "id": "future", "cell_type": "future", "metadata": {} },
    ],
  })
  let dib = @dib.parse("#!meta\n{\"title\":\"Root\"}\n#!csharp\n#!share x")
  @expect.expect_all(s => {
    s
    .expect(metadata_presence(book.root()))
    .to_equal([
      Some(false),
      Some(true),
      Some(true),
      Some(false),
      None,
      None,
      None,
      Some(true),
      None,
      Some(true),
      Some(true),
    ])
    s.expect(metadata_presence(dib.root())).to_equal([Some(false), None, None])
    s.expect(book.root().metadata()).to_equal(Some(book.metadata()))
    s.expect(dib.root().metadata()).to_equal(Some(dib.metadata()))
    s.expect(book.cells()[0].metadata().get_json("title")).to_equal(None)
  })
  // Both format-specific constructors accept the exact same metadata value.
  let shared = @notebooks.Metadata({ "vendor": { "items": [1, true, null] } })
  let jupyter = @nbformat.Notebook::Notebook([], metadata=shared)
  let interactive = @dib.Notebook::Notebook([], metadata=shared)
  @expect.expect(jupyter.metadata()).to_equal(interactive.metadata())
}

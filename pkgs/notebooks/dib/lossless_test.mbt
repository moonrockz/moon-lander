///|
test "issue 109 public empty Markdown cell round trip" {
  let source_mode = @dib.SourceMode::Lossless
  let registry = @dib.KernelRegistry(
    [
      @dib.KernelInfo(@dib.KernelName("scheme")),
      @dib.KernelInfo(@dib.KernelName("markdown")),
    ],
    default_kernel=@dib.KernelName("scheme"),
  )
  let original = @dib.Notebook::Notebook([
    @dib.Cell::Cell("", kernel=@dib.KernelName("markdown"), source_mode~),
    @dib.Cell::Cell("42", kernel=@dib.KernelName("scheme"), source_mode~),
  ], registry~)
  let encoded = original.to_string(source_mode~)
  let parsed = @dib.parse(encoded, registry~, source_mode~)
  assert_eq(encoded, "#!markdown\n\n#!scheme\n42\n")
  assert_eq(original.cells().length(), 2)
  assert_eq(parsed.cells().length(), 2)
  assert_eq(parsed, original)
}

///|
test "lossless cells retain empty boundary lines across adjacent selectors" {
  let source_mode = @dib.SourceMode::Lossless
  let sources = [
    ("", ""),
    ("\n", "\n"),
    ("\n\n", "\n\n"),
    ("\r\n42\r", "\n42\n"),
    ("\t\n \n", "\t\n \n"),
    ("alpha\n\nbeta", "alpha\n\nbeta"),
  ]
  for (first, expected_first) in sources {
    for (last, expected_last) in sources {
      let original = @dib.Notebook::Notebook([
        @dib.Cell::Cell(first, kernel=@dib.KernelName("md"), source_mode~),
        @dib.Cell::Cell("", kernel=@dib.KernelName("f#"), source_mode~),
        @dib.Cell::Cell(last, kernel=@dib.KernelName("fsharp"), source_mode~),
      ])
      let parsed = @dib.parse(original.to_string(source_mode~), source_mode~)
      assert_eq(parsed, original)
      assert_eq(parsed.cells().length(), 3)
      assert_eq(parsed.cells()[0].source(), expected_first)
      assert_eq(parsed.cells()[2].source(), expected_last)
    }
  }
}

///|
test "lossless empty notebooks and explicit empty selectors differ" {
  let source_mode = @dib.SourceMode::Lossless
  let empty = @dib.Notebook::Notebook([])
  assert_eq(@dib.parse(empty.to_string(source_mode~), source_mode~), empty)
  let selected = @dib.parse("#!fsharp\n#!fsharp\n#!markdown", source_mode~)
  assert_eq(selected.cells().length(), 3)
  assert_eq(@dib.parse(selected.to_string(source_mode~), source_mode~), selected)
  let metadata_only = @dib.Notebook::Notebook(
    [], metadata=@dib.Metadata({ "title": "Empty" }),
  )
  assert_eq(
    @dib.parse(metadata_only.to_string(source_mode~), source_mode~),
    metadata_only,
  )
}

///|
test "lossless metadata and source metadata directives retain cell boundaries" {
  let source_mode = @dib.SourceMode::Lossless
  for metadata in [
    @dib.Metadata::empty(),
    @dib.Metadata({ "title": "Example" }),
  ] {
    let original = @dib.Notebook::Notebook([
      @dib.Cell::Cell("", kernel=@dib.KernelName("markdown"), source_mode~),
      @dib.Cell::Cell(
        "\n#!meta\nretained as source\n#!unknown\n",
        kernel=@dib.KernelName("csharp"), source_mode~,
      ),
      @dib.Cell::Cell("", kernel=@dib.KernelName("csharp"), source_mode~),
    ], metadata~)
    assert_eq(
      @dib.parse(original.to_string(source_mode~), source_mode~),
      original,
    )
  }
}

///|
test "lossless source refuses registered selector collisions at original lines" {
  let source_mode = @dib.SourceMode::Lossless
  let original = @dib.Notebook::Notebook([
    @dib.Cell::Cell("\n#!fsharp\nx\n", kernel=@dib.KernelName("csharp"), source_mode~),
  ])
  try original.to_string(source_mode~) catch {
    @dib.UnrepresentableSource(cell~, line~) => {
      assert_eq(cell, 0)
      assert_eq(line, 2)
    }
    _ => fail("unexpected serialization error")
  } noraise {
    _ => fail("a registered selector must not silently split the cell")
  }
}

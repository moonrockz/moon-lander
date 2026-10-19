///|
test "selectors aliases directives and line normalization follow DIB rules" {
  let source = "\u{FEFF}\r\nvar x = 1;\r\n\r\n#!f#\r\n\r\n#!share --from csharp x\r\nlet y = x\r\n\r\n#!md\r\n# Title\r\n#!csharp\r\n#!connect named-pipe --kernel-name wpf\r\n#!wpf -h\r\n"
  let book = @dib.parse(source)
  let cells = book.cells()
  @expect.expect(cells.length()).to_equal(4)
  @expect.expect_all(s => {
    s
    .expect(cells.map(cell => cell.kernel().to_string()))
    .to_equal(["csharp", "fsharp", "markdown", "csharp"])
    s.expect(cells[0].source()).to_equal("var x = 1;")
    s.expect(cells[1].source()).to_equal("#!share --from csharp x\nlet y = x")
    s
    .expect(cells[3].directives().map(directive => directive.name()))
    .to_equal(["connect", "wpf"])
    s.expect(cells[1].directives()[0].arguments()).to_equal("--from csharp x")
    s.expect(cells[1].directives()[0].line()).to_equal(1)
    s.expect(book.cells_for_kernel("f#")).to_equal([cells[1]])
    s.expect(book.cell(-1)).to_equal(None)
    s.expect(@dib.parse(book.to_string())).to_equal(book)
  })
}

///|
test "empty sections are omitted and whitespace-only source is preserved" {
  let book = @dib.parse("#!fsharp\n\n#!pwsh\nGet-Item\n\n#!fsharp\n")
  let empty = @dib.parse("")
  let blank = @dib.parse("#!csharp\n \n")
  @expect.expect_all(s => {
    s.expect(book.cells().length()).to_equal(1)
    s.expect(book.cells()[0].kernel().to_string()).to_equal("pwsh")
    s.expect(book.to_string()).to_equal("#!pwsh\n\nGet-Item\n")
    s.expect(empty.cells().length()).to_equal(1)
    s.expect(empty.cells()[0].source()).to_equal("")
    s.expect(empty.to_string()).to_equal("")
    s.expect(blank.cells()[0].source()).to_equal(" ")
  })
}

///|
test "metadata registers custom kernels and remains immutable" {
  let source =
    #|#!meta
    #|{"kernelInfo":{"defaultKernelName":"custom","items":[{"name":"custom","aliases":["alt"],"languageName":"Example"}]},"vendor":{"items":[1,2]}}
    #|#!custom
    #|unmarked()
    #|#!alt
    #|custom()
    #|#!markdown
    #|# Title
  let book = @dib.parse(source)
  let exported = book.metadata().to_json()
  guard exported is Object(fields) else { fail("metadata missing") }
  fields.clear()
  guard book.metadata().get_json("vendor") is Some(Object(vendor)) else {
    fail("vendor missing")
  }
  guard vendor.get("items") is Some(Array(items)) else { fail("items missing") }
  items.clear()
  @expect.expect_all(s => {
    s
    .expect(book.cells().map(cell => cell.kernel().to_string()))
    .to_equal(["custom", "custom", "markdown"])
    s.expect(book.metadata().get_json("vendor")).to_equal(Some({ "items": [1, 2] }))
    s.expect(@dib.parse(book.to_string())).to_equal(book)
  })
}

///|
test "invalid metadata and duplicate kernel names report typed errors" {
  let invalid = try {
    ignore(@dib.parse("#!meta\nnot json"))
    None
  } catch {
    error => Some(error)
  }
  let kernel = @dib.KernelName("example")
  let duplicate : @dib.FormatError? = try {
    ignore(
      @dib.KernelRegistry(
        [@dib.KernelInfo(kernel), @dib.KernelInfo(kernel)],
        default_kernel=kernel,
      ),
    )
    None
  } catch {
    error => Some(error)
  }
  @expect.expect_all(s => {
    s.expect(invalid is Some(InvalidMetadata(line=2, ..))).to_be_true()
    s.expect(duplicate).to_equal(Some(@dib.DuplicateKernelName("example")))
  })
}

///|
test "writing refuses source that would silently split into more cells" {
  let cell = @dib.Cell::Cell(
    "before\n#!fsharp\nafter",
    kernel=@dib.KernelName("csharp"),
  )
  let book = @dib.Notebook::Notebook([cell])
  let error : @dib.FormatError? = try {
    ignore(book.to_string())
    None
  } catch {
    error => Some(error)
  }
  @expect.expect(error).to_equal(
    Some(@dib.UnrepresentableSource(cell=0, line=2)),
  )
}

///|
test "metadata-only documents and exact selector matching" {
  let book = @dib.parse("#!meta\n{\n\"title\":\"Notebook\"\n}")
  let exact = @dib.parse("#!fsharp extra\n  #!fsharp\n#!unknown\nx")
  @expect.expect_all(s => {
    s.expect(book.cells().length()).to_equal(1)
    s.expect(book.metadata().get_json("title")).to_equal(Some("Notebook"))
    s.expect(@dib.parse(book.to_string())).to_equal(book)
    s.expect(exact.cells().length()).to_equal(1)
    s
    .expect(exact.cells()[0].source())
    .to_equal("#!fsharp extra\n  #!fsharp\n#!unknown\nx")
  })
}

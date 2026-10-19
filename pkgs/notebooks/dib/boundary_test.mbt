///|
test "an external registry determines defaults and survives contextual round trips" {
  let kernel = @dib.KernelName("custom")
  let registry = @dib.KernelRegistry(
    [@dib.KernelInfo(kernel, aliases=[@dib.KernelName("alt")])],
    default_kernel=@dib.KernelName("alt"),
  )
  let book = @dib.parse("initial()\n#!md\n# Title\n#!alt\nnext()", registry~)
  @expect.expect_all(s => {
    s
    .expect(book.cells().map(cell => cell.kernel().to_string()))
    .to_equal(["custom", "markdown", "custom"])
    s.expect(book.registry().default_kernel().to_string()).to_equal("custom")
    s
    .expect(@dib.parse(book.to_string(), registry=book.registry()))
    .to_equal(book)
  })
}

///|
test "later metadata directives remain source even with an empty document header" {
  let book = @dib.parse("#!meta\n{}\n#!csharp\n#!meta\nkeep this as source")
  let constructed = @dib.Notebook::Notebook([
    @dib.Cell::Cell(
      "#!meta\nliteral directive",
      kernel=@dib.KernelName("csharp"),
    ),
  ])
  @expect.expect_all(s => {
    s.expect(book.cells()[0].source()).to_equal("#!meta\nkeep this as source")
    s.expect(@dib.parse(book.to_string())).to_equal(book)
    s.expect(@dib.parse(constructed.to_string())).to_equal(constructed)
  })
}

///|
test "metadata-only default kernels remain available without a code selector" {
  let source =
    #|#!meta
    #|{"kernelInfo":{"defaultKernelName":"fsharp"}}
  let book = @dib.parse(source)
  @expect.expect_all(s => {
    s.expect(book.cells()[0].kernel().to_string()).to_equal("fsharp")
    s.expect(@dib.parse(book.to_string())).to_equal(book)
  })
}

///|
test "notebook construction canonicalizes aliases and copies metadata imports" {
  let input = Json::object({ "vendor": { "values": [1] } })
  let metadata = @dib.Metadata(input)
  let book = @dib.Notebook::Notebook(
    [@dib.Cell::Cell("# Heading", kernel=@dib.KernelName("md"))],
    metadata~,
  )
  guard input is Object(fields) else { fail("no metadata") }
  fields.clear()
  @expect.expect_all(s => {
    s.expect(book.cells()[0].kernel().to_string()).to_equal("markdown")
    s.expect(book.metadata().get_json("vendor")).to_equal(Some({ "values": [1] }))
    s.expect(@dib.parse(book.to_string())).to_equal(book)
  })
}

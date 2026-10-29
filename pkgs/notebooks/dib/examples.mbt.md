# DIB notebook examples

These examples import `moonrockz/notebooks/dib` as `@dib` and
`moonrockz/expect` as `@expect`. Every `mbt check` block is a documentation
test. Reading and writing never execute cell source or directives.

## Read a polyglot notebook

Exact registered selectors begin cells. Aliases resolve to canonical kernel
names. Other commands remain source, including directives with arguments.

```mbt check
///|
test "example: parse polyglot source and select a kernel" {
  let source =
    #|#!md
    #|# Results
    #|#!c#
    #|#!share --from fsharp x
    #|Console.WriteLine(x);
    #|#!fsharp
    #|let x = 42
  let book = @dib.parse(source)
  @expect.expect_all(s => {
    s
    .expect(book.cells().map(cell => cell.kernel().to_string()))
    .to_equal(["markdown", "csharp", "fsharp"])
    s.expect(book.cells()[0].kind() is Markdown).to_be_true()
    s
    .expect(book.cells_for_kernel("cs")[0].source())
    .to_equal("#!share --from fsharp x\nConsole.WriteLine(x);")
    s.expect(book.cells_for_kernel("unregistered").is_empty()).to_be_true()
    s.expect(@dib.parse(book.to_string())).to_equal(book)
  })
}
```

Selectors must match an entire line at column zero. For example,
`#!fsharp --help` and an indented `#!fsharp` remain source.

## Construct cells and metadata

Cell construction normalizes line endings and trims empty boundary lines.
Notebook construction resolves aliases and validates registry membership.

```mbt check
///|
test "example: construct a DIB notebook" {
  let intro = @dib.Cell::Cell("\r\n# Example\r\n", kernel=@dib.KernelName("md"))
  let code = @dib.Cell::Cell(
    "\nConsole.WriteLine(42);\n",
    kernel=@dib.KernelName("cs"),
  )
  let metadata = @dib.Metadata({
    "title": "Example",
    "vendor": { "tags": ["demo"] },
  })
  let book = @dib.Notebook::Notebook([intro, code], metadata~)
  @expect.expect_all(s => {
    s.expect(book.cells()[0].source()).to_equal("# Example")
    s.expect(book.cells()[0].kernel().to_string()).to_equal("markdown")
    s.expect(book.cells()[1].kernel().to_string()).to_equal("csharp")
    s.expect(book.metadata().get_json("title")).to_equal(Some("Example"))
    s.expect(@dib.parse(book.to_string())).to_equal(book)
    s.expect(book.cell(2)).to_equal(None)
  })
}
```

## Preserve empty source cells

Use one lossless mode value for cell construction, export and import. Empty
cells and leading or trailing empty source lines remain in the result.

```mbt check
///|
test "example: preserve empty Markdown and source boundary lines" {
  let source_mode = @dib.SourceMode::Lossless
  let registry = @dib.KernelRegistry(
    [@dib.KernelInfo(@dib.KernelName("scheme"))],
    default_kernel=@dib.KernelName("scheme"),
  )
  let book = @dib.Notebook::Notebook([
    @dib.Cell::Cell("", kernel=@dib.KernelName("markdown"), source_mode~),
    @dib.Cell::Cell("\n42\n", kernel=@dib.KernelName("scheme"), source_mode~),
  ], registry~)
  let exported = book.to_string(source_mode~)
  let restored = @dib.parse(exported, registry=book.registry(), source_mode~)
  @expect.expect(restored).to_equal(book)
  @expect.expect(restored.cells().length()).to_equal(2)
  @expect.expect(restored.cells()[0].source()).to_equal("")
  @expect.expect(restored.cells()[1].source()).to_equal("\n42\n")
}
```

## Supply a custom execution environment

A registry defines canonical names, aliases and a default. Language labels
describe the registration; this library does not install or run those kernels.
Keep the effective registry when custom definitions come from the environment.

```mbt check
///|
test "example: custom registry and contextual round trip" {
  let name = @dib.KernelName("example")
  let info = @dib.KernelInfo(
    name,
    aliases=[@dib.KernelName("ex")],
    language=Some("Example Language"),
  )
  let registry = @dib.KernelRegistry(
    [info],
    default_kernel=@dib.KernelName("ex"),
  )
  let book = @dib.parse("initial()\n#!ex\nnext()\n#!md\n# Note", registry~)
  let rendered = book.to_string()
  let restored = @dib.parse(rendered, registry=book.registry())
  @expect.expect_all(s => {
    s.expect(info.name()).to_equal(name)
    s.expect(info.language()).to_equal(Some("Example Language"))
    s.expect(info.aliases()[0].to_string()).to_equal("ex")
    s.expect(registry.default_kernel()).to_equal(name)
    s.expect(registry.resolve("ex")).to_equal(Some(name))
    s.expect(registry.resolve("EX")).to_equal(None)
    s.expect(book.cells_for_kernel("ex").length()).to_equal(2)
    s.expect(restored).to_equal(book)
  })
}
```

Parsing also supplies the Markdown pseudo-kernel. When a file must describe
its own custom selectors, persist their definitions in document metadata.

## Store custom kernels in document metadata

The first exact `#!meta` line starts a JSON object ending at the next `#!`
line. Metadata can span lines. Custom namespaces survive writing and cannot
be mutated through exported JSON.

```mbt check
///|
test "example: self-describing custom kernel metadata" {
  let source =
    #|#!meta
    #|{
    #|  "kernelInfo":{"defaultKernelName":"custom","items":[{"name":"custom","aliases":["alt"]}]},
    #|  "vendor":{"values":[1,2]}
    #|}
    #|#!alt
    #|custom()
  let book = @dib.parse(source)
  guard book.metadata().get_json("vendor") is Some(Object(vendor)) else {
    fail("missing vendor metadata")
  }
  guard vendor.get("values") is Some(Array(values)) else {
    fail("missing values")
  }
  values.clear()
  @expect.expect_all(s => {
    s.expect(book.cells()[0].kernel().to_string()).to_equal("custom")
    s.expect(book.metadata().get_json("vendor")).to_equal(Some({ "values": [1, 2] }))
    s.expect(@dib.parse(book.to_string())).to_equal(book)
  })
}
```

## Inspect directives through specialized cursors

Directive arguments remain unparsed text. Line numbers are one-based within
normalized cell source, rather than locations in the original file. Parsed
kernel selectors are cell properties and do not appear as directive children.

```mbt check
///|
test "example: specialized directive navigation" {
  let book = @dib.parse(
    "#!csharp\nvalue = 42;\n#!share --from fsharp x\n#!unknown --flag",
  )
  guard book.cursor().first_child() is Some(cell_cursor) else {
    fail("missing cell")
  }
  guard cell_cursor.first_child() is Some(directive_cursor) else {
    fail("missing directive")
  }
  guard directive_cursor.node() is Directive(directive) else {
    fail("expected directive")
  }
  @expect.expect_all(s => {
    s.expect(directive.name()).to_equal("share")
    s.expect(directive.arguments()).to_equal("--from fsharp x")
    s.expect(directive.text()).to_equal("#!share --from fsharp x")
    s.expect(directive.line()).to_equal(2)
    s.expect(directive_cursor.path().to_string()).to_equal("$[0][0]")
    s
    .expect(
      directive_cursor.next_sibling().map(cursor => cursor.path().to_string()),
    )
    .to_equal(Some("$[0][1]"))
    s
    .expect(directive_cursor.parent().map(cursor => cursor.path()))
    .to_equal(Some(cell_cursor.path()))
    s
    .expect(book.root().at(directive_cursor.path()))
    .to_equal(Some(directive_cursor.node()))
  })
}
```

## Read YAML, TOML and Ion metadata

Use a format-qualified header to select the parser. All three inputs feed
the same Ion-backed `Metadata` API. Saving uses JSON when it preserves that
value and Ion otherwise. YAML/TOML comments and source formatting are not saved.

```mbt check
///|
test "example: DIB metadata format extensions" {
  let yaml = @dib.parse("#!meta yaml\ntitle: Example\ntags: [demo, notebook]\n#!markdown\n# Heading")
  let toml = @dib.parse("#!meta toml\ntitle = \"Example\"\ncreated = 2026-10-19T12:30:00Z")
  let ion = @dib.parse("#!meta ion\n{title: \"Example\", amount: 1234.500}")
  guard toml.metadata().get("created") is Some(created) else { fail("missing timestamp") }
  @expect.expect_all(s => {
    s.expect(yaml.metadata().get_json("tags")).to_equal(Some(["demo", "notebook"]))
    s.expect(yaml.to_string().has_prefix("#!meta\n")).to_be_true()
    s.expect(created.ion_type().to_text()).to_equal("timestamp")
    s.expect(toml.to_string().has_prefix("#!meta ion\n")).to_be_true()
    s.expect(@dib.parse(toml.to_string())).to_equal(toml)
    s.expect(@dib.parse(ion.to_string(metadata_output=@dib.MetadataOutput::Ion))).to_equal(ion)
  })
}
```

## Catch invalid input and unsafe serialization

Kernel names and registry membership are separate checks. A constructed cell
can contain a selector in its source, but writing rejects it because reading
the result would silently split that cell.

```mbt check
///|
test "example: typed DIB errors" {
  let metadata_error : @dib.FormatError? = try {
    ignore(@dib.parse("#!meta\nnot JSON"))
    None
  } catch {
    error => Some(error)
  }
  let name_error : @dib.FormatError? = try {
    ignore(@dib.KernelName("meta"))
    None
  } catch {
    error => Some(error)
  }
  let unknown : @dib.FormatError? = try {
    ignore(
      @dib.Notebook::Notebook([
        @dib.Cell::Cell("run()", kernel=@dib.KernelName("unregistered")),
      ]),
    )
    None
  } catch {
    error => Some(error)
  }
  let book = @dib.Notebook::Notebook([
    @dib.Cell::Cell("before\n#!fsharp\nafter", kernel=@dib.KernelName("csharp")),
  ])
  let write_error : @dib.FormatError? = try {
    ignore(book.to_string())
    None
  } catch {
    error => Some(error)
  }
  @expect.expect_all(s => {
    s.expect(metadata_error is Some(InvalidMetadata(line=2, ..))).to_be_true()
    s.expect(name_error).to_equal(Some(@dib.InvalidKernelName("meta")))
    s.expect(unknown).to_equal(Some(@dib.UnknownKernel("unregistered")))
    s
    .expect(write_error)
    .to_equal(Some(@dib.UnrepresentableSource(cell=0, line=2)))
  })
}
```

Repeated names or aliases raise `DuplicateKernelName`. Errors for writing
report a zero-based cell index and a one-based source line.

## Preserve a literal metadata directive

The writer emits a document metadata header when needed to ensure a later
`#!meta` line stays source. The header can contain an empty object.

```mbt check
///|
test "example: retain a metadata marker in cell source" {
  let book = @dib.Notebook::Notebook([
    @dib.Cell::Cell("#!meta\nliteral source", kernel=@dib.KernelName("csharp")),
  ])
  let serialized = book.to_string()
  @expect.expect_all(s => {
    s.expect(serialized.has_prefix("#!meta\n\n{}\n")).to_be_true()
    s.expect(@dib.parse(serialized)).to_equal(book)
  })
}
```

## Account for empty-cell normalization

DIB omits empty cells when writing. Reading an empty document yields one
empty cell. Internal blank lines and lines containing spaces remain source.
This differs from Jupyter, which can persist explicitly empty cells.

```mbt check
///|
test "example: DIB empty cells and whitespace" {
  let empty = @dib.parse("")
  let book = @dib.Notebook::Notebook([
    @dib.Cell::Cell("", kernel=@dib.KernelName("csharp")),
    @dib.Cell::Cell("\nfirst\n\n \nlast\n", kernel=@dib.KernelName("fsharp")),
  ])
  let restored = @dib.parse(book.to_string())
  @expect.expect_all(s => {
    s.expect(empty.cells().length()).to_equal(1)
    s.expect(empty.cells()[0].source()).to_equal("")
    s.expect(empty.to_string()).to_equal("")
    s.expect(book.cells().length()).to_equal(2)
    s.expect(restored.cells().length()).to_equal(1)
    s.expect(restored.cells()[0].source()).to_equal("first\n\n \nlast")
  })
}
```

## Reuse a configured codec

```mbt check
///|
test "example: configured lossless codec" {
  let codec = @dib.Codec::lossless(
    default=@dib.KernelInfo(@dib.KernelName("moonbit")),
  ).with_kernel(@dib.KernelInfo(
    @dib.KernelName("python"), aliases=[@dib.KernelName("py")],
  ))
  let book = codec.notebook([
    codec.cell(""),
    codec.cell("\nprint(42)\n", kernel=@dib.KernelName("py")),
  ])
  assert_eq(codec.parse(codec.write(book)), book)
}
```

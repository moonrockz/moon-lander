///|
test "JSON YAML TOML and Ion headers share metadata and kernel registration" {
  let payloads = [
    ("#!meta", "{\"title\":\"Example\",\"enabled\":true,\"count\":42,\"tags\":[\"demo\",\"λ\"],\"kernelInfo\":{\"defaultKernelName\":\"custom\",\"items\":[{\"name\":\"custom\",\"aliases\":[\"alt\"]}]}}"),
    ("#!meta json", "{\"title\":\"Example\",\"enabled\":true,\"count\":42,\"tags\":[\"demo\",\"λ\"],\"kernelInfo\":{\"defaultKernelName\":\"custom\",\"items\":[{\"name\":\"custom\",\"aliases\":[\"alt\"]}]}}"),
    ("#!meta yaml", "title: Example\nenabled: true\ncount: 42\ntags: [demo, λ]\nkernelInfo:\n  defaultKernelName: custom\n  items:\n    - name: custom\n      aliases: [alt]"),
    ("#!meta toml", "title = \"Example\"\nenabled = true\ncount = 42\ntags = [\"demo\", \"λ\"]\n[kernelInfo]\ndefaultKernelName = \"custom\"\n[[kernelInfo.items]]\nname = \"custom\"\naliases = [\"alt\"]"),
    ("#!meta ion", "{title: \"Example\", enabled: true, count: 42, tags: [\"demo\", \"λ\"], kernelInfo: {defaultKernelName: \"custom\", items: [{name: \"custom\", aliases: [\"alt\"]}]}}"),
  ]
  let expected = @dib.Metadata({
    "title": "Example", "enabled": true, "count": 42, "tags": ["demo", "λ"],
    "kernelInfo": {"defaultKernelName": "custom", "items": [{"name": "custom", "aliases": ["alt"]}]},
  })
  for (header, payload) in payloads {
    let source = "\u{FEFF}\r\n" + header + "\n" + payload + "\n#!alt\nrun()"
    let book = @dib.parse(source.replace_all(old="\n", new="\r\n"))
    @expect.expect_all(s => {
      s.expect(book.metadata()).to_equal(expected)
      s.expect(book.registry().default_kernel().to_string()).to_equal("custom")
      s.expect(book.cells_for_kernel("alt")[0].source()).to_equal("run()")
      s.expect(book.to_string().has_prefix("#!meta\n")).to_be_true()
      s.expect(@dib.parse(book.to_string())).to_equal(book)
      s.expect(@dib.parse(book.to_string(metadata_output=@dib.MetadataOutput::Ion))).to_equal(book)
    })
  }
}

///|
test "TOML timestamps local times nonfinite floats and large integers survive Ion output" {
  let source =
    #|#!meta toml
    #|date = 2026-10-19
    #|local = 2026-10-19T12:30:00
    #|offset = 2026-10-19T12:30:00Z
    #|time = 12:30:00
    #|positive = inf
    #|negative = -inf
    #|not_a_number = nan
    #|large = 9223372036854775807
    #|ratio = 1.5
  let book = @dib.parse(source)
  let metadata = book.metadata()
  guard metadata.get("date") is Some(date) else { fail("date missing") }
  guard date.kind() is Timestamp(day) else { fail("date lost its type") }
  guard metadata.get("local") is Some(local_value) else { fail("local missing") }
  guard local_value.kind() is Timestamp(local_time) else { fail("local lost its type") }
  guard metadata.get("time") is Some(time) else { fail("time missing") }
  guard metadata.get("large") is Some(large) else { fail("large missing") }
  guard large.kind() is Int(integer) else { fail("integer lost its type") }
  @expect.expect_all(s => {
    s.expect(day.to_ion_string()).to_equal("2026-10-19")
    s.expect(local_time.to_ion_string()).to_equal("2026-10-19T12:30:00-00:00")
    s.expect(time.annotations().map(token => token.text())).to_equal([Some("toml_local_time")])
    s.expect(time.kind() is String("12:30:00")).to_be_true()
    s.expect(integer.to_string()).to_equal("9223372036854775807")
    s.expect(book.to_string().has_prefix("#!meta ion\n")).to_be_true()
    s.expect(@dib.parse(book.to_string())).to_equal(book)
  })
  try book.to_string(metadata_output=@dib.MetadataOutput::Json) catch {
    @dib.InvalidMetadata(_) => ()
    _ => fail("expected metadata conversion error")
  } noraise { _ => fail("expected explicit JSON output to reject data loss") }
}

///|
test "YAML handles multiline data nulls nonfinite numbers and exact integers" {
  let source =
    #|#!meta yaml
    #|title: Example
    #|description: |
    #|  first
    #|  #!meta toml
    #|  last
    #|empty: null
    #|large: 9223372036854775807
    #|special: .inf
    #|nested:
    #|  items: [true, false, null]
  let book = @dib.parse(source)
  @expect.expect_all(s => {
    s.expect(book.metadata().get_json("empty")).to_equal(Some(null))
    s.expect(book.metadata().get_json("description")).to_equal(Some("first\n#!meta toml\nlast\n"))
    s.expect(book.metadata().get_json("nested")).to_equal(Some({"items": [true, false, null]}))
    s.expect(book.metadata().get_json("large").map(value => value.stringify())).to_equal(Some("9223372036854775807"))
    s.expect(@dib.parse(book.to_string())).to_equal(book)
  })
}

///|
test "invalid payloads and non-object metadata report the section start line" {
  for source in [
    "#!meta yaml\n- a\n- b", "#!meta yaml\nscalar", "#!meta yaml\na: [", "#!meta yaml\na: 1\n---\nb: 2",
    "#!meta yaml\na: 1\na: 2", "#!meta toml\na = [", "#!meta toml\na = 1\na = 2",
    "#!meta ion\n[1, 2]", "#!meta ion\n{a: 1, a: 2}", "#!meta ion\n{} {}", "#!meta ion\nnull.struct",
    "#!meta\ntitle: no auto-detection", "#!meta json\n{} trailing",
  ] {
    try @dib.parse(source) catch {
      @dib.InvalidMetadata(line~, ..) => @expect.expect(line).to_equal(2)
      _ => fail("expected invalid metadata")
    } noraise { _ => fail("expected invalid metadata to raise: " + source) }
  }
}

///|
test "empty YAML and TOML sections normalize to empty metadata" {
  for header in ["#!meta yaml", "#!meta toml"] {
    for payload in ["", "# comment only"] {
      let book = @dib.parse(header + "\n" + payload)
      @expect.expect(book.metadata().is_empty()).to_be_true()
      @expect.expect(@dib.parse(book.to_string())).to_equal(book)
    }
  }
}

///|
test "all metadata headers remain literal after the first section and when constructed" {
  for header in ["#!meta", "#!meta json", "#!meta yaml", "#!meta toml", "#!meta ion"] {
    let cell = @dib.Cell::Cell(header + "\nliteral", kernel=@dib.KernelName("csharp"))
    let book = @dib.Notebook::Notebook([cell])
    @expect.expect(@dib.parse(book.to_string())).to_equal(book)
    let parsed = @dib.parse("#!meta yaml\n{}\n#!csharp\n" + header + "\nliteral")
    @expect.expect(parsed.cells()[0].source()).to_equal(header + "\nliteral")
    @expect.expect(@dib.parse(parsed.to_string())).to_equal(parsed)
    let name = header[2:].to_owned()
    try @dib.KernelName(name) catch {
      @dib.InvalidKernelName(_) => ()
      _ => fail("expected reserved kernel name")
    } noraise { _ => fail("expected metadata selector to be reserved") }
  }
}

///|
test "root Ion annotations on empty metadata survive writing" {
  let book = @dib.parse("#!meta ion\nannotated::{}")
  @expect.expect(book.metadata().is_empty()).to_be_false()
  @expect.expect(@dib.parse(book.to_string())).to_equal(book)
}

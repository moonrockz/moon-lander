///|
test "nested Polyglot and legacy kernel declarations remain self describing" {
  for metadata_key in ["polyglot_notebook", "dotnet_interactive"] {
    let fields : Map[String, Json] = Map([])
    fields[metadata_key] = { "kernelInfo": {
      "defaultKernelName": "python",
      "items": [{ "name": "python", "aliases": ["py"], }],
    }, }
    let source = "#!meta\n" + Json(fields).stringify() + "\n#!py\nprint(42)\n"
    let book = @dib.parse(source, source_mode=@dib.Lossless)
    assert_eq(book.registry().default_kernel(), @dib.KernelName("python"))
    assert_eq(book.cells()[0].kernel(), @dib.KernelName("python"))
    assert_eq(@dib.parse(book.to_string(source_mode=@dib.Lossless), source_mode=@dib.Lossless), book)
  }
}

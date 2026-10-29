# Convert source notebooks

`Converter` converts whole source notebooks between DIB and Jupyter. It preserves
source-cell order, empty cells and LF-normalized source. Custom kernels travel
through `polyglot_notebook.kernelName` cell metadata and notebook kernelInfo
registrations, following the Polyglot notebook convention.

```mbt check
///|
test "example: convert notebook source with an explicit loss policy" {
  let codec = @dib.Codec::lossless()
  let original = codec.notebook([codec.cell("42"), codec.cell("")])
  let converter = @conversion.Converter::new(policy=@conversion.SourceOnly)
  let jupyter = converter.to_jupyter(original)
  assert_true(jupyter.losses().is_empty())
  let restored = converter.to_dib(jupyter.notebook())
  assert_eq(restored.notebook().cells(), original.cells())
  assert_eq(restored.losses().length(), 2) // Jupyter cell IDs have no DIB equivalent.
  assert_eq(@dib.parse(restored.text(), source_mode=@dib.Lossless).cells(), original.cells())
}
```

`Reject` is the default policy. It raises `ConversionError::Lossy` whenever
conversion would discard reported state. `SourceOnly` permits those losses and
returns their typed report beside the converted notebook and serialized text.
Review `losses()` before using the result. Conversion reports Jupyter cell IDs,
unsupported cell metadata, outputs, execution counts, attachments and extension
fields. Unknown source cell types are refused. Registered selectors inside a
cell retain DIB's representation refusal, even under SourceOnly.

A normal v4.5 notebook has cell IDs, so conversion to DIB generally requires
explicit SourceOnly policy. The policy is configured once per converter. The
original notebook remains unchanged. Non-JSON Ion metadata cannot be written as
Jupyter metadata and raises the existing typed metadata conversion error.

This is source-notebook conversion. For file-tree documents, use
`@files.convert_tree(text, source=from_format, target=to_format)` with the DIB and
Jupyter file-tree adapters. That operation maps first-line DIB declarations to
`metadata.vfs`, preserves the selected tree, and excludes unrelated notes and
execution state as documented by the tree projection.

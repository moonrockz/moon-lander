# Changelog

## 0.1.0 - 2026-10-19

Moon-Lander now owns `moonrockz/notebooks`, migrated from Moonbase with its
Jupyter and DIB codecs, shared navigation, usage guides, acceptance suites
and property laws.

### Added

- Select Jupyter cells by MIME type in rich outputs and attachments.
- Use `MimeTyped` to require MIME lookup support in generic code.
- Inspect MIME support at runtime through `CellView`, including mixed Jupyter,
  DIB and consumer-defined cell collections.
- Read DIB metadata using `#!meta yaml`, `#!meta toml` and `#!meta ion`.
- Store shared metadata as immutable Ion values, preserving native types and
  defensively copying containers and annotations.
- Choose DIB metadata output with `MetadataOutput`. Automatic output uses JSON
  when it preserves the value and Ion otherwise.

### Breaking changes

- `Metadata.get(key)` returns an Ion value. Use `get_json(key)` for explicit
  JSON lookup, or inspect the native value's `kind()`.
- `Metadata.to_json()` and `get_json()` can raise `MetadataError::NotJson`.
  Use `to_ion()` and `Metadata::from_ion(value)` for the full native model.
- Jupyter notebook, cell and output JSON exports are fallible and report
  `FormatError`. Jupyter constructors reject metadata requiring Ion-only types.
- DIB reserves the format-qualified metadata selectors as kernel names.

The `moonrockz/notebooks` module name and package import paths are unchanged.
The framework module remains provisional. The workspace root and acceptance
test module are not published.

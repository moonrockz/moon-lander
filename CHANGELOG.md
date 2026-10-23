# Changelog

## Unreleased

### Breaking changes

- `moonrockz/moon-lander/mediator`: `Topic::publish` calls every handler of
  the topic, in add order, also after a handler raises an error. After the
  last handler it raises one `MediatorError::PublishFailed(handlers~,
  failures~)`, also when only one handler fails. Before, publish stopped at
  the first handler that raised and passed that error out. A caller that
  caught the raw handler error catches `PublishFailed` instead and reads each
  error from `failures`. `Sender::send` does not change.
- `MediatorError` has the new cases `PublishFailed` and `TimedOut`. A
  `match` on `MediatorError` with no wildcard must add them.

### Added

- `PublishFailure`, one handler failure of a publish: the 1-based `position`
  of the handler and the `error` that it raised. `MediatorError::message`
  gives only the failure count, the handler count and the positions, not
  event values or the text of the wrapped errors.
- `moonrockz/moon-lander/mediator/async` (`@mediator_async`), the async
  mediator for `wasm`, `js` and `native`. It has typed async senders and
  topics, `publish` (one handler at a time) and `publish_concurrent` (all
  handlers in one task group), both with one `PublishFailed` in add order,
  and no fire-and-forget publish. A caller cancellation stops the running
  handlers and passes out; it is never a failure. Async middleware has the
  core helper names, with async `before` and `after` and a sync `finally_`
  that also runs during a cancellation. `timeout(after_ms)` cancels a slow
  step and raises the new core case `MediatorError::TimedOut(after_ms~)`,
  whose message is "Request timed out after N ms". `Sender::from_sync` and
  `Topic::from_sync` wrap core values with their middleware.

## 0.2.0 - 2026-10-22

Moon-Lander adds `moonrockz/openrpc` and a release workflow. The shared
workspace version moves to `0.2.0`, so `moonrockz/notebooks` is republished
unchanged at `0.2.0`.

### Added

- `moonrockz/openrpc`, a portable OpenRPC 1.3.2 and 1.4.x document
  library with no framework dependency. It reads strict JSON into a
  source-preserving CST and a typed AST, keeps exact number tokens and
  extensions, and writes canonical or pretty JSON. It models and checks
  draft-07 schema documents, including portable ECMAScript 2018 regex syntax,
  and resolves references only through explicit resources. Validation reports
  model, schema, reference, normative and pinned-artifact facets under the
  `Specification` and `MetaschemaCompatibility` profiles, with structured,
  ordered findings. Checked edits replace one value while keeping the rest of
  the source.
- A GitHub Actions release workflow publishes the public modules to
  mooncakes.io, verifies the published OpenRPC module from the public registry
  and creates the GitHub release.
- `moonrockz/moon-lander/mediator`, a synchronous mediator in the framework
  module: typed senders and topics, middleware with `before`, `after` and
  `finally_`, a context value, and `MediatorError::Rejected`. The compiler is
  the registry, so there is no text key and no runtime lookup. In `0.2.0`,
  `Topic::publish` stops at the first handler that raises. The framework
  module is not published.

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

# Changelog

## 0.4.0 - 2026-10-27

Moon-Lander splits the framework into six modules, adds the application host
and the logging module, and types the configuration file-tree paths. The shared
workspace version moves to `0.4.0`, so `moonrockz/notebooks` and
`moonrockz/openrpc` are republished unchanged at `0.4.0`. The framework modules
are not published.

### Breaking changes

- The framework is six modules. `moonrockz/moon-lander/config` is now
  `moonrockz/moon-lander-config` (`@config`), with `conventions`, `host` and
  `browser` below it; `moonrockz/moon-lander/config/formats/<name>` is
  `moonrockz/moon-lander-config/parsers/<name>`, and the linked format set is
  `moonrockz/moon-lander-config/formats`. The mediator is
  `moonrockz/moon-lander-mediator` (`@mediator`), with the async mediator in
  `moonrockz/moon-lander-mediator/async`. The host is
  `moonrockz/moon-lander-hosting`. `moonrockz/moon-lander` stays the umbrella
  module.
- `moonrockz/moon-lander-mediator`: a caller cannot make an invalid
  `MediatorError`. Use `MediatorError::rejected(reason)` in place of the
  `Rejected` constructor, give `timed_out` and the async `timeout` middleware a
  core `TimeLimit`, and read publish failures through the collection accessors.
- `moonrockz/moon-lander-config`: every `FileTree` path parameter, both
  `FileRequest` cases and `LoadContext.working_dir` take the new
  `FileTreePath`. Make one with `FileTreePath::parse` or, for native Windows
  text, `FileTreePath::from_native`. The load parses the builder working
  directory and each file source one time, so `C:\cfg\app.toml` with the working
  directory `C:/proj` now loads `C:/cfg/app.toml`. A drive-relative path such
  as `C:app.toml`, or `\` in portable text, is the new configuration error
  `InvalidFilePath` with a `FilePathRule`.
- `EntryKind` has the new case `Inaccessible`. An exhaustive `match` on it must
  add the case.

### Added

- `moonrockz/moon-lander-core`: `AppName` and `TimeLimit` (for example `2m30s`),
  with smart constructors. `moonrockz/moon-lander-config` binds a `TimeLimit`
  from configuration text.
- `moonrockz/moon-lander-logging`: a bring-your-own `Logger` trait, six levels,
  immutable `LogEvent` values, `{Name}` message templates, `null_logger`,
  `MemoryLogger`, `min_level`, `fan_out` and `with_category`.
- `moonrockz/moon-lander-hosting`: the application host. It parses the
  arguments first with the standard flags, resolves the environment name, loads
  the configuration with the variable prefix and the starting settings, builds
  the services record, and runs the hooks in order with a lifetime, stop
  requests, cancellation checks, a bounded shutdown timeout, exit-code
  precedence and an error report. It has console drivers for native and js,
  with signal handling, and an embedded driver for wasm and wasm-gc. Mapped
  command-line options become the last configuration source.
- `FileTreePath` operations: `parent`, `name`, `child`, `join`, `resolve`,
  `root`, `is_within`, `common_dir`, `to_native` and `from_absolute`.
  `ConfigBuilder::given_file_paths` gives the source path texts as given.

### Fixed

- Workspace discovery on Windows no longer fails with an OS error on a locked
  entry such as `D:/pagefile.sys` at the drive root. A host adapter records an
  entry that it cannot inspect as `Inaccessible`; the load still reads it when it
  is a candidate, so its real error is not hidden. The directory of a file below a
  drive root is the drive root `C:/`, not the drive-relative `C:`.

## 0.3.0 - 2026-10-23

Moon-Lander changes the mediator publish policy and adds the async mediator
in the framework module. The shared workspace version moves to `0.3.0`, so
`moonrockz/notebooks` and `moonrockz/openrpc` are republished unchanged at
`0.3.0`. The framework module `moonrockz/moon-lander` is not published.

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

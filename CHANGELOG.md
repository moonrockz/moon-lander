# Changelog

## Unreleased

### Added

- `moonrockz/sigstore` verifies RFC 3161 timestamps (TimeStampResp, CMS SignedData
  and its signed attributes, the TSA chain at the timestamp time, the imprint over
  the bundle signature). Bundles with no transparency log entry verify when a
  timestamp gives their time, as for attestations of private repositories and the
  release attestations of GitHub immutable releases.
- `TrustedRoot::github()` pins the trusted root of GitHub's Sigstore instance (TUF
  target SHA-256 `484cdfe1…fbb7`). `TrustedRoot::combine` and
  `TrustedRoot::github_attestations()` join roots; an SCT is required only for
  authorities whose root lists CT logs.
- `Policy::github_release(repository, tag~)` with `ReleaseTag`,
  `PredicateType::github_release_v0_2()` and `PolicyMismatch::ReleaseMismatch` match
  the release predicate (repository, tag, purl, optional repository and owner IDs).
- Rekor v1 `intoto/0.0.2` entries verify.
- An empty SCT list, and PrintableString or IA5String text outside its character
  set, are refused.

### Changed (breaking)

- `VerifiedBundle` replaces `log_id`, `log_index` and `integrated_time` with
  `times : Array[VerifiedTime]`, each with a `TimeSource` (`Log` or `Authority`).
- `Failure` gains `Timestamp`, `TimestampAuthority` and `TimestampTime`;
  `Feature::TimestampAuthority` becomes `Feature::TimestampAlgorithm`; `Statement`
  gains `predicate`. A caller that matches every case adds the new arms.
- Every log entry and every timestamp of a bundle must verify. A leaf whose
  certificate authority comes from a root that lists transparency logs (such as
  public good) still needs a log entry from one of them; a timestamp alone is not
  enough. An SCT must come from a CT log of the same root as its authority.

## 0.10.0 - 2026-10-31

All twelve libraries share this minor version. The Sigstore verifier module is
published for the first time. Existing public APIs remain compatible.

### Added

- `moonrockz/sigstore`: pure, portable verification of Sigstore bundles and
  GitHub artifact attestations on wasm, wasm-gc, JavaScript and native. It
  checks the DSSE or message signature, the Fulcio certificate chain and SCT,
  and the Rekor v1 entry with its inclusion proof and checkpoint, against a
  trusted root, a publisher identity policy and a given time. A verdict gives
  one typed reason, and unsupported bundles (Rekor v2, timestamp authorities,
  public keys) give a typed not-supported reason. The module embeds the pinned
  Sigstore public-good root and imports `moonbitstack/mooncrypt@0.4.4`.
- Publish and verify `moonrockz/sigstore` as the twelfth library, after
  `moonrockz/openrpc`, with an isolated registry consumer that verifies a real
  GitHub bundle on all four targets. `mise run check:sigstore` fails when a
  target runs zero sigstore tests, `mise run check:sigstore-assets` rejects a
  stale generated root or fixture, and the manual `mise run bench:sigstore`
  times one verification.
- `Policy::github_workflow` requires SLSA provenance v1 by default, as
  `gh attestation verify` does; give `predicate_type=` for another type.

### Not supported yet

- RFC 3161 timestamps (the only time source of attestations from private
  repositories and GitHub immutable releases), Rekor v2 entries, managed-key
  bundles and Ed25519 or RSA keys give `Rejected(Unsupported(...))`. A Sigstore
  TUF client that refreshes the trusted root is a later change.

## 0.9.0 - 2026-10-30

All eleven libraries share this minor version. The optional Moonx launcher
module is published for the first time. Existing public APIs remain compatible.

### Added

- `moonrockz/moon-lander-moonx`: immutable typed process, argument, shutdown,
  private Node payload and completion values. The policy root supports wasm,
  wasm-gc, JavaScript and native; the synchronous process driver supports wasm
  and native with a separate parent runtime.
- Original POSIX SIGINT/SIGTERM forwarding with genuine Node-owned host
  completion, bounded child reaping, idle stdin and protected finalization.
  Materialize complete Node/worker layouts in a private owned directory and
  remove them after reaping, including startup failure and cancellation.
- Public `/launch` with opaque argv and binary streams. Parent `--json` owns
  help, usage errors and not-started reports. A started child owns its output
  and application result schema. Node is an explicit prerequisite.
- Licensed frozen async0.22.5 source with deterministic provenance, drift
  checks, retained upstream tests and documented maintenance/removal criteria.
- Eleven-library publication and source-archive verification, with separate
  cold default-registry source and public Moonx asset qualification on stock
  0.10.16+b1a0e846e and 0.10.17+d971670cd.

### Platform behavior

- Stock Windows Moonrun delivers parent Ctrl-C to Node as Ctrl-Break. A genuine
  Moon-Lander Node host reports Quit/131 while the parent retains Interrupt and
  its full Windows cancellation status. This documented limitation does not
  change existing native, JS, embedded or actor behavior. Actual Windows finite
  transport, Ctrl-Break, forced reaping and private payload cleanup are qualified.

## 0.8.0 - 2026-10-29

All ten libraries share this minor version. The optional actors module is
published for the first time. Existing public APIs remain compatible.

### Added

- `moonrockz/moon-lander-actors`: local typed actors with private state,
  scope-owned lifetimes and bounded FIFO mailboxes. Add blocking admission,
  nonblocking `try_send`, backpressure and cancellation-safe admission.
- Composable `Receive` values, selective receive, state actors, deterministic
  message-based test runners and stack-safe receive loops. The policy root
  supports wasm, wasm-gc, JavaScript and native; the actor runtime supports wasm,
  JavaScript and native.
- Typed request/reply with admission-and-reply deadlines, subjects, services and
  responders. Add close, drain, cancellation, protected cleanup, initialization,
  child scopes, scoped names and addresses, immutable directories and event
  topics. The actors module imports only core and `moonbitlang/async` and remains
  separate from the umbrella module.
- Notebook virtual text file trees with checked relative paths, explicit empty
  directories and typed conflict errors. DIB file declarations and Jupyter
  `metadata.vfs` read and write the same portable model through `TreeFormat`.
- Whole source-notebook conversion between DIB and Jupyter, with preserved cell
  order, empty cells, source boundaries and custom kernel identities. The default
  policy rejects reported losses; explicit `SourceOnly` returns typed loss
  reports with the converted notebook and serialized text.
- Configured DIB `Codec` and the open `KernelDescriptor` trait for shared kernel
  registration and source-mode settings.

### Changed

- Replace the private docs generator with published Telescope 0.5.1, retaining
  docs/API routes, anchors, diagrams, search and versioned release assets.
- Add the Moonrockz bunny-and-lander mascot, logos and browser icons, a new
  landing page, and Smithy light/dark colors. Native Windows docs tooling uses
  the upstream host-path repair and a tested local API-index link adapter.
- Publish and verify the actors library alongside the existing nine libraries,
  with isolated candidate/public consumers and supported-target checks.

### Fixed

- Read nested Polyglot and legacy kernelInfo registrations so custom notebook
  kernels remain self-describing after source conversion.

## 0.7.3 - 2026-10-28

All nine libraries share this patch version.

### Fixed

- Add optional `completed(outcome, selected)` reporting to console and both
  logging bridge entry points. Applications can report clean pending stops before
  any hook or command, after diagnostic finalization, without a copied driver.
- Protect once-only reporting from cancellation and preserve selected signal
  precedence when reporting raises. Default callers and embedded execution keep
  their behavior. Qualify real native/Node/Bun lifecycle output and fresh public
  completion consumers for selected 130/143.

## 0.7.2 - 2026-10-28

All nine libraries share this patch version.

### Fixed

- Add `Context.stop_requested()`, `Lifetime.stop_requested()` and
  `StopToken.stop_requested()` for synchronous foreign callbacks on the host
  thread. They poll the existing registered probes and retained stop request
  without querying the current coroutine. Task-aware cancellation, first stop
  reason and signal exit-code precedence remain compatible.
- `mediator/async` sender and before/after/finally middleware composition can
  be imported on all four targets. Non-suspending async sends work under the
  embedded host on wasm and wasm-gc, with no event loop. Timeout and topic
  operations retain their existing wasm/JS/native behavior and target boundary.
- Qualify real native/JS asynchronous completion, including a JavaScript
  Promise, typed failure, cancellation, finalization and timeout compatibility.
  Fresh registry consumers execute the same public composition through the
  embedded or runtime host path on each target.
- Worker acceptance timeouts now report their typed child phase and streamed
  output. Existing deadlines, true signal reasons/codes and drain assertions
  stay in place; this adds evidence for the intermittent worker follow-up.

## 0.7.1 - 2026-10-28

All nine libraries share this patch version. Existing logging bridge callers
and default signal handling remain compatible.

### Fixed

- The public hosting logging bridge now forwards an optional enclosing
  `SignalProbe` to the console driver, retaining the actual signal reason and
  exit code through cleanup, including non-yielding JavaScript workers.
- Add `logging.run_with_session` so a real diagnostic hosted service can close
  and drain its session before telemetry stops. Unconditional final cleanup,
  repeated close, cancellation protection and direct failure reporting remain
  safe after early hosted close. Only records accepted before close are covered
  by its drain; later log attempts cannot reopen the session.
- Qualify ordered drain, startup failure, skipped/timed-out stop hooks,
  cancellation, sink failures and public bridge consumers on native and
  JavaScript, with parent-owned worker SIGINT/SIGTERM coverage.

## 0.7.0 - 2026-10-28

All nine libraries share this version. Existing discovery, DIB encoding and
array-form JSON logging defaults remain compatible.

### Breaking changes

- Exhaustive `ConfigError` matches must handle `ConventionPolicy`. Its typed
  `ConventionRule` identifies invalid discovery-policy inputs.

### Added

- Opt-in workspace-first discovery with public root evidence, ordered format
  groups, supplemental workspace documents and selected-file overlays. JSON5/JSON,
  YAML/YML and TOML can compose at each source stage. Normalized file identities
  prevent duplicate selected-file loads, transforms and reports.
- Layered configuration profiles retain each control and group definition's
  original source. Selecting a discovered base preserves control authority;
  external selected files remain unable to activate profiles.
- Enclosing-host shutdown through `Lifetime::stop_from_embedder` and
  `RunOutcome::stop_reason`. An optional `SignalProbe` lets a native or JavaScript
  console run observe signals owned by an enclosing process without installing
  console listeners, including a spinning worker and protected cleanup.
- Lossless DIB source mode preserves empty and consecutive cells and their source
  boundaries. Existing normalized encoding remains the default.
- `format_json_object_line` and the rolling sink's `NamedObject` policy emit named
  values under `properties`. The last occurrence wins; repeated names also have
  all values, including the winner, in ordered `duplicateProperties` arrays.
  Nulls, arrays and objects retain their JSON types. The duplicate object is
  omitted when no names repeat; the existing array formatter and sink default
  retain schema 1.
- Public rolling-sink, embedding, disk-adapter and isolated registry-consumer
  regressions for these APIs, with portable configuration and DIB coverage on
  wasm, wasm-gc, JavaScript and native.

### Fixed

- Preserve the enclosing-workspace search's skip-ambiguous fallback when ordered
  formats use `NearestFile`. Workspace-first discovery still rejects an examined
  ambiguous location.

## 0.6.0 - 2026-10-28

The framework libraries are now published to mooncakes.io. Earlier releases
omitted them from the publication list. All nine libraries use version `0.6.0`
and exact sibling dependency versions. The release also adds opt-in configuration
profiles.

### Breaking changes

- Configuration providers use `Expansion::new` and accessors in place of record
  literals and field reads. Complete `DiscoveryOptions` literals add
  `profiles: Unspecified`. Exhaustive matches must handle
  `ProfileFile(ProfileName)` and `ConfigError::Profile`.

### Changed

- Update the direct `moonbitlang/x` dependency to `0.5.6` in configuration, the
  docs tool and task scripts. Other direct library pins already match the latest
  stable registry versions.

### Added

- Opt-in configuration profiles with ordered activation, defaults, includes,
  bounded groups and adjacent profile files. Activate them through typed
  options, `--profiles`, prefixed variables or eligible base files. Loaded
  configuration and host contexts expose immutable profile resolution.
- Public modules: `moonrockz/moon-lander-core`, `moonrockz/moon-lander-logging`,
  `moonrockz/moon-lander-config`, `moonrockz/moon-lander-mediator`,
  `moonrockz/moon-lander-logging-hosting-async`, `moonrockz/moon-lander-hosting`
  and `moonrockz/moon-lander`. `moonrockz/notebooks` and `moonrockz/openrpc`
  are republished at the same version.
- Dependency-ordered publication, archive audits and isolated registry consumer
  checks for every library. Public archive checksums and format override checks
  must pass before GitHub release creation.
- Private manifests for tooling, tests and generated consumers, with an enforced
  nine-library publication allowlist.

## 0.5.0 - 2026-10-28

Moon-Lander adds console and rolling file logging. The shared workspace version
moves to `0.5.0`, so `moonrockz/notebooks` and `moonrockz/openrpc` are
republished unchanged at `0.5.0`. The framework modules, including the new
`moonrockz/moon-lander-logging-hosting-async`, are not published.

### Added

- `moonrockz/moon-lander-logging`: `LogEvent::segments` gives the message as
  ordered literal and bound-value segments. The new pure packages work on all four
  targets: `formatting` (UTC `LogTimestamp`, `LogRecord`, the Literate and plain
  console layout, the text file layout and JSON Lines version 1 with ordered
  `{name, value}` properties) and `rolling` (`LogFileStem`, `FileSet`,
  `RollingPolicy`, `Retention`, `ByteCount` and the rolling plan and retention).
- `moonrockz/moon-lander-logging-hosting-async`, a new optional module that
  imports core, logging and `moonbitlang/async` only. Its root has typed
  settings (`SessionSettings`, `ConsoleSink`, `FileSink`, queue and record limits,
  `ColorMode`) and reports. Its `runtime` package (native, and js on Node.js and
  Bun) has `with_session`: a bounded queue that drops the newest record when it
  is full and counts each drop, one writer task, `drain` and `close`, the console
  on standard error by default, and daily plus 10 MiB rolling text and JSON Lines
  files that keep the newest 31, guarded by an ownership marker.
- `moonrockz/moon-lander-hosting`: `@console.run` takes an optional `finalize`
  step that runs after the run and its reports, before the process ends;
  `report_writer` sends the default report lines to a writer; and the new
  `hosting/logging` bridge runs a host with a logging session and drains it
  before exit, also after a start failure, a shutdown timeout or a first signal.

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

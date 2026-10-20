# Proposal: add-configuration-binding

## Why

An application must read its merged configuration as typed values, like .NET
`Get<T>`, `Bind` and the Options pattern. Today finos/morphir-moonbit reads
configuration with more than 60 calls that look up dotted text keys
(`document.text("ir.layout", "single-file")`, `document.boolean("ir.strict_mode",
false)`). Each call repeats a fallback, checks one type, and raises one
`Invalid(String)` error. Only one file (`config/metadata_provider.mbt`) tells the
user which source set the bad value. Binding replaces these calls with one typed
read for each section, and each failure names the key and its source.

## What Changes

- Add `bind`: decode a configuration section into a type `T : FromJson`. The
  section key is a non-empty key path. Add `bind_root` to decode the full
  configuration.
- Add `bind_or`: merge the configuration section over a typed default value with
  the core merge rules, then decode. Keys that no source sets keep their default
  values. The type must be `ToJson + FromJson`.
- Fill the core `BindFailure` value for typed, source-aware decode errors. Each
  error names the full decode path (the key path, plus a list index and field
  suffix inside a list) and the sources that set the bad value, or says that no
  source set the key, or that the value came from the default. Origins show the
  file role name, and file paths use `/` on every platform.
- Add the `Validate` trait. Validation runs after binding and reports all failures
  together, each with its key path and source.
- Add `Options[T]`, an immutable bound and validated value, and `NamedOptions[T]`
  for many named instances of one type in one section.
- Add the `FromConfig` trait and `bind_with`. They decode directly from the Ion
  value tree, so values that `Json` cannot hold exactly (Ion decimals, timestamps,
  big integers, `Int64`) keep their exact values. Add `Sourced[T]`, a value with
  its origin, for values such as relative paths that need the file that set them.
- Add an optional unknown-key check for types that are `ToJson + FromJson`.
- Make all binding functions take the configuration as their first argument so
  that they work in `|>` pipelines.

## Out of scope

- The value tree, key paths, sources, merge rules, provenance, secrets and
  `ConfigError` itself. The change `add-configuration-core` owns them. The core
  also declares the `Decode` and `Validation` cases and the `BindFailure` value
  that they hold. This change fills and raises them. It adds no error case and no
  error type of its own.
- File discovery and conventions (`add-configuration-conventions`).
- The host, `Context[S]`, commands and exit codes (`add-host-lifecycle`). The host
  maps binding errors to its configuration exit code.
- Reload on file change, options snapshots and options monitors. The configuration
  does not change after the host builds it.
- A DI container. Options are values that the application puts in its services
  record.
- Changes to MoonBit `derive(FromJson)` behavior or to its deprecated derive
  arguments. Binding depends only on the `FromJson` trait.
- Secret resolution during binding. Binding never resolves a secret reference.

## Capabilities

### New Capabilities

- `configuration-binding`: typed reads of configuration sections into application
  values, defaults merged under configuration, source-aware decode and validation
  errors, options values, and exact decoding from the Ion value tree.

### Modified Capabilities

None.

## Impact

- New source files in package `moonrockz/moon-lander/config` (`@config`). No new
  package and no new module dependency: `moonbitlang/core/json` and
  `moonrockz/ion` come from `add-configuration-core`.
- No change to `ConfigError`. Binding raises the core `Decode` and `Validation`
  cases. The host change maps every `ConfigError` to exit code 2.
- New acceptance suites in the unpublished `tests/` module.
- morphir-moonbit can replace its dotted-path reads in `projects.mbt`, `plan.mbt`,
  `workspace/workspace.mbt`, `config/metadata_provider.mbt` and `apps/morphir/main.mbt`
  with typed section records. That migration happens in morphir-moonbit.
- No breaking changes.

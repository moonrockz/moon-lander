# Proposal: add-configuration-core

## Why

Moon-Lander must give MoonBit applications layered, hierarchical configuration,
like .NET Microsoft.Extensions.Configuration. The first consumer,
finos/morphir-moonbit, has configuration code with known problems: lookups by
untyped dotted strings, one `Invalid(String)` error for all failures, TOML as the
only value model, YAML that it finds but cannot load, every `MORPHIR_*` variable
as a configuration key, and provenance that it records but does not show.

This change supplies the core that the other configuration and host changes use.
The core is generic. The Morphir rules are its defaults, but the core does not
hard-code the Morphir file layout.

## What Changes

- Add one Ion-based configuration value tree (`ConfigValue`). Each format parses
  into this tree before the merge.
- Add `KeyPath`, a typed path into the tree, with a dotted text form. A key path is
  never empty and never indexes a list.
- Add configuration sources as ordered, typed values (`ConfigSource`): defaults,
  in-memory (a value tree or flat key-path pairs), a file at an explicit path, an
  explicit candidate list, environment variables, and a generic overrides layer.
  The argparse adapter in `add-host-lifecycle` supplies the overrides layer.
- Add the shared source kinds `SourceKind` and `FileRole`, so reports show
  Morphir's kind names (`system`, `global`, `project`, `workspace-member`,
  `environment-file`, `user-override`).
- Add `SourceSelection` (`Discover | Explicit | Skip`) for each source.
- Make list order the merge order. Each source has a display priority, and the
  builder raises an error when priorities decrease along the list.
- Add key filters for each source (`exclude`), with an optional `KeyRemoved`
  warning in the source report.
- Add format parsers, each in its own package: TOML, YAML (with an optional
  Morphir strict profile), JSON (through `moonbitlang/x/json5`), JSON5, and Ion.
  The builder is the format registry that the conventions change reads.
- Add a pure merge. The Morphir merge rules are the default. A `MergePolicy` can
  select list append or list merge-by-key for a source or a key path. A null
  overlay value does not change the base value.
- Add secret references as indivisible leaves, lazy resolution through a
  host-supplied `SecretResolver`, and display redaction.
- Add provenance for each winning leaf (a never-empty array of origins), a
  `SourceReport` for each source, and a typed ambiguity error when one location
  has more than one candidate file.
- Add one typed `ConfigError` suberror that holds every configuration case of the
  core, conventions, and binding changes, and declare `BindFailure` for binding.
- Add pure helpers for `config get`, `config show`, and `config path`: render,
  redact, and explain the origin of a value.
- Add a source-provider entry point on the builder, so conventions discovery runs
  inside the pure load, and a load context that carries the file tree, `Platform`,
  the process variables, the base directory, and the registered formats.
- Add the file snapshot `FileTree` and the pure load protocol
  `LoadStep = Need(Array[FileRequest]) | Done(T)`, with
  `@config.load(builder, tree)` on all targets.
- Add the host adapter package `config/host`: `load(builder)` drives the request
  loop on native (through `moonbitlang/async`) and on js (through a TypeScript
  adapter over `node:fs`, bundled with Bun). Environment variables and the working
  directory come from `moonbitlang/core/env`. wasm and wasm-gc take an injected
  `FileTree`.
- Support Windows from the first story: a windows-latest CI leg, and paths shown
  with `/` on every platform.

## Out of scope

- Discovery of configuration files, file-layout conventions, XDG and platform
  directories, workspaces, and environment names. The change
  `add-configuration-conventions` owns them. This change supplies only what they
  use: the `Discover` selection value, the candidate-ambiguity rule, the
  source-provider entry point, `Platform` in the load context, `FileTree`, and the
  `config/host` adapter.
- Binding of configuration to typed values (`bind`, `Options[T]`, `Validate`,
  `FromConfig`). The change `add-configuration-binding` owns them.
- The host, the lifecycle, CLI commands, exit codes, and the argparse adapter.
  The change `add-host-lifecycle` owns them. This change supplies only pure
  helpers that those commands call.
- File, command, and keyring secret backends. This change defines the
  resolver interface and an environment resolver over explicit variables.
- Reload on file change, explicit unset of a key, .NET index-based list merge,
  a DI container, a logging abstraction, and a CLI parser.
- Ion binary input. This change reads Ion text only.

## Capabilities

### New Capabilities

- `configuration-core`: the configuration value tree, key paths, typed sources,
  format parsers, merge rules and policies, secret references, provenance,
  source reports, typed errors, and the pure helpers for get, show, and path.

### Modified Capabilities

None.

## Impact

- New packages in module `moonrockz/moon-lander` (`pkgs/lander`):
  `config` (`@config`), `config/formats/toml`, `config/formats/yaml`,
  `config/formats/json5`, `config/formats/ion`, and `config/host` (native and js).
- New dependencies of `pkgs/lander`: `moonrockz/ion@0.6.0`,
  `moonbit-community/toml@0.5.0`, `moonbit-community/yaml@0.0.8` (these are
  already in the workspace through `pkgs/notebooks`), `moonbitlang/x` for
  `json5`, and `moonbitlang/async` for the native host adapter.
- New TypeScript source for the js adapter in `pkgs/lander/adapters/node/`. The
  `add-host-lifecycle` change adds the js console lifetime to the same adapter.
- Tooling: Bun pinned in `.config/mise/config.toml`, a moonx task script that
  builds the TypeScript adapter, and a narrow AGENTS.md exception for that adapter.
- CI: a windows-latest leg that builds and tests native and js.
- New acceptance suites in the unpublished `tests/` module.
- The changes `add-configuration-conventions`, `add-configuration-binding`, and
  `add-host-lifecycle` depend on this change.
- No current public API changes. No breaking changes.

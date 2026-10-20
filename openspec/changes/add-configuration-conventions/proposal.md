# Proposal: Add configuration conventions

## Why

The configuration core (change `add-configuration-core`) merges sources, but each
application must still find its files. Command-line tools use the same patterns
again and again: a system directory, an XDG user directory, an application home,
walk-up discovery from the working directory, `.config/<app>/` folders, workspaces
with members, and personal `*.user.*` overrides. finos/morphir-moonbit has these rules
hard-coded for Morphir, and it has known faults: an ancestor configuration leaks into
temporary test roots (bead o6vm.10), YAML files are found but cannot load, and
discovery is mixed with file I/O. Moon-Lander must supply these patterns as generic,
reusable parts so that Morphir becomes one preset and other applications get the same
behavior with no copied code.

## What Changes

- Add the package `moonrockz/moon-lander/config/conventions`. It supplies reusable
  convention parts that produce ordered `ConfigSource` values for the core. The
  application adds them with `|> @conventions.add(@conventions.app_dirs("acme"))`:
  - A system directory (`/etc/<app>`, `%PROGRAMDATA%/<app>`).
  - A global user directory: `$XDG_CONFIG_HOME` only when absolute, else the
    platform directory (`~/.config`, `~/Library/Application Support`, `%APPDATA%`).
  - An application home: `~/.<app>`, which `$<PREFIX>_HOME` replaces.
  - Three candidate layouts per location: `<app>.*`, `.<app>/<app>.*` and
    `.config/<app>/config.*`.
  - Searched extensions that come from the formats the builder registers.
  - Adjacent `*.user.*` overrides.
  - Ambiguity detection when more than one candidate exists at one location. It
    raises the core error `ConfigError::Ambiguous`.
  - An optional legacy fallback file.
- Add walk-up root discovery with an explicit stop boundary and an isolated mode.
- Add workspace and member selection with `*` and `**` globs, confinement rules,
  an enclosing-workspace search, explicit project selection, and key filters for
  member layers and inherited layers. The filters use the core `exclude` operation.
- Add environments in the .NET style. The environment name is optional. Its sources
  are the name from the host, then `<PREFIX>_ENVIRONMENT`, then a default. Environment
  files sit next to each primary. Each application must opt in.
- Take the host inputs as plain values (`DiscoveryOptions`: environment name, explicit
  configuration file, isolated mode, project selector). Hosting parses the arguments.
  Conventions never reads them.
- Run discovery as a pure function over the core `FileTree` and the core `LoadStep`
  protocol. The core `config/host` package reads the file system on native and js.
  wasm and wasm-gc hosts give a `FileTree`.
- Support Windows fully. Reports and errors show paths with `/` on every platform.
- Add a Morphir preset as an acceptance fixture in the unpublished `tests/` module.
  It reproduces Morphir exactly. Port the discovery, precedence, member and ambiguity
  cases of Morphir's `config.feature` as acceptance tests.

## Capabilities

### New Capabilities

- `configuration-conventions`: Reusable rules that find configuration files and
  workspace members, select environments, and turn the results into ordered
  configuration sources with reports. The rules are pure over a file-tree snapshot.

### Modified Capabilities

None. This change depends on `add-configuration-core`. It uses the shared names
`ConfigSource`, `SourceSelection`, `SourceKind`, `FileRole`, `SourceReport`,
`ConfigWarning`, `Origin`, `FileTree`, `FileRequest`, `LoadStep` and `ConfigError`. It
does not change the core merge, format or file I/O behavior.

## Impact

- New package `moonrockz/moon-lander/config/conventions` (pure, all four targets). It
  depends on `@config` only. Format packages come in through the builder registry.
- No new host package and no new I/O dependency. Discovery uses the core
  `config/host` adapter on native and js.
- The native and js tests of this change also run on the windows-latest CI leg that
  `add-configuration-core` adds.
- New acceptance suite and Morphir preset fixture in `tests/`.
- finos/morphir-moonbit can replace `pkgs/morphir-host/configuration.mbt` and the
  discovery parts of `pkgs/morphir-engine/workspace/workspace.mbt` with a preset. It
  keeps its own production copy of that preset.

## Out of scope

- Merge rules, file formats, value types, provenance, key-filter application, secret
  resolution, the file snapshot, the load protocol and file I/O. The core change owns
  them.
- Binding to typed objects (change `add-configuration-binding`).
- The host lifecycle, `HostEnvironment` checks such as `is_development()`, the
  `@hosting.default_environment` builder step, argument parsing, the `--environment`,
  `--config` and `--isolated` flags, usage errors and the reserved names
  `<PREFIX>_ENVIRONMENT` and `<PREFIX>_HOME` (change `add-host-lifecycle`). This change
  only supplies the resolved environment name.
- The `config get`, `config show` and `config path` commands. This change supplies the
  source reports that they use.
- `XDG_CONFIG_DIRS`, reload on file change and file watching.
- Morphir's translation of the legacy `morphir.json` manifest and the legacy
  `morphir-workspace.json` file. morphir-moonbit owns them.
- A production Morphir preset in a published package.

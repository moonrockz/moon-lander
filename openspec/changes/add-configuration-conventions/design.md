# Design: Add configuration conventions

## Context

See proposal.md for the reason for this change. The requirements are in
`specs/configuration-conventions/spec.md`.

This change depends on `add-configuration-core`. The core owns the value tree, formats
and the format registry, merge, provenance, key filters, the environment-variable
source, the file snapshot, the load protocol, the host adapters and the shared types
`ConfigSource`, `SourceSelection[T]` (`Discover | Explicit(T) | Skip`), `SourceKind`,
`FileRole`, `SourceReport`, `ConfigWarning`, `Origin`, `FileTree`, `FileRequest`,
`LoadStep[T]` and `ConfigError`. This design does not specify merge, format or file I/O
behavior. It only decides which files become sources, in which order, with which roles,
priorities and reports.

Labels in this document:

- **Owner**: the project owner made the decision. O-items refer to the owner answers
  of 2026-10-20.
- **Call**: the designer made the decision. The owner has not rejected it. R-items
  refer to the reconciliation calls of 2026-10-20.
- **Call (this change)**: a decision made while this change was written. The brief and
  the reconciliation calls do not cover it. The owner must review it.
- **Owner (2026-10-20)**: a later owner decision of 2026-10-20: the local override
  layer (D17) and one variable set and one working directory for each run (D6, D12).

### Current state that this design replaces

- finos/morphir-moonbit `pkgs/morphir-host/configuration.mbt` finds system and global
  files with hard-coded Morphir paths. It checks `APPDATA` before `XDG_CONFIG_HOME` on
  every platform. It finds YAML files but cannot load them.
- `pkgs/morphir-engine/workspace/workspace.mbt` discovers workspaces over a `Tree`
  snapshot (`files`, `directories`). This is the pure-over-snapshot model that this
  design keeps (morphir-moonbit ADR 0002: a synchronous core, async hosts prepare
  snapshots). Its `locate` function walks up with no stop boundary (bead o6vm.10).
- `Document::shared()` removes the `project` and `workspace` tables from inherited
  layers. Owner: keep this filtering.
- The Rust loader in finos/morphir (`morphir-devkit/src/config/{discovery,loader,
  members,sources}.rs`) and the normative document `morphir-toml-merge-rules.md` define
  the behavior that the Morphir preset must reproduce.

## Goals / Non-Goals

**Goals:**

- Reusable parts that an application composes into its convention set with pipelines
  and labelled arguments.
- Discovery that is pure, synchronous and equal on wasm, wasm-gc, js and native.
- Full Windows support in the first stories.
- A Morphir preset, as a test fixture, that passes the ported Morphir acceptance cases.
- Reports that let a later `config path` command show every candidate and status.

**Non-Goals:**

- No file watching or reload.
- No search of `XDG_CONFIG_DIRS`.
- No file I/O, no host adapter and no argument parsing in this change.
- No translation of legacy file contents. The application gives a decoder.
- No `is_development()` checks or other `HostEnvironment` behavior. The host-lifecycle
  change owns them.

## Decisions

### D1. Generic parts, with Morphir as a preset (Owner)

The framework is generic. Morphir's layout is one preset made from public parts. No
Morphir rule is hard-coded in `config/conventions`. The preset lives in the
unpublished `tests/` module as an acceptance fixture (Call). morphir-moonbit owns its
production copy (Call).

### D2. Convention parts and the pipeline (Owner: honor `.config/`, XDG and build-tool patterns; Call (R1): pipeline name; Call (this change): the list of parts)

The package `moonrockz/moon-lander/config/conventions` (`@conventions`) gives one
immutable `Conventions` value and these parts:

| Part | Result |
| --- | --- |
| `base(name, prefix?, display?)` | An empty convention set with the app name, the variable prefix and the display name |
| `app_dirs(name, prefix?, display?)` | `base` plus the standard parts below: system, user configuration directory, application home, three layouts, local overrides, user overrides, walk-up |
| `system_dir()` | System candidates (`/etc/<app>`, `%PROGRAMDATA%/<app>`) |
| `user_config_dir()` | XDG, macOS and Windows configuration-directory candidates |
| `app_home()` | `~/.<app>` or `$<PREFIX>_HOME` candidates |
| `layouts()` | The three primary layouts |
| `local_overrides()` | `*.local.*` candidates next to each primary (D17) |
| `user_overrides()` | `*.user.*` candidates next to each primary |
| `without(part)` | Removes one standard part |
| `legacy(name, format~, decode~)` | An optional legacy fallback file, its format and its decoder |
| `boundary(dir)` | The walk-up stop boundary |
| `workspace(members~, exclude~, default_member~, project_name~)` | Workspace key paths and member selection |
| `member_scope_keys(paths)`, `inherited_filter(keys)` | Key filters (D9) |
| `environments(default?)` | Environment opt-in (D10) |
| `add(builder, conventions, options?)` | Adds the convention set to a core builder |

The application pipeline (Call (R1)):

```moonbit
let builder = @config.builder()
  |> @config.defaults(Defaults::default().to_json())
  |> @config.format(@toml.format)
  |> @config.format(@yaml.format)
  |> @conventions.add(@conventions.app_dirs("acme"), options~)
  |> @config.env(prefix="ACME", reserved=["ACME_HOME"])
```

A sketch only (not compiled). Hosting builds this pipeline for an application (D10).

- Call (R8): the application name is given one time, in `@lander.cli(name, args)`.
  Hosting gives the name and the prefix to `app_dirs`. Without hosting, `prefix`
  defaults to the name in upper case with `-` changed to `_`, the same rule that
  hosting uses (Call (this change)).
- Call (this change): `display` defaults to the name. The Morphir preset gives
  `Morphir`.
- Owner (2026-10-20): under the batteries-included `@lander` entry of
  `add-host-lifecycle`, `app_dirs(name, prefix~)` with the host name and prefix is on
  by default. `|> @lander.conventions(fn(c) { ... })` changes or replaces it. The bare
  `@hosting.builder` and the Morphir preset add their convention set explicitly
  (host-lifecycle D15).
- Call (this change): `app_dirs` is the standard set, and `base` with single parts gives
  full control. Alternative: one fixed `standard(app)` function with no way to remove a
  part. Rejected because each application needs to drop or add parts.

### D3. Searched extensions come from the registered formats (Call (R11))

Discovery searches the extensions of the formats that the builder registers, in
registration order and in the order of each format's extensions. The order sets only the
order of candidates in reports. It never selects one file over another. There is no
separate extension list, so an application never searches for a format that it cannot
parse. This fixes the morphir-moonbit fault where YAML files are found but cannot load.

A preset chooses its formats by the formats it registers. Call (this change): the core
YAML format registers `.yaml` and `.yml`. Morphir searches only `.yaml`, so the Morphir
preset registers a copy of the YAML format whose extension list is `["yaml"]`.

### D4. Ambiguity at one location is an error (Call (R2))

Discovery detects ambiguity, including the skip rules for ancestors (D7). Two or more
existing candidates for one source at one location fail with the core error
`ConfigError::Ambiguous(display~, location~, candidates~)`. `display` is the display
name of the convention set, `location` is the directory, and `candidates` lists every
existing path in report order. The core renders the message
`Ambiguous <display> configuration; found: <paths>`, which keeps the Morphir message
`Ambiguous Morphir configuration`.

### D5. Walk-up, stop boundary and isolated mode (Owner: walk-up; Call: boundary and isolated mode; Call (R7): isolated input)

- Walk-up checks each directory from the start directory to the boundary, inclusive.
  The nearest directory with a primary or legacy file is the root. There is no `.git`
  stop, as in Morphir.
- The boundary is an explicit input with no default. Without a boundary, walk-up goes
  to the file-system root. Tests set the boundary to their temporary root. This fixes
  bead o6vm.10.
- Call (this change): a start directory outside the boundary raises
  `ConfigError::OutsideBoundary` with both directories. A silent empty result would
  hide a test setup fault.
- Call (this change): there is no environment variable for the boundary. An application
  can add one. Alternative: a `GIT_CEILING_DIRECTORIES`-style variable. Rejected for now
  because it adds a second, hidden input.
- Isolated mode copies Morphir's `--isolated`. It sets the system, global,
  local-override and user-override sources to `Skip`. Call (this change): isolated
  mode also skips local overrides, because git ignores them and they are not part of
  the shared project configuration. Morphir has no local layer. Project, member and environment-variable sources
  stay. Isolated mode does not set the boundary, because Morphir's isolated mode does
  not (Call (this change)). An application can set both.
- Call (R7): conventions never reads the arguments. Hosting parses `--isolated` and
  gives the value in `DiscoveryOptions` (D10).

### D6. Global user directory and application home (Call; Owner (O3): Windows directories)

- Owner (2026-10-20): every directory variable (`HOME`, `XDG_CONFIG_HOME`, `APPDATA`,
  `PROGRAMDATA`, `USERPROFILE`, `<PREFIX>_HOME`) comes from the one variable set of
  the run, which the core load context gives as `env_vars`. Discovery never reads the
  process environment. A test gives `HOME` and `XDG_CONFIG_HOME` in that set and gets
  the same candidates on every target.

- Linux and macOS: `$XDG_CONFIG_HOME` only when non-empty and absolute; else
  `$HOME/.config` (Linux) or `$HOME/Library/Application Support` (macOS).
- Windows (Owner (O3)): the directories come from the variables `APPDATA`,
  `PROGRAMDATA` and `USERPROFILE`. The configuration directory is `APPDATA`.
  `XDG_CONFIG_HOME` has no effect on Windows. When a variable is unset, its candidate
  is absent, except `PROGRAMDATA`, which falls back to `C:/ProgramData`, as Morphir
  specifies (Call). Windows Known Folder API calls are not made.
- Application home: `$<PREFIX>_HOME` when non-empty; else `<home>/.<app>`, with `<home>`
  from `HOME`, or from `USERPROFILE` on Windows.
- All global candidates are alternatives at one priority. More than one is an
  ambiguity error.
- Call (this change): the platform is an explicit input value `Platform` (`Linux`,
  `MacOs`, `Windows`). Tests give it directly, so the macOS and Windows rules run on
  every target. Core's `config/host` detects it on native and js. wasm and wasm-gc hosts
  give it. This change asks the core load context to carry `Platform` (see Risks).
- Call (this change): the global file name in both directories is `<app>.<ext>`, as in
  Morphir (`~/.config/morphir/morphir.toml`).

### D7. Workspaces and members (Owner: workspace/project pattern; Call: globs; Call (R11): ancestor parse)

- After walk-up finds a root, the enclosing-workspace search goes from the root's parent
  to the boundary. It passes over unreadable, ambiguous and non-workspace files, as the
  Morphir Rust loader does. The first workspace whose patterns select the root wins.
- Call (R11): discovery parses ancestor candidates through the core parse and merge,
  with the formats that the builder registers, to find the workspace keys.
  `config/conventions` depends on `@config` only. Format packages come in through the
  registry.
- Globs: `*` matches in one segment; `**` matches zero or more segments. Other
  characters are literal (Call (this change)). morphir-moonbit also accepts `?`, `[` and
  `{}`; the Morphir Rust loader does not. The preset follows Morphir.
- Confinement: absolute entries, drive prefixes, backslashes and `..` segments are
  skipped with a warning, as in the Rust loader (morphir-moonbit fails instead). The
  root is never its own member.
- Selection order: enclosing member, then default member, then the only member. An
  explicit selector matches a path first, then a name. A selector with no match raises
  `ConfigError::UnknownProject`. A name that matches more than one project raises
  `ConfigError::AmbiguousProject`.
- The application gives the key paths for members, exclude, default member and project
  name. The conventions read them from the merged value of defaults, system, global and
  the workspace primary, before member and override layers load. This is what the Rust
  loader decodes as `root_config` (Call (this change)). morphir-moonbit reads them from
  a value that also has user overrides and environment variables; the preset follows
  the Rust loader.

### D8. Layer order, roles and priorities (Call (R4, R6), from Morphir)

List order is merge order. Each source also has an `Int` priority for display. The core
builder raises `ConfigError::SourceOrder` when priorities decrease along the list.
Reports list sources in merge order. Conventions gives these values, so generic
applications get the same numbers as Morphir:

| Priority | Source | `SourceKind` | Notes |
| --- | --- | --- | --- |
| 0 | Defaults | `Defaults` | Core |
| 100 | System | `File(System)` | |
| 200 | Global user | `File(Global)` | One file across all candidates |
| 300 | Project or workspace primary | `File(Workspace)`, `File(Legacy)` | `File(Explicit)` for `Explicit(path)` |
| 350 | Selected member primary | `File(Member)` | |
| 375 | Environment files | `File(EnvironmentFile)` | Workspace, then member |
| 390 | Local overrides | `File(LocalOverride)` | Workspace, then member (D17) |
| 400 | User overrides | `File(UserOverride)` | Workspace, then member |
| 600 | Environment variables | `Environment` | Core source |
| 700 | Overrides (argparse) | `Overrides` | Hosting |

The 375 value puts environment files between primaries and user overrides. That is the
Owner-accepted order "primary, environment file, `*.user.*`". The 390 value puts local
overrides between environment files and user overrides (Owner (2026-10-20)). With
environments and local overrides off, no 375 or 390 source exists, so the Morphir
preset keeps exactly Morphir's priorities.

Report and `path_json` kind names come from the core mapping of `FileRole` to Morphir's
names. Conventions only assigns the role.

### D9. Key filters (Owner: keep `shared()`; Call (R9): declared through core `exclude`)

Conventions declares the filters on the sources it makes with the core operation
`exclude(paths, warn~ : Bool)`. The core applies it after parse, inside the build. When
`warn` is true and a removed key existed, the core adds
`ConfigWarning::KeyRemoved(path, origin)` to `SourceReport.warnings`. Removed values
have no provenance.

- Member-scope keys, with `warn=true`: key paths that only the workspace can set. They
  are removed from member primaries, member environment files, member local overrides
  and member user overrides. Morphir uses `workspace.out_dir` (Rust loader
  `LayerScope::Member`).
- Inherited filter, with `warn=false`: top-level keys that a layer does not pass to
  scopes it does not own. When a member is selected, the filter removes them from the
  system, global, workspace primary, workspace environment-file, workspace
  local-override and workspace user-override layers. This is morphir-moonbit
  `shared()` with `["project", "workspace"]`.
- The Morphir preset uses both. The Rust loader has only the member-scope filter. The
  inherited filter changes no ported `config.feature` case. It is recorded here as a
  known difference from the Rust loader.

### D10. Environments and discovery options (Owner: .NET style; Call: details the owner accepted; Call (R3, R7, R8): inputs from hosting)

- Environments are opt-in for each application. `|> @conventions.environments()`
  enables them. `|> @hosting.default_environment(name)` sets a default and also
  enables them (Call (R8)). The Morphir preset leaves them off.
- Owner (2026-10-20): the batteries-included `@lander` entry of `add-host-lifecycle`
  enables environments with no default, so environment files load only when the run
  has a name. `|> @lander.no_environments()` turns them off. Conventions itself keeps
  environments off until a caller enables them.
- The name is `Option[String]` with no default. The sources, from high to low: the
  name in `DiscoveryOptions` (hosting fills it from `--environment`),
  `<PREFIX>_ENVIRONMENT` from the variable set of the run, the default from
  `environments`.
  An empty variable counts as unset.
- Call (R7): hosting parses the arguments one time with argparse, before any file
  loads. Conventions never reads the arguments. It takes the results as plain input:

  ```moonbit
  pub(all) struct DiscoveryOptions {
    environment : String?                     // from --environment
    config : @config.SourceSelection[String]  // from --config: Explicit primary
    isolated : Bool                           // from --isolated
    project : String?                         // explicit project selector
  }
  ```

  Call: hosting fills `project` from its `--project <path|name>` flag (on under
  `@lander`, opt-in on the bare `@hosting.builder`). An
  application without hosting sets the field itself. All fields default to "not given".
- Call (R3): an empty `--environment` value is a hosting `UsageError`. Conventions
  raises no usage error.
- Environment files sit next to each project-tier primary: `<app>.<name>.<ext>` or
  `config.<name>.<ext>`. Exact-name match, no case folding.
- Call (this change): a name must be non-empty, must not contain `/`, `\`, `.` or a
  control character, and must not equal `user` in any case. `user` would make
  `<app>.user.<ext>` both an override and an environment file. Case-insensitive file
  systems make `User` the same file, so the check ignores case.
- Owner (2026-10-20): `local` is also a reserved name in any case, so
  `<app>.local.<ext>` is never an environment file. An invalid name raises
  `ConfigError::InvalidEnvironmentName` that names the source of the name.
- Call (R8): hosting adds `<PREFIX>_ENVIRONMENT` and `<PREFIX>_HOME` to the reserved
  names of the environment-variable source. Conventions does not change that source. An
  application that uses conventions without hosting gives the reserved names itself.
- Call (this change): environment files apply only to project-tier primaries (workspace
  and member). They do not apply to system, global, legacy or non-standard explicit
  files. .NET applies `appsettings.{env}.json` only in the content root, and a
  machine-wide environment file has no clear use.
- Call (this change): an environment file alone does not mark a root.

### D11. Exact-name matching through directory listings (Call (this change))

macOS and Windows file systems are usually case-insensitive. A probe for
`acme.Production.toml` would find `acme.production.toml`. To get exact-name matching on
every system, discovery compares candidate names with the names in the `FileTree`
directory listings, not with existence probes. The core snapshot stores listings with
the real names.

### D12. Pure discovery over the core load protocol (Call (R1))

Discovery is a pure, synchronous function. It runs over the core `FileTree` and returns
the core `LoadStep`:

- Inputs: the `FileTree`, `Platform`, the variable set (`env_vars`) and the working
  directory (`working_dir`) from the core load context, the registered formats (from
  the builder), and the `Conventions` value with its `DiscoveryOptions`.
- Owner (2026-10-20): walk-up starts at the working directory of the run. This
  document calls it the start directory.
- `Done(result)`: ordered `ConfigSource` values with their filters, `SourceReport`
  values, warnings, the environment name, the workspace root and the member root.
- `Need(requests)`: the `FileRequest` values (directory listings and file contents)
  that the tree does not contain. A complete tree never gives `Need`.

`@conventions.add` puts the convention set into the core builder. The core calls
discovery during the pure `@config.load(builder, tree) -> LoadStep[Config]`, and a
`Need` from discovery passes out of `@config.load`. The async
`@config/host.load(builder) -> Config` on native and js answers the requests and calls
again. Each round adds all requests that one pass finds. The number of rounds is bounded
by the walk-up depth plus the member expansion depth.

Alternative: read the full tree first. Rejected because walk-up can reach the
file-system root.

Call (this change, tracer bullet): walk-up asks for one listing per round, nearest
first, and stops at the root it finds, so it never lists parents above the project
root. `add(builder, conventions)` takes no options until a part reads them; the
group that first reads a `DiscoveryOptions` field adds `options?`. Discovery with
no working directory, or a relative one, gives a skipped project source and a
`Note` warning: the core would join a relative candidate to the working directory
again, and a relative directory has no parents to walk to. With no
primary, the candidate list at the start directory reports `NotFound`.

### D13. No host package in this change (Call (R1); Owner (O2))

This change has no host package. File reading is in the core package
`moonrockz/moon-lander/config/host`, with per-target files:

| Target | File access | Variable set and working directory |
| --- | --- | --- |
| native | `moonbitlang/async` fs | The builder values; else `config/host` reads `moonbitlang/core/env` |
| js | The TypeScript adapter on `node:fs`, built with Bun (Owner (O2)) | The builder values; else `config/host` reads `moonbitlang/core/env` |
| wasm, wasm-gc | No adapter. The host gives a `FileTree` with `\|> @hosting.files(tree)` | The builder values |

This change tests discovery through that adapter on native and js, and through an
injected tree on wasm and wasm-gc. The AGENTS.md exception for the TypeScript adapter
belongs to the `config/host` js story in `add-configuration-core` (Call (R12)).

### D14. Paths and Windows (Owner (O3): full Windows support; Call (O3): `/` in all paths)

- Discovery uses one path form with `/` separators. An absolute path starts with `/`,
  a drive prefix (`C:/`), or a UNC prefix (`//server/share`).
- The core adapter converts `\` to `/` at the boundary for paths and listings, and
  converts back only for file-system calls. Discovery converts `\` to `/` in the
  path-valued variables that it reads on Windows (`APPDATA`, `PROGRAMDATA`,
  `USERPROFILE`, `XDG_CONFIG_HOME`, `<PREFIX>_HOME`) (Call (this change)).
- Reports and errors show paths with `/` on every platform, including Windows. This
  makes reports and tests equal across targets. The Rust loader shows native separators
  on Windows; this is a known display difference.
- Windows absolute checks accept a drive letter with a separator and a UNC prefix, as in
  the Rust `is_absolute_for`. A drive-relative path such as `C:foo` is not absolute.
- Member and workspace entries reject `\` on every platform, so a configuration file
  means the same thing on every system.
- Path comparison is exact. Discovery does not fold case on Windows or macOS.
- The windows-latest CI leg (a task in `add-configuration-core`, Call (R12)) runs the
  native and js tests of this change on Windows.

### D15. Legacy fallback (Call)

A legacy file is a root marker and a primary only when no primary candidate exists at
that location. It has no local override, no user override and no environment file. The application gives a
decoder from the parsed value to a layer, because the legacy format is application
specific. Call (this change): the legacy part takes its own `Format` value. That format
is not registered with the builder, so its extensions do not join the searched
extensions (D3). Without this, a registered JSON format would make `morphir.json` a
primary candidate. The Morphir preset fixture uses an identity decoder over JSON. morphir-moonbit
keeps its Elm-manifest translation and `morphir-workspace.json`.

### D16. Morphir preset and acceptance (Call)

The preset is in `tests/` and uses only public parts:

- app `morphir`, display `Morphir`, prefix `MORPHIR`;
- registered formats TOML (`.toml`) and YAML limited to `.yaml` (D3); the JSON5 format
  is given only to the legacy part (D15);
- system, global (XDG, macOS, Windows, `~/.morphir` or `$MORPHIR_HOME`), the three
  layouts, user overrides, legacy `morphir.json`, walk-up, workspace keys
  (`workspace.members`, `workspace.exclude`, `workspace.default_member`,
  `project.name`), member-scope key `workspace.out_dir`, inherited filter
  `["project", "workspace"]`;
- reserved environment names `MORPHIR_HOME` and `MORPHIR_LOG_DIR` given to the core
  environment source, because the fixture does not use hosting;
- environments off;
- local overrides off (`without` the local override part), because Morphir has no
  local layer (Owner (2026-10-20)).

Ported `config.feature` cases: dotted-key lookup after discovery; walk-up from
`src/nested`; explicit `--config ../configs/project.yaml` from `elsewhere` (given as
`DiscoveryOptions.config`); environment over project; source list order and statuses;
ambiguous `morphir.toml` and `morphir.yaml`; dot-config TOML and YAML; three adjacent
user overrides; member user override after workspace user override; primaries in two
layouts; sibling user override serializations. Added from the merge-rules document:
global ambiguity, `MORPHIR_HOME`, relative `XDG_CONFIG_HOME`, macOS and Windows
directories, `C:/ProgramData` fallback, legacy fallback, member selection and
confinement. Secret, redaction and CLI output cases stay with the core and
host-lifecycle changes.

The ported cases are a Gherkin file
`tests/config-conventions-acceptance/features/morphir.feature`, run with
`moonrockz/moonspec` as the notebook acceptance suites are (`js+native`). The same cases
also run as plain snapshot tests in `tests/config-conventions-laws` on all four targets,
so wasm and wasm-gc are covered (Call (this change)). A small subset runs over a real
temporary directory on native and js, also on Windows, to check discovery through the
core adapter.

### D17. Local overrides (Owner (2026-10-20); Call: part of `app_dirs`)

- A local override is for one checkout, and git ignores it. A user override is the
  preference of one person. Both sit next to the chosen primary.
- Candidates: `<app>.local.<ext>` next to a primary in the `<app>.<ext>` or
  `.<app>/<app>.<ext>` layout, and `config.local.<ext>` next to
  `.config/<app>/config.<ext>`. The extensions come from the registered formats, as
  for user overrides. More than one existing candidate for one primary is an
  ambiguity error.
- Role `File(LocalOverride)`, report name `local-override`, priority 390.
- Order for a workspace member: workspace local, member local, then workspace user,
  member user.
- Explicit primaries in a standard layout get local overrides. Legacy files and other
  explicit files do not.
- Call: `app_dirs` includes `local_overrides()`. `base` does not. The Morphir preset
  removes it, so the preset still reproduces Morphir exactly.

## Risks / Trade-offs

- [This change needs two core extension points: a builder entry that runs discovery
  during `@config.load`, and `Platform` in the load context] → Confirm both with
  `add-configuration-core` before group 1 starts.
- [The core YAML format also registers `.yml`] → The Morphir preset registers a YAML
  format limited to `.yaml` (D3). Other applications search `.yml` when they register
  the full YAML format.
- [The inherited filter differs from the Morphir Rust loader] → Record it (D9). Add an
  acceptance case that shows the morphir-moonbit behavior, so a change is visible.
- [Exact-name matching through listings costs one directory read per directory] →
  Walk-up reads at most three directories per level (the root, `.<app>`,
  `.config/<app>`). The cost is small for command-line tools.
- [Forward-slash reports on Windows look different from native paths] → Document it.
  An application can convert paths for display.
- [Request-loop rounds on deep trees] → Each round adds all requests that one pass finds.
  The number of rounds is bounded by the walk-up depth plus the member expansion depth.
- [Environment-name rules reject some names that .NET accepts, such as `Prod.EU`] → The
  rule protects file names. An application that needs dots can map names before use.

## Migration Plan

No released code changes. morphir-moonbit moves later:

1. Copy the preset from `tests/` into morphir-moonbit and add its legacy decoder.
2. Replace `configuration.mbt` and the discovery part of `workspace.mbt` with the
   preset. Keep `shared()` behavior through the inherited filter.
3. Set the boundary in its tests (closes bead o6vm.10).

Rollback: morphir-moonbit keeps its current code until its own tests pass on the preset.

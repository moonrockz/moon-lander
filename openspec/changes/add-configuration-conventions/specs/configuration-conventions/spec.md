# Spec Delta

## Purpose

Configuration conventions find an application's configuration files and workspace
members, select an optional environment, and turn the result into ordered
configuration sources with reports. The rules are generic, so one application
layout (for example Morphir) is a preset made from these parts.

## ADDED Requirements

### Requirement: Candidate layouts per location

A convention set SHALL name one application name `<app>`. At each discovery location
it SHALL look for primary candidates in three layouts: `<app>.<ext>`,
`.<app>/<app>.<ext>` and `.config/<app>/config.<ext>`, for each searched extension.
Matching SHALL use the exact file names that the `FileTree` directory listings hold.

#### Scenario: Root layout found
- **WHEN** the application is `acme`, the builder registers the TOML format, and the directory contains only `acme.toml`
- **THEN** discovery selects `acme.toml` as the primary at that location

#### Scenario: Dot-config layout found
- **WHEN** the application is `acme`, the builder registers the TOML format, and the directory contains only `.config/acme/config.toml`
- **THEN** discovery selects `.config/acme/config.toml` as the primary at that location

#### Scenario: Hidden directory layout found
- **WHEN** the application is `acme`, the builder registers the YAML format, and the directory contains only `.acme/acme.yaml`
- **THEN** discovery selects `.acme/acme.yaml` as the primary at that location

### Requirement: Searched extensions come from registered formats

Discovery SHALL search the extensions of the formats that the builder registers, and
no other extension. The order of registration SHALL only set the order of candidates
in reports. It SHALL NOT select one file over another.

#### Scenario: Unregistered extension ignored
- **WHEN** the builder registers the TOML format and a YAML format limited to `.yaml`, and the directory contains only `acme.json`
- **THEN** discovery finds no primary at that location

#### Scenario: Registration order does not choose
- **WHEN** the builder registers the TOML format and a YAML format limited to `.yaml`, and the directory contains `acme.toml` and `acme.yaml`
- **THEN** discovery fails with an ambiguity error and does not select `acme.toml`

### Requirement: Ambiguity at one location is an error

When more than one candidate exists for one source at one location, discovery SHALL
raise `ConfigError::Ambiguous` with the display name of the convention set, the
location and every existing candidate path. Discovery SHALL NOT merge the files or
choose one.

#### Scenario: Two serializations of one layout
- **WHEN** the directory contains `acme.toml` and `acme.yaml`
- **THEN** discovery fails with an ambiguity error that names both paths

#### Scenario: Primaries in two layouts
- **WHEN** the directory contains `acme.toml` and `.acme/acme.toml`
- **THEN** discovery fails with an ambiguity error that names both paths

### Requirement: Legacy fallback candidate

A convention set MAY name one legacy fallback file name with its own format. The legacy
format SHALL NOT add to the searched extensions. Discovery SHALL use the legacy file at
a location only when no primary candidate exists at that location.
A legacy file SHALL count as a root marker. A legacy file SHALL NOT have an adjacent
user override or environment file.

#### Scenario: Legacy file used when no primary exists
- **WHEN** the legacy name is `acme.json` and the directory contains only `acme.json`
- **THEN** discovery selects `acme.json` as the primary at that location

#### Scenario: Primary wins over legacy file
- **WHEN** the legacy name is `acme.json` and the directory contains `acme.json` and `acme.toml`
- **THEN** discovery selects `acme.toml` and does not report an ambiguity error

### Requirement: Walk-up root discovery

Discovery SHALL start at the start directory and move to each parent directory. The
first directory that contains a primary candidate or a legacy file SHALL be the
project root. Discovery SHALL NOT stop at a version-control directory such as `.git`.

#### Scenario: Configuration found from a nested directory
- **WHEN** `acme.toml` is in the root and the start directory is `src/nested`
- **THEN** discovery selects the root `acme.toml` as the project primary

#### Scenario: Nearest configuration wins
- **WHEN** `acme.toml` is in the root and in `sub`, and the start directory is `sub/deep`
- **THEN** discovery selects `sub/acme.toml` as the project primary

#### Scenario: Ambiguity in the nearest directory stops discovery
- **WHEN** `sub` contains `acme.toml` and `acme.yaml` and the start directory is `sub`
- **THEN** discovery fails with an ambiguity error and does not continue to the parent

### Requirement: Explicit stop boundary

Discovery SHALL take an optional stop boundary directory. The walk-up SHALL examine the
boundary directory and SHALL NOT examine its ancestors. The enclosing-workspace search
SHALL obey the same boundary. When there is no boundary, the walk-up SHALL continue to
the file-system root.

#### Scenario: Ancestor configuration above the boundary is ignored
- **WHEN** `/tmp/acme.toml` exists, the boundary is `/tmp/case`, and the start directory is `/tmp/case/src`
- **THEN** discovery finds no project primary

#### Scenario: Configuration at the boundary is found
- **WHEN** `/tmp/case/acme.toml` exists, the boundary is `/tmp/case`, and the start directory is `/tmp/case/src`
- **THEN** discovery selects `/tmp/case/acme.toml` as the project primary

#### Scenario: Start directory outside the boundary
- **WHEN** the boundary is `/tmp/case` and the start directory is `/srv/other`
- **THEN** discovery raises `ConfigError::OutsideBoundary` that names both directories

### Requirement: Isolated mode

Isolated mode SHALL be on when the `isolated` value of `DiscoveryOptions` is true. In
isolated mode, the convention sources for the system directory, the global user
directory and adjacent user overrides SHALL have the selection `Skip`. Project,
workspace, member and environment-variable sources SHALL stay unchanged. Their reports
SHALL show the status skipped.

#### Scenario: Isolated mode skips user and machine files
- **WHEN** a global user file, a system file and `acme.user.toml` exist, and isolated mode is on
- **THEN** only the defaults, the project primary and the environment-variable source contribute values

#### Scenario: Isolated mode keeps environment variables
- **WHEN** `acme.toml` sets `ir.format_version = 3`, `ACME_IR__FORMAT_VERSION=4` is set, and isolated mode is on
- **THEN** the effective value of `ir.format_version` is 4

### Requirement: System directory

The system source SHALL look in `/etc/<app>` on Linux and macOS. On Windows it SHALL
look in `%PROGRAMDATA%/<app>`, and use `C:/ProgramData/<app>` when `PROGRAMDATA` is not
set. The candidates SHALL be `<app>.<ext>` for each searched extension.

#### Scenario: Linux system file
- **WHEN** the platform is Linux and `/etc/acme/acme.toml` exists
- **THEN** the system source loads `/etc/acme/acme.toml`

#### Scenario: Windows system directory fallback
- **WHEN** the platform is Windows and `PROGRAMDATA` is not set
- **THEN** the system candidates are in `C:/ProgramData/acme`

### Requirement: Global user configuration directory

On Linux and macOS, the configuration directory SHALL be `$XDG_CONFIG_HOME` when it is
a non-empty absolute path. Otherwise it SHALL be `$HOME/.config` on Linux and
`$HOME/Library/Application Support` on macOS. On Windows it SHALL be `%APPDATA%`, and
`XDG_CONFIG_HOME` SHALL have no effect. `XDG_CONFIG_DIRS` SHALL have no effect.

#### Scenario: Absolute XDG directory used
- **WHEN** the platform is Linux and `XDG_CONFIG_HOME=/srv/alice/config`
- **THEN** a global candidate is `/srv/alice/config/acme/acme.yaml`

#### Scenario: Relative XDG directory ignored
- **WHEN** the platform is Linux, `HOME=/home/alice` and `XDG_CONFIG_HOME=config`
- **THEN** a global candidate is `/home/alice/.config/acme/acme.yaml`

#### Scenario: macOS default directory
- **WHEN** the platform is macOS, `HOME=/Users/Alice` and `XDG_CONFIG_HOME` is not set
- **THEN** a global candidate is `/Users/Alice/Library/Application Support/acme/acme.yaml`

#### Scenario: Windows roaming directory
- **WHEN** the platform is Windows and `APPDATA=D:\Profiles\Alice\Roaming`
- **THEN** a global candidate is `D:/Profiles/Alice/Roaming/acme/acme.yaml`

### Requirement: Application home directory

The global source SHALL also look in the application home. The application home SHALL
be `$<PREFIX>_HOME` when that variable is non-empty. Otherwise it SHALL be `.<app>` in
the user home (`$HOME`, or `%USERPROFILE%` on Windows). `<PREFIX>` is the variable
prefix of the convention set. The candidates SHALL be `<app>.<ext>` in that directory.

#### Scenario: Default application home
- **WHEN** `HOME=/home/alice` and `ACME_HOME` is not set
- **THEN** a global candidate is `/home/alice/.acme/acme.toml`

#### Scenario: Relocated application home
- **WHEN** `ACME_HOME=/tmp/acme-home`
- **THEN** a global candidate is `/tmp/acme-home/acme.toml` and no candidate is in `$HOME/.acme`

#### Scenario: Windows user home
- **WHEN** the platform is Windows, `USERPROFILE=C:\Users\Alice` and `ACME_HOME` is not set
- **THEN** a global candidate is `C:/Users/Alice/.acme/acme.toml`

#### Scenario: Empty home variable is unset
- **WHEN** `ACME_HOME` is set to an empty value and `HOME=/home/alice`
- **THEN** a global candidate is `/home/alice/.acme/acme.toml`

### Requirement: One global user configuration

The configuration-directory candidates and the application-home candidates SHALL be
alternatives at one priority. When more than one of them exists, discovery SHALL fail
with an ambiguity error that names every existing candidate.

#### Scenario: Two global files
- **WHEN** `$HOME/.config/acme/acme.toml` and `$HOME/.acme/acme.toml` both exist
- **THEN** discovery fails with an ambiguity error that names both paths

### Requirement: Adjacent user overrides

For a primary in the layout `<app>.<ext>` or `.<app>/<app>.<ext>`, the user override
candidates SHALL be `<app>.user.<ext>` in the same directory. For
`.config/<app>/config.<ext>` they SHALL be `config.user.<ext>` in the same directory.
More than one existing override for one primary SHALL be an ambiguity error.

#### Scenario: Adjacent override wins
- **WHEN** `acme.toml` sets `ui.theme = "shared"` and `acme.user.toml` sets `ui.theme = "personal"`
- **THEN** the effective value of `ui.theme` is `personal`

#### Scenario: Dot-config override wins
- **WHEN** `.config/acme/config.toml` sets `ui.theme = "shared"` and `.config/acme/config.user.toml` sets `ui.theme = "personal"`
- **THEN** the effective value of `ui.theme` is `personal`

#### Scenario: Sibling override serializations
- **WHEN** `acme.toml`, `acme.user.toml` and `acme.user.yaml` exist
- **THEN** discovery fails with an ambiguity error that names both override files

### Requirement: Explicit primary file

When the `config` value of `DiscoveryOptions` is `Explicit(path)`, discovery SHALL use that
file and SHALL NOT walk up for a root. The enclosing-workspace search SHALL still apply.
When the file path matches a standard layout, the override and environment-file rules
SHALL apply. Other explicit files SHALL have no implicit override or environment file.

#### Scenario: Explicit file from another directory
- **WHEN** the start directory is `elsewhere` and the explicit path is `../configs/project.yaml`
- **THEN** the project source loads `configs/project.yaml` and its report path ends with `configs/project.yaml`

#### Scenario: Explicit non-standard file has no override
- **WHEN** the explicit path is `configs/project.yaml` and `configs/project.user.yaml` exists
- **THEN** no user override source loads

### Requirement: Enclosing workspace discovery

After walk-up finds a project root, discovery SHALL search from the parent of that root
up to the boundary. It SHALL stop at the first configuration that declares a workspace
whose member and exclude patterns select the project root. That configuration SHALL be
the workspace primary and the found file SHALL be the member primary. Unreadable,
ambiguous or non-workspace configurations SHALL be passed over.

#### Scenario: Member found from inside the member
- **WHEN** `acme.toml` declares members `["packages/*"]`, `packages/billing/acme.toml` exists, and the start directory is `packages/billing/src`
- **THEN** the root `acme.toml` is the workspace primary and `packages/billing/acme.toml` is the member primary

#### Scenario: Ambiguous ancestor is passed over
- **WHEN** an ancestor of the project root contains `acme.toml` and `acme.yaml`
- **THEN** discovery does not fail and continues to the next ancestor

#### Scenario: Excluded member stays standalone
- **WHEN** the workspace declares members `["packages/*"]` and exclude `["packages/legacy"]`, and the project root is `packages/legacy`
- **THEN** `packages/legacy/acme.toml` is the project primary and no workspace primary loads

### Requirement: Member glob patterns

Member, exclude and default-member entries SHALL be relative paths with `/` as the
separator. In a pattern, `*` SHALL match any run of characters in one segment, and `**`
SHALL match zero or more whole segments. All other characters SHALL match literally.
A literal entry SHALL name its directory whether or not it exists.

#### Scenario: Single-segment wildcard
- **WHEN** the members are `["packages/*"]`
- **THEN** `packages/billing` matches and `packages/billing/core` does not match

#### Scenario: Multi-segment wildcard
- **WHEN** the members are `["packages/**"]`
- **THEN** `packages/billing` and `packages/billing/core` match

#### Scenario: Listed member is missing
- **WHEN** the members are `["members/alpha"]`, `members/alpha` has no configuration, and `members/alpha` is the default member
- **THEN** the member source report has the status not found and lists the six candidates

### Requirement: Member entries stay in the workspace

An entry that is absolute, has a drive prefix, contains a backslash, or contains a `..`
segment SHALL be skipped with a warning that names the entry. The workspace root SHALL
never be its own member. Wildcard expansion SHALL only return directories that contain
a primary or legacy candidate.

#### Scenario: Escaping entry skipped
- **WHEN** the members are `["../outside", "packages/*"]`
- **THEN** discovery skips `../outside`, reports a warning that names it, and expands `packages/*`

#### Scenario: Root is not its own member
- **WHEN** the members are `["**"]`
- **THEN** the workspace root is not a member

### Requirement: Automatic member selection

When the found configuration is the workspace primary and no project is given, member
selection SHALL use this order. First, a member that encloses the start directory. Then,
the default member when it is a confined, non-excluded member. Then, the only member
when the expansion gives one member. Otherwise no member SHALL be selected.

#### Scenario: Default member selected
- **WHEN** the workspace declares members `["packages/*"]` and default member `packages/billing`, and the start directory is the workspace root
- **THEN** `packages/billing` is the selected member

#### Scenario: Single member selected
- **WHEN** the workspace declares members `["packages/*"]` and only `packages/orders` contains a configuration
- **THEN** `packages/orders` is the selected member

#### Scenario: Several members and no default
- **WHEN** the workspace has two members, no default member, and the start directory is the workspace root
- **THEN** no member source loads

#### Scenario: Default member names the root
- **WHEN** the default member is `.`
- **THEN** no member source loads

### Requirement: Explicit project selection

An explicit project selector SHALL first match a declared member path relative to the
workspace root. When no path matches, it SHALL match the project name key of the root
and of each member. `.` SHALL select the root project. More
than one name match SHALL raise `ConfigError::AmbiguousProject`. No match SHALL raise
`ConfigError::UnknownProject`. The selector SHALL be the `project` value of
`DiscoveryOptions`.

#### Scenario: Selection by path
- **WHEN** the selector is `packages/billing` and that path is a member
- **THEN** `packages/billing` is the selected member

#### Scenario: Ambiguous name
- **WHEN** the selector is `orders` and two members set the project name `orders`
- **THEN** selection raises `ConfigError::AmbiguousProject` that asks for a member path

#### Scenario: Unknown project
- **WHEN** the selector is `missing` and no member path or name matches
- **THEN** selection raises `ConfigError::UnknownProject` that names `missing`

### Requirement: Project layer order

The project-tier sources SHALL load in this order: workspace primary, member primary,
workspace environment file, member environment file, workspace user override, member
user override. A member layer and its override SHALL not load until that member is
selected.

#### Scenario: Member user override wins last
- **WHEN** the workspace primary sets `ui.theme = "workspace"`, the member primary sets `"member"`, the workspace override sets `"workspace-user"`, and the member override sets `"member-user"`
- **THEN** the effective value of `ui.theme` is `member-user`

#### Scenario: Member primary wins over workspace primary
- **WHEN** the workspace primary sets `ui.theme = "workspace"` and the selected member primary sets `ui.theme = "member"`, with no overrides
- **THEN** the effective value of `ui.theme` is `member`

### Requirement: Member-scope key filter

A convention set MAY name key paths that only the workspace can set. Discovery SHALL
declare them with the core `exclude(paths, warn=true)` on member primaries, member
environment files and member overrides. A removed key that existed SHALL give a
`ConfigWarning::KeyRemoved` with the key path and the origin in the report of that
source. The removed values SHALL have no provenance.

#### Scenario: Member cannot set a workspace key
- **WHEN** `workspace.out_dir` is a member-scope key and the member primary sets it
- **THEN** the effective value comes from the workspace, and the member report has a `KeyRemoved` warning for `workspace.out_dir` with the member file as origin

### Requirement: Inherited-layer key filter

A convention set MAY name top-level keys that a layer does not pass to scopes it does
not own. When a member is selected, discovery SHALL declare them with the core
`exclude(paths, warn=false)` on the system, global, workspace primary, workspace
environment-file and workspace override layers. Defaults, member layers and environment
variables SHALL stay complete. The removal SHALL give no warning.

#### Scenario: Workspace project table not inherited
- **WHEN** the filter is `["project", "workspace"]`, the workspace primary sets `project.name = "root"`, and the selected member sets no project name
- **THEN** the member's effective configuration has no `project.name` and the workspace report has no warning

#### Scenario: Shared table inherited
- **WHEN** the filter is `["project", "workspace"]` and the workspace primary sets `ui.theme = "dark"`
- **THEN** the member's effective value of `ui.theme` is `dark`

### Requirement: Environment name resolution

Environments SHALL be off unless the application enables them. When enabled, the
environment name SHALL be optional. Its value SHALL come from the `environment` value of
`DiscoveryOptions`, then from `<PREFIX>_ENVIRONMENT`, then from the default of the
convention set. An empty variable SHALL count as unset. With none of these, the name
SHALL be absent.

#### Scenario: Option wins
- **WHEN** the `environment` value of `DiscoveryOptions` is `Staging` and `ACME_ENVIRONMENT=Production`
- **THEN** the environment name is `Staging`

#### Scenario: Variable wins over default
- **WHEN** `ACME_ENVIRONMENT=Production` and the default is `Development`
- **THEN** the environment name is `Production`

#### Scenario: Empty variable is unset
- **WHEN** `ACME_ENVIRONMENT` is set to an empty value and the default is `Development`
- **THEN** the environment name is `Development`

#### Scenario: No source gives no name
- **WHEN** environments are enabled with no option value, no variable and no default
- **THEN** the environment name is absent and no environment file loads

### Requirement: Discovery options from the host

Discovery SHALL take the host inputs as one `DiscoveryOptions` value: the environment
name, the selection of the project primary, isolated mode and the project selector.
Discovery SHALL NOT read the process arguments. Discovery SHALL NOT raise a usage error.

#### Scenario: Arguments are not read
- **WHEN** the process arguments contain `--environment Staging`, the `environment` value of `DiscoveryOptions` is absent, and no variable or default is set
- **THEN** the environment name is absent

#### Scenario: Default options
- **WHEN** an application adds a convention set with no `DiscoveryOptions`
- **THEN** the project primary is discovered, isolated mode is off, and no project selector applies

### Requirement: Environment name validation

An environment name SHALL be non-empty. It SHALL NOT contain `/`, `\`, `.` or a control
character. It SHALL NOT equal `user` in any letter case. An invalid name SHALL be a
`ConfigError::InvalidEnvironmentName` that names the source of the name.

#### Scenario: Reserved name rejected
- **WHEN** `ACME_ENVIRONMENT=User`
- **THEN** discovery raises `ConfigError::InvalidEnvironmentName` that names `ACME_ENVIRONMENT`

#### Scenario: Path name rejected
- **WHEN** the `environment` value of `DiscoveryOptions` is `../prod`
- **THEN** discovery raises `ConfigError::InvalidEnvironmentName` that names the discovery options as the source

### Requirement: Environment files

When an environment name is present, each project-tier primary SHALL have environment
file candidates in its directory: `<app>.<name>.<ext>` for the root and hidden layouts,
and `config.<name>.<ext>` for the dot-config layout. The name SHALL match exactly,
with no case folding. More than one existing candidate SHALL be an ambiguity error.

#### Scenario: Environment file between primary and override
- **WHEN** the name is `Production`, `acme.toml` sets `ui.theme = "base"`, `acme.Production.toml` sets `"prod"`, and `acme.user.toml` sets `"mine"`
- **THEN** the effective value of `ui.theme` is `mine`, and without `acme.user.toml` it is `prod`

#### Scenario: Case must match
- **WHEN** the name is `Production` and only `acme.production.toml` exists next to `acme.toml`
- **THEN** no environment file loads

#### Scenario: Environment file without primary
- **WHEN** a directory contains only `acme.Production.toml`
- **THEN** that directory is not a project root

### Requirement: Environment files only for project-tier primaries

Environment files SHALL NOT apply to the system source, the global user source, a
legacy file or an explicit file outside the standard layouts.

#### Scenario: No environment file for global configuration
- **WHEN** the name is `Production` and `$HOME/.acme/acme.Production.toml` exists
- **THEN** no source loads that file

### Requirement: Pure discovery over the core load protocol

Discovery SHALL be a pure, synchronous function of explicit inputs: the core
`FileTree`, the platform, the environment variables, the start directory, the registered
formats, the convention set and the `DiscoveryOptions`. With the same inputs it SHALL
give the same result on every target. It SHALL return the core `LoadStep`. When the
tree does not contain an entry that discovery needs, discovery SHALL return
`Need` with the `FileRequest` values for the missing entries.

#### Scenario: Same result on all targets
- **WHEN** the same tree and inputs are given on wasm, wasm-gc, js and native
- **THEN** the sources, reports and errors are equal

#### Scenario: Missing entries requested
- **WHEN** the tree is partial and does not contain the parent directory listing that walk-up needs
- **THEN** discovery returns `Need` with a request that names that directory

#### Scenario: Complete tree
- **WHEN** the tree is marked complete and an entry is not in it
- **THEN** discovery treats the entry as absent and returns `Done`

### Requirement: Discovery through the core host adapter

On native and js, the core `@config/host.load` SHALL answer the requests of discovery
until it gives a result. This change SHALL NOT add a host package. On wasm and wasm-gc,
discovery SHALL run through the pure `@config.load` over an injected complete
`FileTree` and SHALL NOT read the file system.

#### Scenario: Native adapter reads files
- **WHEN** a native test writes `acme.toml` to a temporary directory and loads a convention set with that directory as start and boundary
- **THEN** the project source loads that file

#### Scenario: js adapter reads files
- **WHEN** a js test writes `acme.toml` to a temporary directory and loads a convention set with that directory as start and boundary
- **THEN** the project source loads that file

#### Scenario: Windows report paths
- **WHEN** the native or js test runs on Windows
- **THEN** the project report path uses `/` as the separator

#### Scenario: wasm uses injected tree
- **WHEN** a wasm-gc program injects a complete tree that contains `acme.toml`
- **THEN** discovery loads `acme.toml` with no file-system access

### Requirement: Path handling on Windows

Discovery SHALL use `/` as the separator for paths in trees, reports and errors on
every platform, including Windows. On Windows, discovery SHALL convert `\` to `/` in the
path-valued variables that it reads. A Windows absolute path SHALL be a drive letter
followed by a separator (`C:/`), or a UNC prefix (`//server/share`). A drive-relative
path such as `C:foo` SHALL NOT be absolute. Member and workspace entries SHALL reject
`\` on every platform.

#### Scenario: Windows absolute XDG check
- **WHEN** the platform is Windows and a path value is `D:\Profiles\Alice`
- **THEN** discovery treats it as absolute and reports it as `D:/Profiles/Alice`

#### Scenario: Backslash member entry rejected
- **WHEN** the platform is Linux and the members are `["packages\\billing"]`
- **THEN** discovery skips the entry with a warning

### Requirement: Source reports for convention sources

Each convention source SHALL produce a `SourceReport` with its kind, priority, loaded
path, every candidate it checked, and the status loaded, not found or skipped. The kind
SHALL be `File` with the core `FileRole` of the source. The priorities SHALL be system
100, global 200, workspace or project primary 300, member primary 350, environment file
375 and user override 400. The reports SHALL be in merge order, and the priorities
SHALL not decrease along that order.

#### Scenario: Not-found global source lists candidates
- **WHEN** no global user file exists
- **THEN** the global report has the status not found and lists every global candidate

#### Scenario: Reports in merge order
- **WHEN** discovery loads defaults, a project primary and environment variables
- **THEN** the reports are in merge order with priorities 0, 300 and 600

#### Scenario: Member roles
- **WHEN** a workspace primary and a selected member primary load
- **THEN** their reports have the roles `Workspace` and `Member` with priorities 300 and 350

### Requirement: Morphir preset reproduces Morphir

The acceptance suite SHALL contain a Morphir preset built only from public convention
parts. With the application `morphir`, the registered formats TOML and YAML limited to
`.yaml`, legacy file `morphir.json`, prefix `MORPHIR` and environments off, it SHALL give
Morphir's sources:
defaults 0, system 100, global 200, project 300, member 350, user override 400 and
environment 600.

#### Scenario: Six primary candidates
- **WHEN** the preset lists the primary candidates of a directory
- **THEN** they are `morphir.toml`, `morphir.yaml`, `.morphir/morphir.toml`, `.morphir/morphir.yaml`, `.config/morphir/config.toml` and `.config/morphir/config.yaml`

#### Scenario: Ambiguous Morphir configuration
- **WHEN** the directory contains `morphir.toml` and `morphir.yaml`
- **THEN** discovery fails and the message contains `Ambiguous Morphir configuration`

#### Scenario: Dot-config YAML project
- **WHEN** only `.config/morphir/config.yaml` exists
- **THEN** the project report path ends with `.config/morphir/config.yaml`

#### Scenario: Environment overrides project
- **WHEN** `morphir.toml` sets `ir.format_version = 3` and `MORPHIR_IR__FORMAT_VERSION=4`
- **THEN** the effective value of `ir.format_version` is 4

#### Scenario: Source list for a discovered project
- **WHEN** `morphir.toml` exists and `MORPHIR_UI__COLOR=false` is set in isolated mode
- **THEN** the project and environment reports have the status loaded, and the reports are in merge order

#### Scenario: Operational variables are not keys
- **WHEN** `MORPHIR_HOME=/tmp/mh` and `MORPHIR_LOG_DIR=/tmp/logs` are set
- **THEN** a global candidate is `/tmp/mh/morphir.toml`, and the effective configuration has no `home` or `log_dir` key

#### Scenario: Legacy morphir.json fallback
- **WHEN** a directory contains only `morphir.json`
- **THEN** the preset selects `morphir.json` as the project primary with no user override candidates

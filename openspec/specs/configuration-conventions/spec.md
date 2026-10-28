# configuration-conventions Specification

## Purpose
Configuration conventions find an application's configuration files and workspace
members, select an optional environment, and turn the result into ordered
configuration sources with reports. The rules are generic, so one application
layout (for example Morphir) is a preset made from these parts.

## Requirements

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

When ordered format layers are off, the following rules apply.

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

When ordered format layers are off, the following rules apply. With ordered format layers on, ambiguity is checked inside each declared layer.

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
local override, user override or environment file.

#### Scenario: Legacy file used when no primary exists
- **WHEN** the legacy name is `acme.json` and the directory contains only `acme.json`
- **THEN** discovery selects `acme.json` as the primary at that location

#### Scenario: Primary wins over legacy file
- **WHEN** the legacy name is `acme.json` and the directory contains `acme.json` and `acme.toml`
- **THEN** discovery selects `acme.toml` and does not report an ambiguity error

### Requirement: Walk-up root discovery

When workspace-first discovery is off, the following rules apply. Workspace-first discovery uses the separate workspace-first requirements.

Discovery SHALL start at the start directory, which is the working directory of the
run, and move to each parent directory. The
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
directory, adjacent local overrides and adjacent user overrides SHALL have the
selection `Skip`. Their reports SHALL show the status skipped. Project, workspace,
member, environment-file, profile-file and environment-variable sources SHALL stay
unchanged. Active profile files MUST still load in their normal project positions.

#### Scenario: Isolated mode skips user and machine files
- **WHEN** a global user file, a system file, `acme.local.toml` and `acme.user.toml` exist, and isolated mode is on
- **THEN** only the defaults, the project primary and the environment-variable source contribute values

#### Scenario: Isolated mode keeps environment variables
- **WHEN** `acme.toml` sets `ir.format_version = 3`, `ACME_IR__FORMAT_VERSION=4` is set, and isolated mode is on
- **THEN** the effective value of `ir.format_version` is 4

#### Scenario: Isolated mode keeps selected profile layers

- **WHEN** metrics is active and isolated mode skips machine, global, local, and user layers
- **THEN** eligible project/workspace/member metrics files still load, with environment-variable and CLI precedence unchanged

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

### Requirement: Directory variables come from the run variable set

Discovery SHALL read `HOME`, `XDG_CONFIG_HOME`, `APPDATA`, `PROGRAMDATA`,
`USERPROFILE` and `<PREFIX>_HOME` only from the variable set of the run in the core
load context. Discovery SHALL NOT read the process environment.

#### Scenario: Directories come only from the given set
- **WHEN** the platform is Linux, the variable set is `HOME=/home/test` and `XDG_CONFIG_HOME=/srv/test/config`, and the process environment has other values for `HOME` and `XDG_CONFIG_HOME`
- **THEN** the global candidates are `/srv/test/config/acme/acme.toml` and `/home/test/.acme/acme.toml`, on every target

### Requirement: One global user configuration

When ordered format layers are off, the following rules apply. With ordered format layers on, ambiguity is checked inside each declared stage and format group.

The configuration-directory candidates and the application-home candidates SHALL be
alternatives at one priority. When more than one of them exists, discovery SHALL fail
with an ambiguity error that names every existing candidate.

#### Scenario: Two global files
- **WHEN** `$HOME/.config/acme/acme.toml` and `$HOME/.acme/acme.toml` both exist
- **THEN** discovery fails with an ambiguity error that names both paths

### Requirement: Adjacent user overrides

When ordered format layers are off, the following rules apply. With ordered format layers on, each user-override stage uses the declared format order and ambiguity scope.

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

### Requirement: Adjacent local overrides

Local overrides SHALL use `<app>.local.<ext>` beside `<app>.<ext>` or `.<app>/<app>.<ext>`, and `config.local.<ext>` beside `.config/<app>/config.<ext>`. Extensions SHALL come from registered formats. Without ordered layers, multiple existing candidates for one primary SHALL be ambiguous. With layers, stages SHALL use declared format order and ambiguity SHALL be checked within each group.

#### Scenario: Local file loads between environment file and user override
- **WHEN** the name is `Production`, `acme.toml` sets `ui.theme = "base"`, `acme.Production.toml` sets `"prod"`, `acme.local.toml` sets `"local"`, and `acme.user.toml` sets `"mine"`
- **THEN** the effective value of `ui.theme` is `mine`, without `acme.user.toml` it is `local`, and the local report has the kind name `local-override` and priority 390

#### Scenario: Dot-config local override
- **WHEN** `.config/acme/config.toml` sets `ui.theme = "shared"` and `.config/acme/config.local.toml` sets `ui.theme = "local"`
- **THEN** the effective value of `ui.theme` is `local`

#### Scenario: Sibling local override serializations
- **WHEN** `acme.toml`, `acme.local.toml` and `acme.local.yaml` exist
- **THEN** discovery fails with an ambiguity error that names both local override files

### Requirement: Local overrides in the standard set

The convention set from `app_dirs` SHALL include the local override part. A convention
set from `base` SHALL NOT include it until the application adds it. `without` SHALL
remove it.

#### Scenario: Standard set loads a local file
- **WHEN** the convention set is `app_dirs("acme")` and `acme.toml` and `acme.local.toml` exist
- **THEN** a local override source loads `acme.local.toml`

#### Scenario: Base set has no local layer
- **WHEN** the convention set is `base("acme")` with the layouts and user overrides, and `acme.toml` and `acme.local.toml` exist
- **THEN** no source loads `acme.local.toml`

### Requirement: Explicit primary file

Without selected-file overlays, `Explicit(path)` SHALL supply the project primary without walk-up; enclosing-workspace search SHALL still apply. A standard-layout path SHALL retain adjacent local/user overrides, environment files and enabled profile files. A nonstandard path SHALL have no implicit adjacent files. With overlays enabled, the selected file SHALL follow the separate selected-overlay requirements.

#### Scenario: Explicit file from another directory
- **WHEN** the start directory is `elsewhere` and the explicit path is `../configs/project.yaml`
- **THEN** the project source loads `configs/project.yaml` and its report path ends with `configs/project.yaml`

#### Scenario: Explicit non-standard file has no override
- **WHEN** the explicit path is `configs/project.yaml` and `configs/project.user.yaml` exists
- **THEN** no user override source loads

#### Scenario: Profiles beside a standard explicit primary

- **WHEN** metrics is active and the explicit primary is a standard-layout `acme.toml`
- **THEN** the profile candidates include its adjacent `acme.profile.metrics` files

#### Scenario: Nonstandard explicit primary gains no profile sibling

- **WHEN** metrics is active and the explicit primary is `configs/custom.toml`
- **THEN** no implicit `custom.profile.metrics` file is requested

### Requirement: Enclosing workspace discovery

Without workspace-first discovery, discovery SHALL search the found project root's parents through the boundary. The first workspace whose member and exclude patterns select the root SHALL become the workspace primary; the found project SHALL become its member primary. Unreadable, ambiguous and non-workspace configurations SHALL be passed over. Workspace-first mode SHALL instead select the nearest declared workspace before member selection.

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

The project-tier sources SHALL load in this order: workspace primary, member
primary, workspace environment file, member environment file, profile files in
resolved active order with workspace before member for each name, workspace
local override, member local override, workspace user override, member user
override. A member layer and its overlays MUST NOT load until that member is
selected. With profiles off, the existing order MUST remain unchanged.

#### Scenario: Member user override wins last
- **WHEN** the workspace primary sets `ui.theme = "workspace"`, the member primary sets `"member"`, the workspace override sets `"workspace-user"`, and the member override sets `"member-user"`
- **THEN** the effective value of `ui.theme` is `member-user`

#### Scenario: Member local override order
- **WHEN** the workspace local override sets `ui.theme = "workspace-local"`, the member local override sets `"member-local"`, and the workspace user override sets `"workspace-user"`
- **THEN** the effective value of `ui.theme` is `workspace-user`, and without the workspace user override it is `member-local`

#### Scenario: Member primary wins over workspace primary
- **WHEN** the workspace primary sets `ui.theme = "workspace"` and the selected member primary sets `ui.theme = "member"`, with no overrides
- **THEN** the effective value of `ui.theme` is `member`

#### Scenario: Profile ordering spans workspace and member

- **WHEN** the active profile order is `[postgres,metrics]` and both locations hold both files
- **THEN** profile sources are workspace postgres, member postgres, workspace metrics, member metrics, after environment files and before local overrides

#### Scenario: Higher override stages still win

- **WHEN** a profile sets `ui.theme=profile`, a local override sets `ui.theme=local`, and a later CLI override sets `ui.theme=cli`
- **THEN** the final theme is cli, and without the CLI override it is local

### Requirement: Member-scope key filter

A convention set MAY name key paths that only the workspace can set. Discovery SHALL
declare them with the core `exclude(paths, warn=true)` on member primaries, member
environment files, member profile files and member overrides. A removed key that existed SHALL give a
`ConfigWarning::KeyRemoved` with the key path and the origin in the report of that
source. The removed values SHALL have no provenance.

#### Scenario: Member cannot set a workspace key
- **WHEN** `workspace.out_dir` is a member-scope key and the member primary sets it
- **THEN** the effective value comes from the workspace, and the member report has a `KeyRemoved` warning for `workspace.out_dir` with the member file as origin

#### Scenario: Member profile cannot set a workspace-only key

- **WHEN** `workspace.out_dir` is a member-scope key and a selected member profile file sets it
- **THEN** the profile value is removed, has no ordinary provenance, and the source report holds a KeyRemoved warning naming that file

### Requirement: Inherited-layer key filter

A convention set MAY name top-level keys that a layer does not pass to scopes it does
not own. When a member is selected, discovery SHALL declare them with the core
`exclude(paths, warn=false)` on the system, global, workspace primary, workspace
environment-file, workspace profile-file and workspace override layers. Defaults, member layers and environment
variables SHALL stay complete. The removal SHALL give no warning.

#### Scenario: Workspace project table not inherited
- **WHEN** the filter is `["project", "workspace"]`, the workspace primary sets `project.name = "root"`, and the selected member sets no project name
- **THEN** the member's effective configuration has no `project.name` and the workspace report has no warning

#### Scenario: Shared table inherited
- **WHEN** the filter is `["project", "workspace"]` and the workspace primary sets `ui.theme = "dark"`
- **THEN** the member's effective value of `ui.theme` is `dark`

#### Scenario: Workspace profile follows the inherited filter

- **WHEN** the inherited filter contains project and a workspace profile sets `project.name` and `ui.theme`
- **THEN** a selected member inherits ui.theme but not project.name, and the removal creates no warning

### Requirement: Environment name resolution

Environments SHALL be off unless the application enables them. When enabled, the
environment name SHALL be optional. Its value SHALL come from the `environment` value of
`DiscoveryOptions`, then from `<PREFIX>_ENVIRONMENT` in the variable set of the run,
then from the default of the convention set. An empty variable SHALL count as unset. With none of these, the name
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
name, the selection of the project primary, isolated mode, the project selector,
and typed profile activation selection. Profile selection MUST distinguish
unspecified, an explicit ordered list, and disabled processing.
Discovery SHALL NOT read the process arguments. Discovery SHALL NOT raise a usage error.

#### Scenario: Arguments are not read
- **WHEN** the process arguments contain `--environment Staging`, the `environment` value of `DiscoveryOptions` is absent, and no variable or default is set
- **THEN** the environment name is absent

#### Scenario: Default options
- **WHEN** an application adds a convention set with no `DiscoveryOptions`
- **THEN** the project primary is discovered, isolated mode is off, and no project selector applies

#### Scenario: Profile options use an explicit parsed selection

- **WHEN** a caller selects parsed profile names `[postgres,metrics]` through discovery options
- **THEN** discovery uses those names without inspecting process arguments or reparsing the typed names

#### Scenario: Default profile options preserve prior behavior

- **WHEN** a caller uses default discovery options and profiles are not enabled
- **THEN** no profile selection or profile file lookup is added

### Requirement: Environment name validation

An environment name SHALL be non-empty. It SHALL NOT contain `/`, `\`, `.` or a control
character. It SHALL NOT equal `user` or `local` in any letter case. An invalid name SHALL be a
`ConfigError::InvalidEnvironmentName` that names the source of the name.

#### Scenario: Reserved name rejected
- **WHEN** `ACME_ENVIRONMENT=User`
- **THEN** discovery raises `ConfigError::InvalidEnvironmentName` that names `ACME_ENVIRONMENT`

#### Scenario: Reserved name local rejected
- **WHEN** the `environment` value of `DiscoveryOptions` is `Local`
- **THEN** discovery raises `ConfigError::InvalidEnvironmentName` that names the discovery options as the source

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
`FileTree`, the platform, the variable set, the working directory, the registered
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
SHALL be `File` with the core `FileRole` of the source. The reports SHALL be in merge
order.

#### Scenario: Not-found global source lists candidates
- **WHEN** no global user file exists
- **THEN** the global report has the status not found and lists every global candidate

### Requirement: Convention source priorities

The priorities SHALL be system 100, global 200, workspace or project primary 300,
member primary 350, environment file 375, profile file 380, local override 390 and
user override 400. All profile files MUST share priority 380 and preserve their
resolved source order at that priority.
When selected-file overlays are on, their reports SHALL use the existing `Explicit` role and priority 325.
The priorities SHALL not decrease along the merge order.

#### Scenario: Reports in merge order
- **WHEN** discovery loads defaults, a project primary and environment variables
- **THEN** the reports are in merge order with priorities 0, 300 and 600

#### Scenario: Member roles
- **WHEN** a workspace primary and a selected member primary load
- **THEN** their reports have the roles `Workspace` and `Member` with priorities 300 and 350

#### Scenario: Several profiles fit between environment and local overrides

- **WHEN** an environment file, two profile files, and a local override load
- **THEN** their report priorities are 375, 380, 380, and 390, without reordering the equal-priority profile sources

### Requirement: Morphir preset reproduces Morphir

The acceptance suite SHALL contain a Morphir preset built only from public convention
parts. With the application `morphir`, the registered formats TOML and YAML limited to
`.yaml`, legacy file `morphir.json`, prefix `MORPHIR`, environments off and no local
override part, it SHALL give Morphir's sources:
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

#### Scenario: Preset has no local layer
- **WHEN** a directory contains `morphir.toml` and `morphir.local.toml`
- **THEN** no source loads `morphir.local.toml`, and no report has the kind name `local-override`

### Requirement: Discovery passes over inaccessible entries

Walk-up, the enclosing-workspace search and member selection SHALL ignore an
`Inaccessible` entry that is not a primary candidate, a legacy file or a member
directory that a pattern selects. When the name of an `Inaccessible` entry is a
candidate or a selected member directory, discovery SHALL ask for it, so the error of
the host passes out of the load and discovery never drops a configuration without a
report.

#### Scenario: Unbounded search reaches a locked file at the drive root

- **WHEN** the workspace part is on, no boundary is set, no directory above the start directory holds a workspace file, and the drive root holds an entry that the host cannot inspect
- **THEN** discovery asks for the listing of the drive root `D:/`, never for `D:` (the current directory of the drive), and loads the project file of the start directory with no error

#### Scenario: Inaccessible candidate is an error

- **WHEN** the start directory holds `acme.toml` as an `Inaccessible` entry
- **THEN** discovery asks for `acme.toml`, and the load raises the error of the host for it

#### Scenario: Inaccessible file next to a workspace file

- **WHEN** the enclosing-workspace search reaches `/w`, which holds the workspace file `acme.toml` and the candidate `acme.yaml` as `Inaccessible`
- **THEN** discovery asks for `/w/acme.yaml` and does not pass over `/w` as a directory with more than one file

#### Scenario: Inaccessible member directory is not dropped

- **WHEN** a workspace declares `members = ["packages/*"]` and `packages` holds an `Inaccessible` entry `billing`
- **THEN** discovery asks for the listings of `packages/billing`, and the error of the host passes out of the load

### Requirement: Explicit discovery policies preserve compatibility

The application SHALL select workspace-first discovery, ordered format layers and selected-file overlays explicitly. The default policies SHALL retain the existing candidate, legacy, root, member and explicit-primary behavior. A policy SHALL use typed alternatives and validated paths.

#### Scenario: Existing preset keeps its ambiguity rule
- **WHEN** an unchanged preset registers TOML and YAML, and both primary files exist
- **THEN** discovery raises the same ambiguity error as before this change

### Requirement: Workspace-first document classification

Workspace-first discovery SHALL inspect parsed candidate documents for an application-selected workspace section. A section, including an empty section, SHALL identify a workspace. Defaults, machine files and environment variables SHALL NOT create that identity. A project-only primary SHALL remain a fallback while discovery searches its parents.

#### Scenario: Project under a workspace
- **WHEN** `/w/app/acme.toml` defines only a project, `/w/acme.toml` has a workspace section, and the start directory is `/w/app/src`
- **THEN** the selected workspace root is `/w` and the nearest project root remains `/w/app`

#### Scenario: Empty workspace section
- **WHEN** `/w/acme.toml` contains an empty workspace section
- **THEN** `/w` is a workspace even when it has no members or default-member key

#### Scenario: Machine settings cannot create a workspace
- **WHEN** only a global file sets workspace members and the project primary has no workspace section
- **THEN** the global setting does not classify that project directory as a workspace

### Requirement: First workspace stops the search

Workspace-first discovery SHALL stop at the first declared workspace from the start directory upward, including the first primary location itself. It SHALL obey the explicit boundary. Member selection SHALL follow root selection and SHALL NOT cause a search for a farther workspace. With no workspace, discovery SHALL use the nearest project primary.

#### Scenario: Nested workspace wins over an outer workspace
- **WHEN** both `/w/acme.toml` and `/w/nested/acme.toml` declare workspaces, and the start is `/w/nested/src`
- **THEN** `/w/nested` is the selected workspace and `/w` is not read

#### Scenario: Boundary prevents workspace inheritance
- **WHEN** `/w/acme.toml` declares a workspace and the boundary is `/w/app`
- **THEN** discovery does not read `/w/acme.toml`

#### Scenario: Standalone project fallback
- **WHEN** `/w/app/acme.toml` defines a project and no workspace exists within the boundary
- **THEN** `/w/app` is the selected project root

#### Scenario: Exclusion does not choose a farther workspace
- **WHEN** the nearest workspace excludes the nearest project and a farther workspace includes it
- **THEN** discovery retains the nearest workspace, does not load the excluded project as a member, and does not search the farther workspace

### Requirement: Workspace classification failures are visible

Workspace-first discovery SHALL report an invalid, unreadable or ambiguous candidate at an examined location. It SHALL NOT silently pass over the problem and select an ancestor. An incomplete tree SHALL return the existing load requests before classification continues.

#### Scenario: Broken parent document
- **WHEN** the upward search examines a malformed parent primary
- **THEN** the load fails with that file and its parse problem

#### Scenario: Missing parent listing
- **WHEN** the search needs a parent directory absent from a partial tree
- **THEN** discovery returns a request for that directory and does not choose a root yet

### Requirement: Ordered format layers

An application SHALL be able to declare ordered groups of registered formats. Discovery SHALL allow one primary per group at a location, merge the groups in declared order, and reject multiple candidates inside one group. Group order SHALL be independent of parser registration order. Unregistered formats SHALL remain outside discovery.

#### Scenario: JSON then YAML then TOML
- **WHEN** the declared groups are JSON, YAML and TOML, and each primary exists with a shared key
- **THEN** TOML wins that key, keys set only by YAML or JSON remain, and each origin names its source

#### Scenario: YAML alternatives are ambiguous
- **WHEN** `.yaml` and `.yml` belong to one group and both primary files exist
- **THEN** discovery raises ambiguity naming both files

#### Scenario: TOML layout alternatives are ambiguous
- **WHEN** both `acme.toml` and `.acme/acme.toml` exist in the TOML group
- **THEN** discovery raises ambiguity naming both files

### Requirement: Supplemental source within a format layer

An application SHALL be able to name a supplemental file below the ordinary primary in one format group. It SHALL count as a root marker, load through its registered parser, retain its own origin, and coexist with the ordinary primary. It SHALL NOT disable the same group's ambiguity check for ordinary candidates.

#### Scenario: Workspace JSON below project JSON
- **WHEN** supplemental `acme-workspace.json` and primary `acme.json5` both exist
- **THEN** both load, `acme.json5` wins shared keys, and the supplemental file is not an ambiguous ordinary primary

### Requirement: Layered stages use one root decision

Ordered format layers SHALL use one root decision and the same group order for each enabled machine, global, primary, member and adjacent-override stage. Candidate ambiguity SHALL remain scoped to that stage and group. Workspace classification SHALL inspect the merged primary documents at a location. Existing stage precedence and source roles SHALL remain unchanged.

#### Scenario: Workspace declaration in a lower format
- **WHEN** JSON declares workspace members and TOML at the same location sets another workspace key
- **THEN** the merged primary declares one workspace and both documents contribute values

#### Scenario: Local override format order
- **WHEN** ordered groups are YAML then TOML and both `acme.local.yaml` and `acme.local.toml` exist beside a primary
- **THEN** both local overrides load, TOML wins shared keys, and both reports retain the local-override role

#### Scenario: Global formats share one stage
- **WHEN** ordered groups are YAML then TOML and the global directory holds both primary files
- **THEN** both load at the global stage in group order, while two candidates inside one group remain ambiguous

#### Scenario: User override format order
- **WHEN** YAML and TOML user overrides set the same key
- **THEN** the TOML user override wins, and each report retains the user-override role

### Requirement: Layered profile order

When profiles and ordered format layers are enabled, discovery SHALL retain active-name order. Within each name,
workspace format groups SHALL precede member format groups. All those sources SHALL keep priority 380 and the
existing profile-file role. Ambiguity SHALL be checked per name, location and format group. Profiles SHALL NOT
change the root decision.

#### Scenario: Later profile beats an earlier member format
- **WHEN** an earlier profile's member TOML sets a key and a later profile's workspace JSON replaces it
- **THEN** the later workspace JSON value wins unless another later stage replaces it

### Requirement: Selected file is one overlay

With selected-file overlays on, discovery SHALL retain the discovered primary layers and load the selected file above them and below member primaries. A selected file already found by discovery SHALL load only in its overlay position. Reports SHALL use the existing `Explicit` role and priority 325. Missing or unreadable selected files SHALL fail with a typed error naming the file.

#### Scenario: Discovered JSON selected above TOML
- **WHEN** `acme.json` and `acme.toml` set a key differently and the selected file is `acme.json`
- **THEN** JSON wins that key, TOML-only keys remain, and JSON has one source report in the overlay position

### Requirement: Public root and layer evidence

The public pure API SHALL expose selected workspace and nearest-project roots and ordered source evidence. Applications SHALL be able to use that result with their own all-member walk without running a private discovery algorithm or enabling automatic single-member loading. The same input SHALL give equal roots, reports and errors on all four targets.

#### Scenario: Application keeps its member walk
- **WHEN** an application requests root and layer evidence without automatic member selection
- **THEN** it gets the selected roots and primary sources, and can load its members through public sources and merge

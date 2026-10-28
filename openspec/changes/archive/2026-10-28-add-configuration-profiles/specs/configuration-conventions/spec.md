## MODIFIED Requirements

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

### Requirement: Explicit primary file

When the `config` value of `DiscoveryOptions` is `Explicit(path)`, discovery SHALL use that
file and SHALL NOT walk up for a root. The enclosing-workspace search SHALL still apply.
When the file path matches a standard layout, the local override, user override and
environment-file rules SHALL apply, and enabled profile-file rules MUST apply.
Other explicit files SHALL have no implicit override, environment file, or profile
file.

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

### Requirement: Convention source priorities

The priorities SHALL be system 100, global 200, workspace or project primary 300,
member primary 350, environment file 375, profile file 380, local override 390 and
user override 400. All profile files MUST share priority 380 and preserve their
resolved source order at that priority.
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

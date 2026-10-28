# Spec Delta

## MODIFIED Requirements

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

### Requirement: Enclosing workspace discovery

When workspace-first discovery is off, the following rules apply. Workspace-first discovery selects the nearest declared workspace before member selection.

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

### Requirement: Explicit primary file

When selected-file overlays are off, the following rules apply. With selected-file overlays on, the selected file follows the separate overlay requirements.

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

## ADDED Requirements

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

#### Scenario: User override format order
- **WHEN** YAML and TOML user overrides set the same key
- **THEN** the TOML user override wins, and each report retains the user-override role

### Requirement: Selected file is one overlay

With selected-file overlays on, discovery SHALL retain the discovered primary layers and load the selected file above them and below member primaries. A selected file already found by discovery SHALL load only in its overlay position. Missing or unreadable selected files SHALL fail with a typed error naming the file.

#### Scenario: Discovered JSON selected above TOML
- **WHEN** `acme.json` and `acme.toml` set a key differently and the selected file is `acme.json`
- **THEN** JSON wins that key, TOML-only keys remain, and JSON has one source report in the overlay position

### Requirement: Public root and layer evidence

The public pure API SHALL expose selected workspace and nearest-project roots and ordered source evidence. Applications SHALL be able to use that result with their own all-member walk without running a private discovery algorithm or enabling automatic single-member loading. The same input SHALL give equal roots, reports and errors on all four targets.

#### Scenario: Application keeps its member walk
- **WHEN** an application requests root and layer evidence without automatic member selection
- **THEN** it gets the selected roots and primary sources, and can load its members through public sources and merge

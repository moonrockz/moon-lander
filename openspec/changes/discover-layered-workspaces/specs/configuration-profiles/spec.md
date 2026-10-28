# Spec Delta

## MODIFIED Requirements

### Requirement: One authoritative base for controls

When enabled, file controls SHALL come only from the standard-layout workspace
primary documents, or the standard-layout project primary documents when no workspace is selected. With ordered format layers on, those documents SHALL form one authoritative base in format order. Each control MUST retain its supplying document origin.
The system MUST select the workspace and member using existing base discovery
before profile activation. Overlays and member files MUST NOT change that selection.

#### Scenario: A member cannot redefine the workspace profile policy

- **WHEN** a selected workspace member primary contains profile controls
- **THEN** loading fails with a typed invalid-control-location error naming that member file before the factory runs

#### Scenario: A profile cannot select another member

- **WHEN** a loaded profile sets workspace discovery keys
- **THEN** it does not trigger another member selection, and existing key filters determine which ordinary values survive

### Requirement: Controls cannot activate from later layers

When enabled and not explicitly disabled, controls in profile, environment,
local/user, system/global, legacy, nonstandard explicit, or selected-member
layers SHALL fail visibly. Generic configuration overrides MUST NOT set reserved
profile controls. Validation MUST precede layer filters. Activation MUST remain
fixed for the full load. A discovered base file selected as an ordinary-value overlay MUST retain its original control authority, while a selected non-base file MUST NOT gain control authority.

#### Scenario: A profile includes another profile

- **WHEN** an active profile file contains `profiles.include`
- **THEN** loading fails with the file and key and never requests the newly named profile file

#### Scenario: A filter cannot hide forbidden controls

- **WHEN** an inherited or member filter would remove a forbidden control subtree
- **THEN** loading still rejects the control location before applying that filter

#### Scenario: Generic overrides are not a second activation channel

- **WHEN** a generic override or nested environment mapping sets `profiles.active` while profile processing is enabled
- **THEN** loading rejects that source rather than changing activation or exposing a misleading effective value

### Requirement: Adjacent profile file selection

When ordered format layers are off, the following selection and ambiguity rules apply. With layers on, formats load in the declared groups and ambiguity is checked within each name, location and group.

Each active name SHALL select `<stem>.profile.<name>.<ext>` beside eligible
project/workspace/member primaries, using registered extensions. Matching MUST
be exact; multiple existing candidates for one name/location MUST be ambiguous.
A missing candidate MUST report not-found. Inactive profile contents MUST NOT
be requested or parsed.

#### Scenario: Marker profile without a file

- **WHEN** metrics is active and no metrics file exists at an eligible location
- **THEN** metrics remains active, its candidate report is not-found, and other layers still load

#### Scenario: Two formats conflict

- **WHEN** both `acme.profile.metrics.toml` and `acme.profile.metrics.yaml` exist and their formats are registered
- **THEN** loading fails with both paths rather than choosing by registration order

#### Scenario: Inactive malformed file is ignored

- **WHEN** only metrics is active and an unrelated profile file has invalid syntax
- **THEN** no content request or parse is made for that unrelated file

#### Scenario: Profile files are not root markers

- **WHEN** a directory holds only `acme.profile.metrics.toml`
- **THEN** it does not become a project root and discovery keeps its existing walk-up rules

### Requirement: Profile layers have ordered precedence

Profile layers SHALL follow all selected environment layers and precede local
overrides. For each active profile in order, the workspace file MUST precede
the selected member files. With ordered format layers on, each location MUST use the declared group order before discovery advances to the next active name. Later profiles MUST win under existing merge rules.
Local/user, environment-variable, and CLI override precedence MUST remain higher.

#### Scenario: A later workspace profile beats an earlier member profile

- **WHEN** active profiles are `[postgres,metrics]`, the member postgres file sets `mode=member`, and the workspace metrics file sets `mode=metrics`
- **THEN** metrics wins unless the member metrics file or a higher stage overrides it

#### Scenario: Lists and null keep core semantics

- **WHEN** a profile overlays a list or a null-valued struct field
- **THEN** the selected existing merge policy applies, including replacement by default and ignored null overlays

## ADDED Requirements

### Requirement: Control origins survive layered bases

With ordered base formats on, the resolver SHALL retain the winning origin for each active/default/include
control and each whole-group definition. Graph errors SHALL name the effective definition's origin. Controls
SHALL be removed from ordinary values without discarding their profile metadata. The existing single-base
resolver API SHALL retain its behavior.

#### Scenario: Higher format replaces one group
- **WHEN** JSON defines a group and TOML replaces that group while JSON alone supplies defaults
- **THEN** the group definition and its failures name TOML, while the default selector names JSON

### Requirement: Selected discovered base retains control authority

Selecting an already discovered base file as an ordinary-value overlay SHALL retain that file's base control
authority. The file SHALL be parsed once and have one ordinary source report in its overlay position. Arbitrary
selected files SHALL remain forbidden control locations while processing is enabled and not explicitly disabled.
Explicitly disabled processing SHALL retain the existing control-stripping behavior. Control extraction SHALL NOT cause ordinary values to
be merged at both positions.

#### Scenario: Selecting the workspace primary
- **WHEN** the discovered primary contains valid profile controls and the selected overlay names the same normalized path
- **THEN** the controls still resolve from the base and ordinary values load once above other primaries

#### Scenario: Selecting an external file
- **WHEN** processing is enabled and not explicitly disabled and a selected non-base file contains profile controls
- **THEN** the load fails with the existing control-location failure naming that file

### Requirement: Supplemental-only bases have profile layouts

When a supplemental file is the only base document at a location, enabled profiles SHALL use the standard
application layout at that location. The supplemental file SHALL NOT introduce a different profile-file stem.
The usual active-name, format-group, boundary and isolation rules SHALL apply.

#### Scenario: Workspace JSON alone
- **WHEN** only supplemental `acme-workspace.json` declares a workspace and metrics is active
- **THEN** profile candidates use `acme.profile.metrics.<ext>`, not `acme-workspace.profile.metrics.<ext>`

# configuration-profiles Specification

## Purpose
Let applications compose named configuration profiles with deterministic
activation, file overlays, groups, and reports, independently of deployment
environment selection and without adding host I/O to the portable loader.

## Requirements

### Requirement: Profiles are an independent opt-in

Profiles SHALL be off until the application enables a profile policy. Existing
environment selection MUST remain independent. With profiles off, existing
values, source order, reports, and environment-only behavior MUST be unchanged.

#### Scenario: Existing environment-only application

- **WHEN** profiles are off and an application selects environment `Production`
- **THEN** it loads the existing environment file and no profile file, adds no profile resolution, and leaves an application key named `profiles` unchanged

#### Scenario: Environment and profile coexist

- **WHEN** profiles are enabled, the environment is `Production`, and the active profile is `metrics`
- **THEN** both the environment layer and the metrics profile layer apply, without implicitly activating a profile named production

### Requirement: Profile flags do not enable discovery implicitly

A valid standard profile CLI selection with no enabled profile policy SHALL be
ignored with a note, without adding profile files or resolution metadata. Invalid
CLI lists MUST still fail at the argument boundary. With profiles off, ordinary
application variables and keys MUST keep their existing interpretation.

#### Scenario: Registered option on a bare host

- **WHEN** a bare host registers --profiles and receives `--profiles metrics` but has no enabled profile policy
- **THEN** it reports the ignored option, stays Off, and does not start discovery or read profile files

### Requirement: Parsed portable profile names

Profile names SHALL use a type with private fields and a smart constructor. A
name MUST start with a lowercase ASCII letter and contain only lowercase ASCII
letters, digits, underscores, or hyphens, with length 1 through 64. Matching MUST
be exact. Invalid input MUST give a typed rule and source before file selection.

#### Scenario: Unsafe or case-aliased names

- **WHEN** a name contains uppercase, a dot, slash, backslash, comma, whitespace, a control character, or exceeds 64 characters
- **THEN** parsing fails with the input and the specific broken rule before a candidate path is constructed

#### Scenario: Names at the limits

- **WHEN** names are `a`, a valid 64-character name, `local`, and `user`
- **THEN** all parse successfully and retain their spelling

### Requirement: Explicit activation selection

Selection SHALL distinguish unspecified input, an explicit ordered list, and
disabled processing. Precedence MUST be explicit discovery options, the run's
profile variable, base-file active names, base-file default names, then policy
fallback names. A winning explicit list MUST replace lower lists. The system
MUST NOT activate an implicit default profile.

#### Scenario: Option replaces the variable

- **WHEN** explicit options select `[metrics]`, the variable selects `postgres`, and the base active list is `[tracing]`
- **THEN** the chosen active roots are `[metrics]`, before configured includes and group expansion

#### Scenario: Defaults and an explicit empty list

- **WHEN** defaults are `[development]` and the winning active input explicitly selects `[]`
- **THEN** development is not active, while configured includes still apply

#### Scenario: No names are configured

- **WHEN** profiles are enabled with no activation, defaults, or includes
- **THEN** the active set is empty and no profile files are requested

### Requirement: Command-line and variable list syntax

The standard host adapter SHALL accept repeated `--profiles <a,b>` options in
argument order and a conflicting `--no-profiles` flag. Lists MUST split at commas,
trim surrounding ASCII whitespace, and reject empty elements. The selector
variable MUST be `<PREFIX>_PROFILES` from the run snapshot. An absent variable is
unspecified; an empty or whitespace-only variable is disabled.

#### Scenario: Repeated options after a subcommand

- **WHEN** arguments are `build --profiles postgres,metrics --profiles tracing`
- **THEN** the selected roots are `[postgres,metrics,tracing]` in that order, from the single argparse result

#### Scenario: Bad list or conflicting flags

- **WHEN** arguments contain `--profiles=`, `--profiles postgres,,metrics`, or both `--profiles metrics` and `--no-profiles`
- **THEN** the run ends with a usage failure before discovery or service construction

#### Scenario: Variable comes from the injected run

- **WHEN** the run snapshot holds `ACME_PROFILES=postgres,metrics` and the process holds another value
- **THEN** activation uses the run snapshot without a second process read

### Requirement: Explicit disable suppresses every profile

A disabled selection SHALL suppress includes, defaults, group expansion, and
profile-file reads. It MUST expose an empty resolution with its disabling source.
Otherwise loaded configuration MUST retain its ordinary values while excluding
reserved profile controls. Disabling MUST NOT change environment selection.

#### Scenario: Disable a configured group

- **WHEN** `--no-profiles` wins and the base file has valid syntax but contains defaults, includes, and a type-invalid control such as `profiles.active=42`
- **THEN** no profile controls are interpreted, no profile files are read, the resolution is empty with the flag as its reason, and environment files still apply

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

### Requirement: Literal typed profile controls

The authoritative base SHALL accept a reserved `profiles` table containing
`active`, `default`, `include`, and `groups`. Name lists MUST contain strings;
groups MUST map valid names to name lists. Unknown fields, wrong types, and
secret references MUST fail at their control key. Profile controls MUST NOT
become application values or ordinary leaf origins while the feature is enabled.

#### Scenario: Typed control error

- **WHEN** `profiles.groups.production` is a scalar instead of a list
- **THEN** loading fails with its key, file origin, expected type, and typed failure class

#### Scenario: Controls do not leak into binding

- **WHEN** a valid base control table selects metrics
- **THEN** metrics is recorded in profile resolution while the `profiles` subtree is absent from effective application values and ordinary provenance

### Requirement: Controls cannot activate from later layers

When enabled and not disabled, controls in profile, environment, local/user, system/global, legacy, nonstandard explicit and member layers SHALL fail before filters. Generic overrides MUST NOT set reserved controls. Activation MUST remain fixed for the load. Selecting a discovered base as an ordinary overlay MUST preserve its control authority; a selected non-base file MUST NOT gain authority.

#### Scenario: A profile includes another profile

- **WHEN** an active profile file contains `profiles.include`
- **THEN** loading fails with the file and key and never requests the newly named profile file

#### Scenario: A filter cannot hide forbidden controls

- **WHEN** an inherited or member filter would remove a forbidden control subtree
- **THEN** loading still rejects the control location before applying that filter

#### Scenario: Generic overrides are not a second activation channel

- **WHEN** a generic override or nested environment mapping sets `profiles.active` while profile processing is enabled
- **THEN** loading rejects that source rather than changing activation or exposing a misleading effective value

### Requirement: Includes precede chosen roots

Policy includes SHALL precede base-file includes, which MUST precede the chosen
active or default roots. Includes MUST remain active when another active list
replaces defaults. Explicit disabled processing MUST suppress includes too.

#### Scenario: Active selection keeps shared includes

- **WHEN** includes are `[common]`, defaults are `[development]`, and CLI roots are `[production]`
- **THEN** roots expand from `[common,production]` and development is not activated by the default

### Requirement: Deterministic groups and duplicate order

Groups SHALL expand recursively in listed order, with the group name before its
members. Group names MUST remain active. After expansion, duplicate names MUST
keep their last occurrence. A base group definition MUST replace the entire
policy definition of the same name. Unknown group names MUST be leaf profiles.

#### Scenario: Explicit roots override an included duplicate

- **WHEN** includes are `[metrics]`, roots are `[production,postgres]`, and production contains `[postgres,metrics]`
- **THEN** the final active order is `[production,metrics,postgres]`

#### Scenario: Diamond expansion is stable

- **WHEN** a group contains `[left,right]` and both include a shared leaf
- **THEN** the leaf is active once at its last expansion position, independently of map iteration order

### Requirement: Invalid or excessive group graphs fail

Resolution SHALL reject direct and indirect group cycles, including inactive
cycles, with their cycle path and origin. Limits MUST be 64 groups, 64 members
per group, 32 group levels, and 128 distinct active names. It MUST reject excess
rather than truncate and bound work for graphs with shared subgroups.

#### Scenario: An inactive cycle exists

- **WHEN** the effective registry contains `a -> b -> a` even though only metrics was requested
- **THEN** resolution fails with the closed cycle `[a,b,a]` and its definition origin

#### Scenario: Limits are exact

- **WHEN** a registry or resolved state is at a stated limit and then one item or level above it
- **THEN** the valid boundary succeeds and the excess fails with the typed limit and actual count

### Requirement: Adjacent profile file selection

Each active name SHALL select exact `<stem>.profile.<name>.<ext>` candidates beside eligible project/workspace/member primaries. Without ordered layers, multiple registered-format candidates per name/location SHALL be ambiguous. With layers, declared group order SHALL apply and ambiguity SHALL be checked per name/location/group. Missing candidates MUST report not-found. Inactive contents MUST NOT be requested or parsed.

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

### Requirement: Profile resolution is observable and immutable

A loaded configuration SHALL expose Off or one typed immutable profile resolution.
Resolution MUST give the winning selector source, roots, expanded order, and
include/group reasons with control origins. Typed membership queries MUST use
that resolution. Returned collections MUST not allow mutation of kept state.

#### Scenario: Resolve once and inspect later

- **WHEN** a caller inspects active profiles after a successful load
- **THEN** the caller gets the recorded resolution without rereading files or variables or repeating discovery

#### Scenario: Caller changes a returned list

- **WHEN** a caller changes an array returned from the resolution
- **THEN** subsequent queries and source order remain unchanged

#### Scenario: Competing profile providers

- **WHEN** two enabled profile policies expand in one configuration pipeline
- **THEN** loading fails with both provider identities rather than choosing the last metadata value

### Requirement: Host contexts share the final resolution

The host factory, hooks, and command SHALL receive the same resolved profile
state from the loaded configuration. Application code MUST be able to choose
service implementations using typed membership. Invalid profile inputs MUST
stop before service construction, using the existing usage/configuration exit
policy. Help and version MUST require no profile I/O.

#### Scenario: Service factory chooses an implementation

- **WHEN** postgres is active and the factory selects a database implementation using profile membership
- **THEN** every later hook and command sees that same profile membership and services record

#### Scenario: Help avoids file discovery

- **WHEN** the application requests help or version alongside valid profile options
- **THEN** it returns the requested display output without reading base or profile files

### Requirement: Profile loading stays portable

Resolution and discovery SHALL be pure over explicit inputs and use the existing
typed file-tree protocol. The same inputs MUST give equal active state, values,
reports, and failures on wasm, wasm-gc, js, and native. Native, Node/Bun, and
browser hosts MUST use their existing filesystem or mount boundaries.

#### Scenario: Partial file snapshot

- **WHEN** activation is known but an active profile candidate is unknown in an incomplete tree
- **THEN** loading returns its typed file request and no partial configuration or final profile state

#### Scenario: Equal inputs across targets

- **WHEN** complete snapshots and run inputs are equal on all four targets
- **THEN** resolution, merge order, values, provenance, reports, and typed errors agree

#### Scenario: Unreadable selected candidate

- **WHEN** an active profile candidate is inaccessible or outside an allowed browser mount
- **THEN** its existing host or mount failure remains visible and is not treated as an absent profile file

### Requirement: Control origins survive layered bases

With ordered base formats on, the resolver SHALL retain the winning origin for each active/default/include
control and each whole-group definition. Graph errors SHALL name the effective definition's origin. Controls
SHALL be removed from ordinary values without discarding their profile metadata. The existing single-base
resolver API SHALL retain its behavior.

#### Scenario: Higher format replaces one group
- **WHEN** JSON defines a group and TOML replaces that group while JSON alone supplies defaults
- **THEN** the group definition and its failures name TOML, while the default selector names JSON

### Requirement: Literal control metadata merges before parsing

Reserved metadata MUST merge before its one semantic parse: objects merge by field; other supplied values, including null, replace. All eligible base identities MUST remain authorized independently of which controls win.

#### Scenario: A winning null control retains its shape failure
- **WHEN** a later eligible base sets `profiles.active` to null over an earlier valid list
- **THEN** loading fails with the existing typed control-shape error and names the later source, rather than ignoring null as an ordinary configuration overlay

### Requirement: Selected discovered base retains control authority

Selecting a discovered base as an overlay SHALL preserve its control authority. It SHALL be parsed once, with
one ordinary source report at the overlay position and no duplicate merge. Non-base selections SHALL reject
controls when processing is enabled. Explicitly disabled processing SHALL retain control stripping.

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

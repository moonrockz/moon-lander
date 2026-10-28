## MODIFIED Requirements

### Requirement: Source priority

When the application gives no priority, the priority SHALL come from the kind and
file role: defaults 0, system 100, global 200, workspace, explicit, and legacy
files 300, member 350, environment file 375, profile file 380, local override 390,
user override 400, environment variables 600, and overrides 700. An in-memory source with no priority
MUST take the priority of the source before it, or 0 when it is first.

#### Scenario: Default priorities

- **WHEN** an application adds a defaults source, an explicit file source, an in-memory source, an environment source, and an overrides source, with no priorities
- **THEN** the source reports show the priorities 0, 300, 300, 600, and 700

#### Scenario: Override file priorities

- **WHEN** an application adds an environment file source, a local override file source, and a user override file source, with no priorities
- **THEN** the source reports show the priorities 375, 390, and 400

#### Scenario: Ordered profiles have one display priority

- **WHEN** two profile file sources have no explicit priorities
- **THEN** both report priority 380, their insertion order determines precedence, and the source-order check accepts the equal priorities

### Requirement: Report kind names

Reports SHALL show Morphir kind names: `defaults`, `system`, `global`, `project`
(for workspace, explicit, and legacy files), `workspace-member`,
`environment-file`, `user-override`, and `environment`. A local override file MUST
show `local-override`. A profile file MUST show `profile-file`. In-memory and
overrides sources MUST show `in-memory` and `overrides`.

#### Scenario: File role names

- **WHEN** the sources are a member primary file, a local override file, and a user override file
- **THEN** their reports show the kind names `workspace-member`, `local-override`, and `user-override`

#### Scenario: Profile file identity is typed

- **WHEN** a profile file for metrics loads
- **THEN** its report kind name is `profile-file`, its file role carries the parsed profile name metrics, and its ordinary origins retain the source file path

## ADDED Requirements

### Requirement: Loaded profile metadata is separate from values

The loaded configuration SHALL carry at most one immutable typed profile
resolution, separate from application values, warnings, and leaf provenance.
With profiles off it MUST expose Off. The loader MUST retain provider-supplied
resolution only with a completed successful load and reject competing enabled
resolutions. Existing providers without profiles MUST keep their behavior.

#### Scenario: No resolution escapes an incomplete load

- **WHEN** a source provider has resolved profile names but any required file remains unknown
- **THEN** the load returns file requests and exposes neither a final configuration nor a final profile resolution

#### Scenario: Custom provider without profiles

- **WHEN** an existing custom provider returns ordinary sources without enabling profiles
- **THEN** its sources, ordering, warnings, and merge results stay unchanged and the configuration exposes profile state Off

#### Scenario: Typed provider output migration

- **WHEN** a custom provider constructs or decorates an expansion
- **THEN** it uses `Expansion::new(sources, warnings?, profiles?)`, defensive `sources()` and `warnings()` accessors, and an immutable `profiles()` accessor; omitting profile metadata preserves Off

### Requirement: Profile failures use the shared configuration error

Profile failures SHALL use the shared configuration error with typed rules for
names, control values and locations, group cycles and limits, and competing
providers. The failure MUST identify its source or control origin and preserve
any parser position. Cycle failures MUST expose the closed name path without
requiring a message parse.

#### Scenario: Profile failure is a configuration error

- **WHEN** group resolution finds a cycle
- **THEN** the caller can match a profile configuration-failure case and read the typed rule, cycle path, and control origin without parsing the message

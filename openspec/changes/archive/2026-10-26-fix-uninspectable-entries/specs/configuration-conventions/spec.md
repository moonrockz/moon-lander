## ADDED Requirements

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

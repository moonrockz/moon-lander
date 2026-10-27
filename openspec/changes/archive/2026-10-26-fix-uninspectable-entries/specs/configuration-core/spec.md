## ADDED Requirements

### Requirement: Host listings record inaccessible entries

A directory listing SHALL record each entry that the host lists but cannot inspect as
`Inaccessible`. The native and js host adapters MUST NOT raise an error for such an
entry when they answer a listing request. An entry that does not exist when the adapter
inspects it SHALL NOT be in the listing. An error for the listed directory itself, or
for a requested file, SHALL pass out of the load.

#### Scenario: Locked entry next to a configuration file

- **WHEN** a directory holds `acme.toml` and an entry whose inspection fails with a Windows sharing violation, and the adapter answers the listing
- **THEN** the listing holds `acme.toml` as a file and the other entry as `Inaccessible`, and the load reads `acme.toml`

#### Scenario: Entry that disappears

- **WHEN** an entry is in the directory listing and does not exist when the adapter inspects it, or is a link that points nowhere
- **THEN** the listing does not hold the entry and the adapter raises no error

### Requirement: An inaccessible entry can be a file

When the tree does not hold the text of an `Inaccessible` entry with the exact name,
`FileTree::is_file` SHALL give `Unknown`, and `FileTree::file_request` SHALL give the
file request for it. So the load asks the host for that file before it counts the
candidates, and the error of the host passes out of the load. When the tree holds the
text, or the tree is complete, the entry SHALL be a file.

#### Scenario: Inaccessible entry next to a candidate

- **WHEN** the tree is not complete, the listing of `/w` holds `acme.toml` as a file and `acme.yaml` as `Inaccessible`, and both are candidates
- **THEN** the load asks for the file `/w/acme.yaml` and does not raise an ambiguity error before the host answers

#### Scenario: Inaccessible candidate file

- **WHEN** the tree is not complete, a candidate source names `/w/acme.toml`, and the listing of `/w` holds `acme.toml` as `Inaccessible`
- **THEN** the load asks for the file `/w/acme.toml`, and the error of the host for it passes out of the load

## ADDED Requirements

### Requirement: Parsed file-tree paths

Every public path input to `FileTree` and every `FileRequest` payload SHALL use
one parsed path type with private fields. Raw text MUST enter through a smart
constructor. Failure MUST hold the input and a typed rule. Parsing MUST NOT read
process state or perform filesystem I/O.

#### Scenario: Raw text cannot enter a request

- **WHEN** a consumer constructs a file request or calls a file-tree method
- **THEN** the compiler requires a parsed path instead of a string, and the public interface exposes no unchecked constructor

#### Scenario: Invalid portable input

- **WHEN** the portable constructor receives empty text, a NUL, or a backslash
- **THEN** it raises a typed parse error that names the input and the broken rule before any host call

### Requirement: File-tree path roots

Parsed paths SHALL distinguish a POSIX root, an ASCII-letter drive root, a UNC
server-and-share root, and a current-directory-relative path. A drive prefix MUST
have `/` after `:`. A UNC root MUST have a nonempty server and share. A root MUST
have no parent. Case MUST remain exact.

#### Scenario: Windows drive root remains absolute

- **WHEN** the caller parses `C:/acme.toml` and asks for its parent
- **THEN** the result renders as `C:/`, and asking for that root's parent gives no parent

#### Scenario: Drive-relative paths are rejected

- **WHEN** the caller parses `C:` or `C:acme.toml`
- **THEN** parsing fails with the drive-relative rule and does not infer the current directory of drive C

#### Scenario: UNC share is a root

- **WHEN** the caller parses `//server/share/acme.toml` and asks for its parent
- **THEN** the result identifies `//server/share`, and its parent cannot be `//server` or `/`

#### Scenario: Incomplete UNC root is rejected

- **WHEN** the caller parses `//server` or `//server/`
- **THEN** parsing fails with the missing-server-or-share rule

#### Scenario: POSIX and current-directory roots

- **WHEN** the caller parses `/` and `.`, and parses the relative file `acme.toml`
- **THEN** neither root has a parent, and the relative file has `.` as its parent without reading a process directory

### Requirement: Pure typed path operations

Path operations SHALL return parsed paths and preserve their root and exact case.
An operation that can introduce invalid text MUST parse it at its boundary. The
system MUST NOT print and parse an existing path again to join, split, or compare
it. Path operations MUST NOT resolve symbolic links or fold parent segments as
if they were filesystem lookups.

#### Scenario: Child below a drive root

- **WHEN** the caller joins the relative name `acme.toml` to the parsed root `D:/`
- **THEN** the result renders as `D:/acme.toml`, and its parent is the same parsed root

#### Scenario: Absence respects path segments

- **WHEN** a tree records the parsed directory `/w/config` as missing
- **THEN** `/w/config/acme.toml` is missing and `/w/config2/acme.toml` is not made missing by that record

#### Scenario: Relative source uses its explicit base

- **WHEN** the builder gives working directory `C:/w` and the source names relative file `acme.toml`
- **THEN** the protocol requests the typed path `C:/w/acme.toml` without reading process state

### Requirement: Path type does not grant filesystem access

A parsed path SHALL establish only its path rules. It MUST NOT establish that a
file exists, can be read, or belongs to a browser mount. The migrated protocol
MUST retain the existing complete-tree, absence, inaccessible-candidate, and
browser mount rules.

#### Scenario: Valid path outside browser mounts

- **WHEN** a provider requests the parsed path `/outside/acme.toml` and no browser mount contains it
- **THEN** the browser adapter raises the existing outside-mount error before backend access

#### Scenario: Inaccessible candidate still fails visibly

- **WHEN** discovery finds an inaccessible candidate at a valid typed path and the host cannot read it
- **THEN** the host error still passes out of the load, while an unrelated inaccessible entry does not stop discovery

#### Scenario: Complete and missing trees keep their behavior

- **WHEN** a complete tree has no value for a typed path, or an incomplete tree records its directory as missing
- **THEN** loading emits no request for that path and uses the existing absence behavior

## MODIFIED Requirements

### Requirement: Paths use forward slashes

The system SHALL show every path in file trees, reports, origins, and error
messages with `/` separators on every platform. On Windows the host adapter MUST
convert `\` to `/` when it reads paths and MUST convert back only for file-system
calls. Native Windows path input MUST enter the file-tree protocol through an
explicit platform conversion and the path constructor. The conversion MUST NOT
turn drive-relative input into an absolute drive root.

#### Scenario: Windows path in a report

- **WHEN** the native host adapter on Windows loads the explicit file `app.toml` and Windows gives the working directory of drive `C:`, directory `w` with backslash separators
- **THEN** the source report and the origins show the path `C:/w/app.toml`

#### Scenario: Native Windows source path

- **WHEN** a Windows run receives the explicit source `C:\cfg\app.toml` while the supplied working directory is `C:/proj`
- **THEN** boundary conversion gives the typed path `C:/cfg/app.toml`, and the load does not prepend `C:/proj`

#### Scenario: Native UNC source path

- **WHEN** a Windows run receives the native UNC path `\\server\share\acme.toml`
- **THEN** boundary conversion gives the typed path `//server/share/acme.toml` and retains the share root

#### Scenario: Browser rules remain stricter

- **WHEN** a browser mount input contains a backslash, drive prefix, dot segment, parent segment, or empty interior segment
- **THEN** construction still fails before a backend call and does not use Windows native-path conversion

#### Scenario: Browser checks the source spelling before parsing

- **WHEN** a browser load gets the file source `/workspace/./acme.toml`, `/workspace//acme.toml` or `/workspace\acme.toml`, also with the platform Windows
- **THEN** the load fails with the browser invalid-path error before a backend call, although the parsed file-tree path would leave out the dot and empty names and convert the backslash

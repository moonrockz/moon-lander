## ADDED Requirements

### Requirement: Browser execution without Node dependencies

The framework SHALL provide a js browser configuration adapter that uses the pure
configuration core. Its runtime dependency graph MUST NOT import the Node host
adapter or require Node or Bun runtime globals. It MUST NOT provide a UI package.

#### Scenario: A real browser loads and binds configuration

- **WHEN** a browser application loads hosted TOML, applies an explicit override, and binds a typed section
- **THEN** Chromium, Firefox, and WebKit give the expected typed value and source origin without Node shims

#### Scenario: A browser import has no Node runtime

- **WHEN** the browser fixture imports only the core, TOML, and browser packages
- **THEN** the generated application runs with `process`, `require`, and `Bun` absent and has no Node module dependency

#### Scenario: Feasibility cannot be proved

- **WHEN** the first spike cannot run the FFI and promise bridge in a required engine
- **THEN** the failure is recorded and dependent implementation does not start until the owner resolves it

### Requirement: Explicit mounted namespaces

The browser adapter SHALL load only from explicit mounts. Each mount SHALL have
one canonical absolute virtual root. A load MUST reject an empty mount set,
overlapping roots, invalid paths, duplicate entries, and file/directory collisions.
Names MUST match exactly and all reported file paths MUST use `/`.

#### Scenario: Hosted defaults and selected project files share a load

- **WHEN** URL files are mounted at `/defaults` and selected files at `/workspace`, and the builder orders the defaults before the project file
- **THEN** both contribute to one configuration and later values win under the core merge rules

#### Scenario: Roots overlap by path segment

- **WHEN** a mount set contains `/workspace` and `/workspace/vendor`
- **THEN** construction fails before any backend call

#### Scenario: Similar names are separate roots

- **WHEN** a mount set contains `/workspace` and `/workspace2`
- **THEN** each request is routed only to the root that contains that full path

#### Scenario: An input path is invalid

- **WHEN** an entry contains a parent segment, a dot segment, a backslash, a NUL, a drive prefix, or an empty interior segment
- **THEN** construction fails before any backend call

#### Scenario: Inputs name the same file twice

- **WHEN** two entries have the same relative path, or a file path is also used as a directory
- **THEN** construction fails instead of selecting one entry by input order

#### Scenario: A request escapes all mounts

- **WHEN** a source or provider requests `/outside/acme.toml` and no mount contains it
- **THEN** loading raises an outside-mount error without network or storage access for that path

### Requirement: Explicit browser run inputs

The browser adapter SHALL preserve the variable map, working directory, and
platform that the builder holds. For omitted inputs it SHALL use an empty
variable map, the first mount root as working directory, and no inferred platform.
It MUST NOT discover configuration from process state, page parameters, or browser
storage. A supplied working directory MUST be canonical and inside a mount.

#### Scenario: The browser uses supplied variables

- **WHEN** the builder holds `APP_A=1` and an environment source with prefix `APP`
- **THEN** that source contributes `a = 1` using the existing environment mapping rules

#### Scenario: The browser has no supplied variables

- **WHEN** the builder has no variable map and includes a discovered environment source
- **THEN** the run uses an empty map and the source contributes no value

#### Scenario: The working directory is supplied

- **WHEN** the first mount is `/defaults` and the builder gives `/workspace/src` inside another mount
- **THEN** relative files join `/workspace/src` without reading an ambient working directory

### Requirement: Browser file requests produce a bounded snapshot

The browser adapter SHALL answer core `ReadFile` and `ListDir` requests
asynchronously and cache each answer in one load snapshot. It SHALL record missing
paths using `FileTree` absence records. It MUST read only requested file contents,
include exact direct-child listings, and return no partial `Config` after failure.
A repeated request that cannot make progress MUST raise a protocol error.

#### Scenario: An unrelated file is not read

- **WHEN** a selected workspace contains a configuration file and a large unrelated file, and only the configuration file is requested
- **THEN** the adapter reads the configuration file and never reads the unrelated file contents

#### Scenario: A missing directory answers later requests

- **WHEN** the adapter records a requested directory as missing
- **THEN** later descendants are missing without another backend call

#### Scenario: A new load sees an edit

- **WHEN** a live backend changes after one load completes and the application loads again
- **THEN** the second load can see the new text and the first configuration stays unchanged

#### Scenario: A provider repeats an answered request

- **WHEN** a custom provider returns only requests that the load has already answered
- **THEN** the adapter raises a protocol error instead of looping

### Requirement: Hosted configuration uses an authoritative manifest

A URL mount SHALL use a version-1 manifest of relative file paths and optional
empty directories. It SHALL derive listings from that manifest and fetch only
listed files from its authorized base. It MUST encode path segments, omit
credentials, and reject redirects. The parsed base pathname MUST end in `/`.
Invalid bases or manifests MUST fail before fetch; the adapter MUST NOT append a
slash to repair an invalid base. No manifest entry may set an independent URL.

#### Scenario: A base omits its directory slash

- **WHEN** the base is `https://host/configs` and the manifest lists `acme.toml`
- **THEN** construction fails before fetch instead of resolving to `https://host/acme.toml`

#### Scenario: A directory base preserves its path

- **WHEN** the base is `https://host/configs/` and the manifest lists `acme.toml`
- **THEN** the file request uses `https://host/configs/acme.toml`

#### Scenario: A manifest version is unsupported

- **WHEN** the application gives a manifest with an unknown version or invalid shape
- **THEN** mount construction fails before any fetch

#### Scenario: A listed file loads

- **WHEN** a manifest lists `acme.toml` under the authorized base and the server returns valid TOML
- **THEN** loading parses that text and reports its virtual mounted path

#### Scenario: A path is not listed

- **WHEN** discovery asks for a path absent from the manifest
- **THEN** it is missing without a fetch, even if a server might hold a file there

#### Scenario: A listed resource is missing

- **WHEN** a listed file returns HTTP 404
- **THEN** the adapter records absence and an explicit required source raises the core file-not-found error

#### Scenario: Access or transport fails

- **WHEN** a request returns HTTP 403 or 500, redirects, or fails due to CORS or network failure
- **THEN** loading raises the corresponding boundary error instead of reporting a missing file

#### Scenario: A filename needs URL encoding

- **WHEN** a listed filename contains a space or a literal percent character
- **THEN** its URL encodes the filename segment and cannot change the authorized origin or base path

#### Scenario: The manifest names an empty directory

- **WHEN** a manifest declares an empty directory
- **THEN** listing that directory gives an empty listing without a network directory probe

### Requirement: Selected files form a read-only mount

The browser adapter SHALL accept explicit relative-path and `File` pairs supplied
by the application. It SHALL infer intermediate directories and obtain requested
text through browser File APIs. It MUST NOT open a picker, guess a path prefix,
write selected files, or upload their contents.

#### Scenario: File input fallback loads a project

- **WHEN** an application maps actual HTML file-input files to relative paths in a mount
- **THEN** configuration loads in Chromium, Firefox, and WebKit with virtual paths in reports and origins

#### Scenario: Nested selected files support discovery

- **WHEN** selected files include `acme.toml` and `src/main.mbt`, and the working directory is the mounted `src` directory
- **THEN** bounded conventions discover the root `acme.toml` using inferred listings

#### Scenario: A selected name differs in case

- **WHEN** the mount contains `Acme.toml` and discovery searches for `acme.toml`
- **THEN** the candidate does not match

### Requirement: Directory handles remain read-only and permission-bound

The browser adapter SHALL accept a caller-supplied directory handle and resolve
requested paths below it one segment at a time. Read traversal MUST NOT create
entries, open a picker, or request permission. Missing or wrong-kind entries SHALL
be absent. Denied or revoked access MUST raise an error without backend fallback.

#### Scenario: A real handle answers file and listing requests

- **WHEN** the caller supplies a real directory handle with nested configuration files
- **THEN** discovery and loading use the handle and produce the same value and virtual origins as an equivalent selected-file mount

#### Scenario: A handle loses permission

- **WHEN** a requested handle operation fails with a permission denial
- **THEN** loading raises permission-denied and does not select another mount or store

#### Scenario: The native picker is unavailable

- **WHEN** the browser has no native directory-picker API but the application supplies selected files
- **THEN** the selected-file path still works and the adapter does not claim that OPFS handle support proves picker support

### Requirement: Browser workspace discovery stays inside its mount

The browser workspace convention helper SHALL disable system, user-config, and
app-home directory sources and set the boundary to its mount root. It SHALL retain
project and local override behavior inside that boundary. It MUST NOT infer a
machine directory from an injected variable. Normal core ambiguity, reports, and
provenance rules SHALL remain in effect.

#### Scenario: A parent outside the mount is not searched

- **WHEN** the application uses browser workspace conventions from a nested mounted directory
- **THEN** discovery stops at the mount root without an outside listing request

#### Scenario: Injected home variables do not grant filesystem access

- **WHEN** the variable map names HOME or an application home outside the mount
- **THEN** browser workspace conventions do not use those locations as machine-directory sources

#### Scenario: Local overrides retain precedence

- **WHEN** the mounted project holds a primary and a local override with the same key
- **THEN** the existing core source order chooses the override and records its virtual file origin

#### Scenario: Candidates are ambiguous

- **WHEN** a mounted location holds multiple registered primary candidates
- **THEN** loading raises the core ambiguity error with virtual candidate paths

### Requirement: Browser persistence is explicit and scoped

The framework SHALL provide explicit OPFS storage operations below a library-owned
application namespace. Opening or writing a store MUST be a caller action. Loads
and read-only mounts MUST NOT create or change storage entries. Writes SHALL await
completion before success, and removal SHALL be limited to a named file inside the
store. Unsupported APIs, access denial, quota failure, and failed close MUST be
errors; they MUST NOT cause an implicit storage fallback.

#### Scenario: A saved configuration survives reload

- **WHEN** the caller writes configuration text, awaits success, reloads the same origin, and mounts that store
- **THEN** loading reads the saved value and records its mounted source path

#### Scenario: Namespaces are independent

- **WHEN** two namespaces hold the same relative filename
- **THEN** reading or removing a file in one does not change the other

#### Scenario: A write fails

- **WHEN** a storage write or close fails, including a quota failure
- **THEN** the operation raises an error and does not report a successful save

#### Scenario: Storage is unavailable

- **WHEN** required OPFS APIs are absent or blocked
- **THEN** opening or using the store raises an unsupported or access error without trying localStorage or IndexedDB

#### Scenario: Load has no persistence side effects

- **WHEN** the caller loads configuration through URL, selected-file, or directory mounts
- **THEN** no OPFS namespace or file is created and no backend is written

### Requirement: Browser store mounts use explicit virtual roots

`open_store(namespace, root~)` SHALL require and validate both the namespace and a
canonical absolute virtual root before storage access. The returned read mount
SHALL use that root; the root MUST NOT change the backing namespace.

#### Scenario: A store uses the supplied virtual root

- **WHEN** the caller opens a namespace at `/state`, writes `acme.toml`, and mounts that store
- **THEN** the stored file is available as `/state/acme.toml` and that path appears in its origin

#### Scenario: A namespace is reopened at a different root

- **WHEN** the same namespace is reopened with virtual root `/restored`
- **THEN** its saved files are available under `/restored` without creating a different backing namespace

#### Scenario: A store root is invalid

- **WHEN** a caller gives a relative or otherwise invalid virtual root
- **THEN** opening the store fails before any OPFS access or directory creation

### Requirement: Browser failures retain type and source information

Boundary failures SHALL use a typed `BrowserError` with operation and virtual path
fields where relevant. Core `ConfigError` values MUST pass through unchanged.
Neither browser error details nor source reports may expose configuration contents,
credentials, or sensitive backend URLs.

#### Scenario: A parse error retains its origin

- **WHEN** a mounted TOML file is invalid
- **THEN** the caller receives the core parse error with its virtual file origin and available position

#### Scenario: A binding error retains its source

- **WHEN** a mounted file supplies a value that cannot bind to the requested type
- **THEN** the caller receives the core binding error with the failing path and virtual source origin

### Requirement: Limits and cancellation stop browser I/O

A load SHALL enforce caller-supplied positive limits or defaults of 4096 observed
entries, 8 MiB of total loaded UTF-8 text, and 8192 distinct requests. It SHALL honor
an optional abort signal. A limit, abort, or streaming failure MUST stop further
requests and return no partial configuration. Acquired reader locks MUST be released; any
possibly live response MUST be cancelled or its fetch aborted first. Lock release
alone is not cancellation. Cleanup MUST preserve the original error.

#### Scenario: A mount exceeds its entry limit

- **WHEN** a manifest or selected-file mount exceeds the entry limit
- **THEN** it fails before reading file content

#### Scenario: A response omits its size

- **WHEN** an HTTP response without Content-Length streams more than the remaining byte limit
- **THEN** reading stops at the limit, the stream is cancelled or its fetch is aborted, the fixture observes upstream cancellation or connection closure, and no next file is fetched

#### Scenario: Decoding fails while a response is live

- **WHEN** decoding fails after a reader is acquired and the response is still live
- **THEN** the response is cancelled or its fetch aborted, the fixture observes upstream stopping, the lock is released, and no next file is fetched

#### Scenario: Reading an errored stream fails

- **WHEN** a body read rejects because the response stream has errored
- **THEN** its reader lock is released and the original read failure is returned

#### Scenario: Cleanup also fails

- **WHEN** cancellation or lock release fails while handling a streaming failure
- **THEN** the original load error is preserved and remaining reader cleanup is attempted

#### Scenario: Loading is aborted

- **WHEN** the caller aborts during a pending file read or fetch
- **THEN** loading terminates with abort failure, starts no next request, and returns no configuration

### Requirement: Browser support has a required execution gate

The first implementation story SHALL establish a real-browser harness and CI gate
for Chromium, Firefox, and WebKit. Each later backend story SHALL add its own
acceptance coverage to that gate. The framework SHALL retain all existing checks,
validate generated FFI freshness, and verify portable core behavior on all four
MoonBit targets. Missing required engines or tests MUST fail rather than skip.

#### Scenario: A browser regression blocks merge

- **WHEN** a required engine fails a selected browser assertion or cannot run
- **THEN** the browser task exits nonzero and `ci-ok` cannot succeed

#### Scenario: Generated browser code is stale

- **WHEN** a TypeScript behavior change is not reflected in the checked-in browser FFI
- **THEN** the freshness check exits nonzero without rewriting the generated file

#### Scenario: Equivalent snapshots have equivalent results

- **WHEN** the same snapshot, formats, variable map, working directory, and ordered sources load in browser js and in the four core targets
- **THEN** values, origins, reports, and representative typed failures agree

#### Scenario: An ordinary consumer does not import browser support

- **WHEN** an unrelated consumer builds without the browser package
- **THEN** it needs neither browser APIs nor browser adapter build tooling

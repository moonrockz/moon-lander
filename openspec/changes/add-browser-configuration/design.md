# Design: add-browser-configuration

## Context

See `proposal.md` for the purpose and scope. The requirements are in
`specs/browser-configuration/spec.md`.

`@config.load(builder, tree)` is pure. It returns `Done(config)` or requests
`ReadFile(path)` and `ListDir(path)`. `FileTree` stores file text, exact-name
listings, and absence records. The Node adapter uses synchronous `node:fs` calls;
its generated factory also uses `process.getBuiltinModule`. That package cannot
be the browser entry point.

The pinned async library has a js promise bridge in `async/js_async`. Its browser
execution with the generated adapter is not yet proved. Group 1 must prove that
boundary before a public browser API is implemented.

All decisions below are **Call (this change)**. They implement the browser path
requested by the owner. A failed feasibility gate returns to the owner; it must
not be hidden by a Node shim or by reducing the browser test matrix.

## Goals / Non-Goals

Each story must leave a complete, tested path that can merge on its own. Keep the
core portable and keep browser capabilities explicit. Do not expand the native or
Node adapter while implementing browser support. See the proposal for exclusions.

## Decisions

### D1. Separate the execution environment from the compiler target

Add `moonrockz/moon-lander/config/browser`, supported on js. Keep `config/host` as
the native and Node/Bun adapter. A browser consumer imports `config/browser` and
never needs `config/host`, `core/env`, or a Node compatibility layer.

The pure core and the data models still build and test on wasm, wasm-gc, js, and
native. Browser execution in this change uses js output. `Platform` remains an
operating-system value; do not add a `Browser` case or infer an OS from user-agent
text. Preserve a platform that the builder explicitly holds, but infer none.

An automatic Node/browser branch inside the existing adapter would load Node
code too early and would hide which file access the application permits. Separate
imports make that boundary testable.

### D2. A mount gives authority to a finite virtual namespace

A **mount** maps one absolute virtual root to browser-accessible files. It does
not identify an OS path. A **manifest** lists the file paths and optional empty
directories available in a URL mount. A **load snapshot** is the `FileTree` built
from the answers obtained during one load. It is not an atomic snapshot of a live
filesystem.

Use opaque, immutable public `Mount` values. Each load accepts a non-empty list
of mounts. Roots must be distinct and must not overlap at a path-segment boundary.
For example, `/workspace` and `/defaults` can coexist; `/workspace` and
`/workspace/vendor` cannot. `/workspace2` does not overlap `/workspace`.

All public paths use `/`. Roots and working directories are absolute. Entry paths
are relative to their root. Reject NUL, backslash, drive prefixes, empty interior
segments, and `.` or `..` segments. Reject duplicate entries, a file used as an
ancestor directory, and file/directory name collisions before I/O. Use exact,
case-sensitive names. Do not lowercase or URL-decode virtual paths.

Before each file request, select its mount by segment containment. Reject a
request outside every mount before any network or storage call. An outside path
is an error, not an absence record. Directory listings include only direct
children and are sorted. Each mount owns its own absence records.

Multiple mounts let an application merge hosted defaults at `/defaults`, selected
project files at `/workspace`, and persisted overrides at `/state` in one builder.
The builder still owns source order. Mount order gives no source priority.

### D3. Use the existing pure request protocol

The intended public operations are:

| Operation | Input and result |
| --- | --- |
| `from_urls` | Base URL, version-1 manifest, virtual root; gives a read-only mount |
| `from_files` | Explicit relative-path and browser `File` pairs, root; gives a mount |
| `from_directory` | Caller-supplied directory handle, root; gives a read-only mount |
| `load` | Builder, mounts, limits, optional abort signal; gives `Config` asynchronously |
| `workspace` | Conventions and mount; gives conventions confined to that root |
| `open_store` | Application namespace and root; opens an OPFS store and its read mount |
| `write_text`, `remove` | Explicit store, relative path, and text where applicable |

Use external wrapper types for `File`, directory handles, and abort signals. Do
not expose DOM elements or make an application construct raw JavaScript reply
objects. Group 1 proves the FFI representation and promise bridge, and records the
exact compilable call shapes before group 2 starts. These operation names and
semantics are fixed; that proof does not authorize a different architecture.

`load` uses the builder variable map, or an explicit empty map when none was given.
It uses the builder working directory, or the first mount root when none was given.
Validate that directory before I/O. Do not read `process.env`, `process.cwd`, page
URL query parameters, browser storage, or other ambient configuration to fill them.

Start a new incomplete `FileTree` for each load. For each `Need`, await the selected
backend, store the listing, text, or absence, and call the core again. Cache answers
only for that load. Read a file only when requested; a selected directory can hold
large files that configuration does not use. Do not scan or read the full workspace.
A custom provider that keeps requesting already answered inputs must produce a
protocol error instead of an infinite loop.

Sequential reads are the first implementation. Parallel reads are unnecessary for
correctness and would complicate limits and cancellation. Do not change parse,
merge, ordering, binding, reports, or provenance. A new load can observe new backend
content; a completed `Config` remains unchanged.

### D4. Build a browser-only TypeScript boundary

Put browser API calls in TypeScript under `adapters/browser`. Bun builds them with
`--target=browser`. A moonx script generates and checks the checked-in inline
MoonBit FFI file. Prove a browser-compatible factory in group 1; do not copy the
Node factory's `require`, `module`, or `process.getBuiltinModule` wrapper.

Use `moonbitlang/async` and its js promise bridge on the MoonBit side. Catch Web API
failures at the boundary and convert them into data that MoonBit can raise. No JS
exception may bypass the normal error path. Keep the library bundle separate from
test fixture code and the Playwright runner.

Add `build:browser-adapter` and `check:browser-adapter`. Ordinary consumer builds
use the checked-in file and do not require Bun. The freshness regression must edit
TypeScript behavior, observe a nonzero check, and verify that checking does not
rewrite generated files. The build graph and real browser test must reject Node
imports and execution that relies on `process`, `require`, or `Bun` globals.

### D5. URL mounts use an authoritative manifest

The manifest is version 1, with `files` and optional `directories`, both arrays of
relative paths. The application may construct it or obtain it from its server.
Derive all parent directory listings from these paths. Preserve declared empty
directories. A path absent from the manifest is missing without a fetch. Do not
infer listings by probing arbitrary URLs or depend on web-server directory indexes.

The base must be an HTTP or HTTPS directory URL with no credentials, query, or
fragment. The caller explicitly authorizes that base, including a cross-origin
base. Construct each file URL by encoding each validated virtual path segment.
No entry can supply its own URL. Set `credentials: "omit"` and `redirect: "error"`.
This bounds the requested namespace without relying on server path normalization.
Applications that need a custom authenticated fetch can obtain a browser `File`
and use an explicit file mount.

A 404 records absence. All other non-success statuses are HTTP errors. A CORS,
network, decoding, or redirect failure is an I/O error. No denied or failed request
is silently converted into a missing file. Origins and errors use virtual paths;
do not put credentials or response bodies in error details.

### D6. Selected files and handles have different lifetimes

`from_files` takes `File` objects that the application already holds. The caller
maps `File.name` or `webkitRelativePath` into explicit relative paths; the adapter
does not strip a top-level directory by guessing. Infer intermediate directories,
then use `File.text()` only for requested files. Do not upload selected files.

`from_directory` accepts an already obtained handle. It never opens a picker or
requests permission. Traverse one path segment at a time with `create: false`.
Use `entries()` for exact-name listings, and `getFile()` followed by `text()` for
reads. A missing entry or an incompatible file/directory kind records absence.
Permission denial or revocation raises an error. It must not try another mount or
fall back to a different store.

Moonbase chooses a native picker where available, or an HTML file/directory input
fallback. These are different capabilities. Availability of OPFS directory handles
does not imply availability of `showDirectoryPicker`. Tests can use real OPFS
handles to prove the handle contract without claiming to test OS picker UI.

### D7. Discovery is confined to a mounted workspace

`workspace(conventions, mount)` removes `SystemDir`, `UserConfigDir`, and `AppHome`,
and sets the discovery boundary to the mount root. It does not imply isolated
mode: normal project, local-override, and user-override files within the workspace
still work. The application can then select a narrower boundary with the normal
conventions API. The adapter's mount check remains in force in either case.

This helper is explicit. A caller that deliberately supplies other conventions or
absolute file sources still gets confinement errors for outside requests. Never
map `/etc`, a real user home, or an environment-provided app home to browser disk
access. Existing `SourceKind` and `FileRole` values remain sufficient; reports and
origins identify `/defaults/acme.toml`, `/workspace/acme.toml`, or another virtual
source path. Do not add backend URLs or handles to the core data model.

### D8. OPFS writes require an explicit scoped store

`open_store(namespace)` uses an application namespace below a fixed library-owned
OPFS directory. The namespace is one validated path segment; it cannot name the
origin root or a parent directory. Opening a store is an explicit caller action,
not a side effect of loading configuration. The store supplies a read mount that
uses the directory backend from group 4.

`write_text` creates parent directories only inside that store, writes text, and
awaits close before reporting success. `remove` removes only a named file inside
the store. Loads and directory mounts never write. Saving text does not require
the unfinished configuration render helpers and does not resolve secrets.

If OPFS or its write API is unavailable, raise `Unsupported`. Do not silently
substitute localStorage or IndexedDB. Quota, denied access, and failed close are
errors, and no success may be reported for a partial write. The API does not
promise multi-file transactions or survival after site data is cleared. Reload
within the same origin must read a successful prior write. Separate namespaces
must remain independent.

### D9. Errors and limits are part of the public contract

Keep browser boundary errors in `BrowserError`, with labelled fields for the
operation and virtual path where relevant. Cases cover invalid mount/path,
outside mount, unsupported capability, permission denial, HTTP status, I/O failure,
limit exceeded, abort, and protocol/no-progress. Preserve core `ConfigError` values
unchanged so parse, ambiguity, and binding failures retain their normal origins.
Error details must exclude configuration contents and sensitive URLs.

Use default limits of 4096 observed entries, 8 MiB of total loaded UTF-8 text, and
8192 distinct requests per load. The caller can provide other positive limits.
Count each unique virtual entry once, including inferred parents but excluding
mount roots. Count manifest and selected-file entries before I/O; count directory
entries while listing. Cached entries do not consume the limit again. Check known file sizes before reading and actual UTF-8 size afterward.
For HTTP, enforce the byte limit while streaming the response, including when
Content-Length is absent or incorrect; release or cancel the reader on failure.
Do not fetch the next file after a limit or abort failure. Pass the abort signal to fetch. Race non-abortable File operations against abort
for load completion, ignore any late result, and release signal listeners. The
browser may finish that underlying read, but the adapter must not accept its
result or start another request after abort.
No failure returns a partial `Config`.

### D10. Prove the browser path from the first PR

Use one unpublished test application and a loopback HTTP fixture server. The
Playwright runner runs in Node/Bun, but the configuration library runs inside a
real browser page. Do not accept js tests run on Node as browser evidence.

Pin Playwright exactly in mise and in the private harness dependency, commit its
Bun lockfile, and verify that the versions agree. Its browser builds form the
recorded test matrix. Use Chromium, Firefox, and WebKit on one Linux CI runner;
this checks engine behavior without adding another host-OS matrix. Test baseline
features in all three engines. An engine or feature needed by the baseline that
cannot start is a failure, not a skipped pass.

Use moonx tasks for installation, build, server/process lifecycle, execution, and
failure propagation. Playwright test code and fixture HTML stay under `tests/`.
Add `browsers:install` and `test:browser`. Build the browser fixture once for the
three engine projects. Keep artifacts in one job; no cross-job transfer is needed.
Document browser installation before local `mise run check`, which includes
`test:browser` and `check:browser-adapter` once those tasks exist.

Add the browser job to the existing `ci-ok` dependency list on the same CI events.
Keep every existing gate. The owner is the PR maintainer, and a failure blocks
merge. Do not defer the only test of a new browser backend to a later integration
story. Each backend story adds its tests to this already required category.

The expected added job time is 2-5 minutes, mainly browser installation; this is an
estimate. Group 1 must record actual installation, build, suite, and total times.
Keep timeout and worker limits explicit. No nightly job or release workflow is
needed for this change. Release evidence and artifact promotion are out of scope.

## Landing plan

| Group | Deliverable | Blocked by |
| --- | --- | --- |
| 1 | Real-browser feasibility spike, shared harness, and CI gate | Landed core, binding, and Node adapter foundations |
| 2 | Hosted configuration with production mounts and bounded request loop | 1 |
| 3 | Selected project files, bounded discovery, and hosted/local merging | 2, landed convention boundaries |
| 4 | Live read-only directory-handle loading and denial errors | 3 |
| 5 | Scoped OPFS save, reload, and explicit failure behavior | 4 |
| 6 | Cross-target reference parity and final consumer/readiness checks | 5 |

Land the planning PR before implementation. Each group is an AFK implementation
story with one bead and one PR. Group 1 is a
spike with a hard feasibility result. If it fails, record the compiler/runtime
failure and return to the owner before dependent stories start. Later groups must
not require unimplemented YAML, JSON5, Ion, render, secret, or host-lifecycle work.
Use TOML, existing overrides, and current typed binding for the complete path.

Each PR must pass strict OpenSpec validation, formatting, `mise run check`, and
its browser tests. Its task boxes are ticked only after verification. Close and
sync the bead with the PR, commit range, and test evidence. Group 6 compares the
browser js result with the same explicit snapshot on all four core targets. It
also builds an unrelated consumer without the browser import to prove that the
browser tooling and Web APIs do not become a dependency of ordinary consumers.
After group 6 merges, its PR maintainer opens a separate archive-only documentation
PR and validates the accepted specification. Keep the epic open until that
maintenance PR merges. Archiving is not a condition that must be completed inside
the final implementation PR.

## Risks / Trade-offs

- Promise or generated-FFI integration can fail in a real browser. Group 1 proves
  it before public APIs or dependent work are implemented.
- Native directory pickers vary by browser. Keep picker UI outside this library,
  test real File input fallback in all engines, and detect picker support in
  consumer examples without inferring it from OPFS support.
- A live directory can change during a load. Cache each answer for that load and
  document this consistency level; do not claim an atomic filesystem snapshot.
- Browser storage can be unavailable or evicted. Return an explicit error and
  preserve caller control over persistence and recovery.
- A manifest can be stale. Treat the manifest as the authorized namespace, then
  record a real 404 as missing while retaining other HTTP failures.

## Migration and rollback

All public additions are opt-in. Existing native, Node/Bun, and injected-tree
consumers keep their imports and behavior. Before a browser implementation lands,
add the narrow Web API exception to project rules. Consumers can stop importing
`config/browser` and inject a `FileTree` directly without a data migration. A
rollback must not clear OPFS namespaces or delete selected user files.

## References

- [Current pure loader](../../../pkgs/lander/config/load.mbt)
- [Current file snapshot](../../../pkgs/lander/config/file_tree.mbt)
- [File System Access and picker permissions](https://developer.chrome.com/docs/capabilities/web-apis/file-system-access)
- [Origin private file system](https://developer.mozilla.org/en-US/docs/Web/API/File_System_API/Origin_private_file_system)
- [Fetch and response handling](https://developer.mozilla.org/en-US/docs/Web/API/Fetch_API/Using_Fetch)
- [Playwright file inputs](https://playwright.dev/docs/input)
- [Playwright browser builds](https://playwright.dev/docs/browsers)

# Design: add-browser-configuration

## Context

See `proposal.md` for the purpose and scope. The requirements are in
`specs/browser-configuration/spec.md`.

`@config.load(builder, tree)` is pure. It returns `Done(config)` or requests
`ReadFile(path)` and `ListDir(path)`. `FileTree` stores file text, exact-name
listings, and absence records. The Node adapter uses synchronous `node:fs` calls;
its generated factory also uses `process.getBuiltinModule`. That package cannot
be the browser entry point.

The pinned async library has a js promise bridge in `async/js_async`. Group 1's
unpublished fixture proves its browser execution with a generated adapter. See
the feasibility evidence below. The public browser API remains group 2 work.

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
| `open_store(namespace, root~)` | Application namespace and required virtual root; opens an OPFS store and its read mount |
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
fragment. Its parsed pathname must end in `/`. Reject a base without that trailing
slash before any fetch; do not guess a directory by appending a slash. Thus
`https://host/configs` is invalid, while `https://host/configs/` maps `acme.toml`
to `https://host/configs/acme.toml`.

The caller explicitly authorizes that base, including a cross-origin base.
Construct each file URL by encoding each validated virtual path segment.
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

`open_store(namespace, root~)` requires an application namespace and a canonical
absolute virtual root. Validate both before any storage access. The namespace is
one validated path segment below a fixed library-owned OPFS directory; it cannot
name the origin root or a parent directory. The supplied root locates the read
mount and uses the directory backend from group 4. It does not change the backing
namespace: reopening the same namespace at `/restored` instead of `/state` reads
the same stored files and reports their new virtual paths.

Opening a store is an explicit caller action, not a side effect of loading
configuration. No virtual root is inferred from the namespace or hard-coded by
the adapter.

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
entries while listing. Cached entries do not consume the limit again. Check known
file sizes before reading and actual UTF-8 size afterward.
For HTTP, enforce the byte limit while streaming the response, including when
Content-Length is absent or incorrect. Release every acquired reader lock after
normal completion or any streaming failure, including read and decoding errors.
If a failed response may still be live, actively cancel it with `reader.cancel()`
or abort its fetch before releasing the lock. An already errored stream needs
lock release; `releaseLock()` alone does not cancel a live response. Preserve the
original load error if cleanup also fails. The oversized-response and decoding
failure fixtures must observe upstream cancellation or connection closure, not
only that the load rejected; an injected read error must leave no locked reader.

Do not fetch the next file after a limit or abort failure. Pass the abort signal
to fetch. Race non-abortable File operations against abort
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

## Group 1 feasibility evidence

The unpublished `tests/browser-fixture` imports `config`, `config/formats/toml`,
and `async/js_async`. `tests/browser` holds the private Playwright harness. The
HTTP server, build, installation, and process lifecycle use moonx scripts.
No public browser package is introduced by the spike.

The compilable bridge uses external object wrappers and a cancellable promise:

```moonbit
#external
priv type Adapter
#external
priv type Reply
extern "js" fn Adapter::fetch_text(
  self : Adapter,
  url : String,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[Reply] =
  #|(adapter, url, signal) => adapter.fetchText(url, signal)
```

MoonBit awaits that call with
`@js_async.run_promise(signal => adapter.fetch_text(url, signal))`. The TypeScript
boundary catches Web API errors and returns tagged reply data. MoonBit inspects
reply properties through `extern "js"` accessors, fills the requested virtual
file in `FileTree`, reruns the pure loader, and binds the resulting section.

The generated factory supplies a lexical `receiveBrowserAdapter` callback. Bun
bundles a small entry which imports the adapter and calls that callback. The
factory returns the received object. This tested `--target=browser --format=iife`
shape uses no `require`, `module`, `process`, or browser global registration.
The pinned Bun CLI did not supply an export object with `--global-name`; do not
depend on that unrecognized option. The final MoonBit application is also bundled
with the browser target and checked for forbidden runtime dependencies.

The test application exports its entry through
`@js_async.Promise::from_async(() => probe(url))`. That export converts raised
errors to generic `Error` text. The fixture explicitly uses `ConfigError::message`
at this JavaScript presentation boundary to retain source paths. The production
MoonBit browser loader must preserve typed `ConfigError` values inside MoonBit;
the fixture's text export is not a replacement error API.

Local proof on macOS arm64 with Playwright `1.64.1` passed six tests across
Chromium `156.0.8078.4`, Firefox `157.0`, and WebKit `27.2`. The browser page fetches
hosted TOML, applies port override `9000`, binds a typed server record, and reports
`/workspace/acme.toml` as the host value's origin. All three runtime globals are
absent. HTTP 404, malformed TOML, and invalid typed data reject through the bridge.
The successful suite took 2.9 seconds, build 0.2 seconds, total 3.1 seconds in one
representative warm run. Installing the missing Firefox and WebKit builds took
17.8 seconds with Chromium already cached; this is not a cold-install measure.

Negative verification reuses that one application artifact. It requires the
specific assertion-failure marker with three failing projects, then six engine
launch failures with an empty browser installation directory. An arbitrary
nonzero result cannot pass verification. Each run checks that its loopback
listener no longer accepts connections after structured cleanup. Reader-closed
errors from browser keep-alive disconnects close only their connection. The server
task is `no_wait=true`, so normal task-group exit cancels and joins it.

The browser job is a separate Linux category because Node tests cannot execute
the browser Web APIs or prove the page's runtime environment. It runs on the
existing PR, main-push, merge-group, and manual events, depends on lint, and is a
required `ci-ok` dependency. It installs the locked harness and all three engines,
then runs the success and negative checks with one build. All prior gates remain.
The PR maintainer owns failures, which block merge. Cold Linux job timings and
the current-head CI run are recorded in the bead when verified. No release or
publishing behavior changes.

The first Linux execution passed in CI run `39619728998`, browser job
`119290058615`, on implementation commit `481c24e`. All 17 checks passed. The
browser job used 21 seconds for pinned tool setup, 45.0 seconds for the locked
harness, engines and OS dependencies, 6.9 seconds for the application build, and
7.4 seconds for the successful browser suite. Both negative checks then passed
with listener cleanup; the test step took 27 seconds including compilation and
all runs. Total job time was 98 seconds, excluding queue delay. Linux reported
the same three engine versions as the local proof. Playwright's pinned builds
are Chromium/headless shell `1248`, Firefox `1555`, and WebKit `2370`. This is one
cold Linux sample with no browser cache configured, not a timing guarantee.

## Group 2 production URL mounts

The public js-only package is `config/browser`. `from_urls(base, manifest, root~)`
accepts a JSON manifest with exactly `version: 1`, `files`, and optional
`directories`. Paths are string arrays. Unknown fields and invalid shapes fail
before fetch. The immutable opaque `Mount` exposes only `root()`. Constructor
validation owns duplicate/collision checks and inferred directories; load-time
limits count every unique entry before any backend call. Empty manifests are
valid, while an empty mount set is not.

`limits(entries?, bytes?, requests?)` creates immutable positive per-load bounds.
`load(builder, mounts, limits?, signal?)` copies the mount array before awaiting,
preserves explicit builder inputs, and uses the proven `async/js_async` bridge.
`AbortController` and `AbortSignal` are aliases for that library's external
wrappers. Each request batch is checked for canonical paths, containment and
remaining request quota before reads begin. Answers are cached in a fresh
`FileTree`; a request batch with no new answer raises `Protocol`. Listings use
explicit lexical code-unit comparison rather than MoonBit's shortlex comparison.

Policy, mount data and the request loop are MoonBit. The TypeScript boundary
exports only URL normalization, required-capability detection and HTTP text reads.
Its generated factory lives in the public package; generated fixture helpers
remain in the unpublished tests module. A consumer compiles the checked-in FFI
with MoonBit, without Bun. A task-script test forces a fresh consumer target with
only the MoonBit compiler directory on `PATH`. The freshness regression changes
TypeScript behavior, checks for a nonzero result without output mutation, and
rejects a Node import with Bun's browser target.

The HTTP adapter encodes each validated relative path segment, omits credentials,
and rejects redirects. It counts streamed bytes and final UTF-8 text across files,
independently of Content-Length. Fatal decoding rejects malformed UTF-8; BOM text
is retained as it is in file inputs. Both caller and task signals control an
internal fetch controller. Failures abort transport before cancellation and lock
release; errored reads and failed cancellation still attempt remaining cleanup.
Boundary replies contain only stable failure classes, never browser exception
text, backend URLs or response bodies. MoonBit raises labelled `BrowserError`
cases and leaves `ConfigError` values unchanged. Invalid path text is not echoed.

The runnable guide is `config/browser/README.mbt.md`, with an unpublished headless
consumer in `tests/browser-consumer`. Both that example and the acceptance fixture
are compiled once and reused by all three engines. The existing browser CI
category is now named Browser configuration and retains the same required
`browser` dependency in `ci-ok`; production freshness is added to the lint job.
No existing check is removed. Negative harness checks select the original smoke
file, so extra acceptance tests do not change their expected failure counts.

The production acceptance suite covers the group 2 namespace/run-input/manifest
scenarios, ordering, binding, reports, exact virtual origins, empty directories,
404/403/500, credential omission, redirects, real CORS and server disconnects,
encoded filenames and literal percent-encoded segments, per-load snapshots,
entry/request/UTF-8 budgets and faulty providers. Real streamed responses verify
upstream stopping for byte limits, decoding errors and abort. Controlled streams
verify false size headers, errored readers, cancellation/release failures and
original-error preservation. A compressed HTTP response verifies that wire size
cannot bypass the decoded-byte budget. Available parse positions and binding
blame are checked before the fixture's JavaScript presentation conversion.

Group 2 did not implement selected files, browser workspace conventions,
directory handles, OPFS operations or cross-target consumer parity. Groups 3-6
add them.

## Group 3 selected files and workspace discovery

`from_files(files, root~)` takes an array of relative-path and external `File`
pairs. `File` is an external wrapper with `name()` and `webkit_relative_path()`
accessors that do not read contents. The mount reuses the manifest namespace
rules, so duplicates, collisions, file ancestors and the entry budget fail before
any read. A private `Backend` selects the HTTP or File read for each mount, and
`load` checks the Web APIs of each backend. A selected-file load does not need
`fetch`.

The TypeScript boundary checks `File.size` against the remaining byte budget,
then calls `File.text()` and checks the UTF-8 size. It races that read against
both abort signals, ignores a late result and removes its listeners. A rejected
read gives `Io`, or `PermissionDenied` for `NotAllowedError` and `SecurityError`.
`File.text()` uses the browser UTF-8 decoding: it replaces malformed bytes and
removes a leading byte order mark. Hosted files keep fatal decoding.

`workspace(conventions, mount)` uses only the public conventions API:
`without(SystemDir)`, `without(UserConfigDir)`, `without(AppHome)` and
`boundary(mount.root())`. The core still rejects an explicit file source after
discovery because of source priority. The tests show builder order with two
explicit files, and with hosted defaults before workspace discovery.

The acceptance fixture page has plain file and directory inputs. Playwright puts
real files into them in all three engines, including a 9 MiB unrelated file and
a real directory. A spy on `Blob` content methods records each read. The
consumer example maps `File.name` and `webkitRelativePath` explicitly and merges
hosted defaults with the selected project.

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
- [Relative URL resolution](https://developer.mozilla.org/en-US/docs/Web/API/URL_API/Resolving_relative_references)
- [Reader cancellation](https://developer.mozilla.org/en-US/docs/Web/API/ReadableStreamDefaultReader/cancel)
- [Reader lock release](https://developer.mozilla.org/en-US/docs/Web/API/ReadableStreamDefaultReader/releaseLock)
- [Playwright file inputs](https://playwright.dev/docs/input)
- [Playwright browser builds](https://playwright.dev/docs/browsers)

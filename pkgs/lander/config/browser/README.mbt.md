# Browser configuration

Import `moonrockz/moon-lander/config/browser` as `@browser` for js output that
runs in a browser. The configuration core remains portable across all four
targets. The browser package has no Node/Bun runtime dependency or UI.

## Hosted configuration

The caller authorizes an HTTP(S) directory base and a version-1 manifest. The
base pathname must end in `/`; credentials, queries and fragments are rejected.
Each manifest entry is a relative path, never an independent URL.

```mbt check
test "construct a hosted mount without fetching" {
  let mount = @browser.from_urls(
    "https://example.org/configs/",
    { "version": 1, "files": ["acme.toml"], "directories": ["empty"] },
    root="/workspace",
  )
  assert_eq(mount.root(), "/workspace")
}
```

Add files to the normal configuration builder, then await
`@browser.load(builder, mounts)`. The headless executable in
[`tests/browser-consumer`](../../../../tests/browser-consumer/main.mbt) is a
compiled example. It registers `loadHostedServer(base)` in its browser page:

```moonbit
let mount = @browser.from_urls(
  base,
  { "version": 1, "files": ["acme.toml"] },
  root="/workspace",
)
let builder = @config.builder()
  |> @config.format(@toml.format())
  |> @config.file("acme.toml")
  |> @config.overrides([("server.port", @config.int(9000))])
let config = @browser.load(builder, [mount])
let server : Server = @config.bind(config, "server")
```

Run `mise run test:browser` from this repository to execute that example and the
production acceptance suite in Chromium, Firefox and WebKit. Install the pinned
engines first with `mise run browsers:install`, adding `-- --with-deps` on Linux.
The loopback fixture serves `acme.toml`; the example returns
`browser.example:9000`. The package guides compile under the ordinary js tests.

## Selected project files

`@browser.from_files(files, root~)` mounts explicit relative-path and
`@browser.File` pairs. The application gets each `File` from its own picker or
HTML input. The package opens no picker and has no UI. Map `File.name` or
`webkitRelativePath` to a relative path yourself; the adapter does not remove a
directory prefix by guessing. `File::name()` and `File::webkit_relative_path()`
read these names without reading the contents.

```moonbit
// A plain file input gives a name. A directory input gives the selected
// directory as the first segment, and this application removes it.
let relative = match file.webkit_relative_path() {
  "" => file.name()
  path =>
    match path.find("/") {
      Some(index) => path[index + 1:].to_owned()
      None => path
    }
}
let project = @browser.from_files([(relative, file)], root="/workspace")
```

Parent listings come from the paths. Duplicates, file/directory collisions and
invalid paths fail before any read. A load reads a file with `File.text()` only
when the core requests it, so a large unrelated file is never read. A file that
is larger than the remaining byte limit fails before its read. The adapter never
uploads or writes a selected file. `File.text()` decodes UTF-8 with replacement
characters and removes a leading byte order mark; this is the browser behavior,
and it differs from the fatal decoding of hosted files. A rejected read raises
`Io`, or `PermissionDenied` for `NotAllowedError` and `SecurityError`. Abort
stops the load while a read is pending, and the adapter ignores its late result.

## Workspace discovery

`@browser.workspace(conventions, mount)` confines convention discovery to one
mount. It removes the system directory, the global user directory and the
application home, and sets the walk-up boundary to the mount root. It does not
set isolated mode. Project files, environment files, and local and user
overrides inside the mount keep the core order, ambiguity, reports and
provenance. Variables such as `HOME` or `ACME_HOME` give no file access.

```mbt check
test "confine discovery to a mounted workspace" {
  let mount = @browser.from_urls(
    "https://example.org/project/",
    { "version": 1, "files": ["acme.toml", "src/main.mbt"] },
    root="/workspace",
  )
  let conventions = @browser.workspace(@conventions.app_dirs("acme"), mount)
  let builder = @config.builder() |> @conventions.add(conventions)
  assert_eq(conventions.name(), "acme")
  ignore(builder)
}
```

A caller can set a narrower boundary with `@conventions.boundary` after this
call. A wider boundary, or conventions without this helper, can still request a
path outside every mount; `load` then raises `OutsideMount` before any I/O.

The compiled consumer in
[`tests/browser-consumer`](../../../../tests/browser-consumer/main.mbt) merges
hosted defaults with selected files. Its `loadSelectedServer(files, base)` maps a
plain file input or a directory input, then loads in builder order:

```moonbit
let defaults = @browser.from_urls(base, { "version": 1, "files": ["acme.toml"] }, root="/defaults")
let project = @browser.from_files(project_files(files), root="/workspace")
let builder = @config.builder()
  |> @config.format(@toml.format())
  |> @config.file("/defaults/acme.toml")
  |> @config.working_dir("/workspace/src")
  |> @conventions.add(@browser.workspace(@conventions.app_dirs("acme"), project))
let config = @browser.load(builder, [defaults, project])
```

## Directory handles

`@browser.from_directory(handle, root~)` mounts a `@browser.DirectoryHandle`
that the application already holds. The application can get it from its own
native picker, or from OPFS. The package never opens a picker and never calls
`requestPermission` or `queryPermission`. The adapter build rejects these APIs.

A directory mount is live and read-only. For each requested path, the adapter
resolves one segment at a time with `create: false`. It lists direct children
with `entries()` and reads a file with `getFile()` and `text()`. It checks each
segment against the exact names from `entries()`, because an engine can resolve
a name without case on a case-insensitive host file system. A missing entry or
a wrong entry kind is absent. A load never creates, writes or removes an entry.

Each load caches its answers. A later load can see changed entries; a completed
`Config` does not change. A load is not an atomic snapshot of the directory.
Listed entries count toward the entry limit as the load observes them.
`NotAllowedError` and `SecurityError` raise `PermissionDenied`, for example
after the user revokes access. Other failures raise `Io`. The load does not try
another mount or store after a failure.

Capability detection belongs to the application. A native directory picker
(`showDirectoryPicker`), a directory input (`webkitdirectory`) and OPFS are
separate capabilities. OPFS support does not mean that a picker is available.
The compiled consumer exposes `browserCapabilities()` and
`loadDirectoryServer(handle, base)`. Without a picker, it uses
`loadSelectedServer(files, base)` with a file or directory input instead.

```moonbit
let project = @browser.from_directory(handle, root="/workspace")
let builder = @config.builder()
  |> @config.format(@toml.format())
  |> @config.file("/defaults/acme.toml")
  |> @config.working_dir("/workspace/src")
  |> @conventions.add(@browser.workspace(@conventions.app_dirs("acme"), project))
let config = @browser.load(builder, [defaults, project])
```

## Authority and ordering

Mounts are opaque immutable values. Their canonical absolute virtual roots must
be distinct and cannot overlap. `/workspace` and `/workspace2` are separate;
`/workspace` and `/workspace/vendor` overlap. A load requires at least one mount.
An empty manifest or file list is valid. Parent directories are inferred;
declared empty directories are retained. Listings contain exact direct-child names in lexical
code-unit order. Unlisted paths are missing without a fetch.

Use multiple mounts for hosted defaults and project configuration, then add their
virtual file sources in builder order. Mount order supplies no priority. The
first root is the default working directory. Explicit builder variables, working
directory and OS platform are preserved. Omitted variables are an empty map and
no platform is inferred. Page parameters, storage, user-agent and process state
never supply configuration.

Roots and working directories must be canonical absolute paths; manifest and
selected-file paths must be relative. Empty segments, `.`, `..`, backslashes, NUL and drive prefixes
are invalid. Duplicate declarations, file/directory collisions, and file ancestors
are rejected before I/O. A requested path must be inside a mount. Filenames are
not URL-decoded or lowercased, and each segment is URL-encoded before fetching.

## Limits, cancellation and failures

`@browser.limits(entries?, bytes?, requests?)` accepts positive limits, defaulting
to 4096 unique manifest or selected-file entries including inferred directories
but excluding mount roots, 8 MiB of loaded UTF-8, and 8192 distinct requests. Entry and request
bounds are checked before backend access. Byte bounds apply across files and
while reading streams, even if size headers are absent or incorrect.

Pass `limits~` and an optional `signal~` to `load`. `@browser.AbortController` and
`@browser.AbortSignal` alias the async library's external Web API wrappers. Abort
terminates the active fetch and prevents further reads. Every acquired response
reader is released. A live failed response is cancelled or aborted first; cleanup
failure does not replace the original error. No failure returns a partial config.

HTTP requests use `credentials: "omit"` and `redirect: "error"`. A 404 is absence;
other non-success statuses raise `BrowserError::Http`. Network, CORS, redirect,
read and UTF-8 decoding failures raise `Io`. `BrowserError` also distinguishes
invalid mounts/paths, outside requests, unsupported APIs, limits, abort and
protocol/no-progress failures. Its operation and virtual-path fields exclude
backend URLs and response contents. Core `ConfigError` values, including parse
and binding origins and available positions, pass through unchanged.

Each load has a new snapshot and caches answers only for that call. A custom
provider that requests only already answered inputs raises `Protocol`. A later
load can see new server content; a previous `Config` remains unchanged.

## Building consumers

Consumers compile the checked-in inline FFI with MoonBit. They do not run Bun or
Playwright. Repository adapter development uses `mise run build:browser-adapter`;
`check:browser-adapter` rejects stale output without rewriting it. The fixture has
its own generated file, outside the published module.

OPFS persistence belongs to a later story. This package currently provides
hosted URL mounts, selected-file mounts and directory-handle mounts.

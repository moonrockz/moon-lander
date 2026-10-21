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

## Authority and ordering

Mounts are opaque immutable values. Their canonical absolute virtual roots must
be distinct and cannot overlap. `/workspace` and `/workspace2` are separate;
`/workspace` and `/workspace/vendor` overlap. A load requires at least one mount.
An empty manifest is valid. Parent directories are inferred; declared empty
directories are retained. Listings contain exact direct-child names in lexical
code-unit order. Unlisted paths are missing without a fetch.

Use multiple mounts for hosted defaults and project configuration, then add their
virtual file sources in builder order. Mount order supplies no priority. The
first root is the default working directory. Explicit builder variables, working
directory and OS platform are preserved. Omitted variables are an empty map and
no platform is inferred. Page parameters, storage, user-agent and process state
never supply configuration.

Roots and working directories must be canonical absolute paths; manifest paths
must be relative. Empty segments, `.`, `..`, backslashes, NUL and drive prefixes
are invalid. Duplicate declarations, file/directory collisions, and file ancestors
are rejected before I/O. A requested path must be inside a mount. Filenames are
not URL-decoded or lowercased, and each segment is URL-encoded before fetching.

## Limits, cancellation and failures

`@browser.limits(entries?, bytes?, requests?)` accepts positive limits, defaulting
to 4096 unique manifest entries including inferred directories but excluding
mount roots, 8 MiB of loaded UTF-8, and 8192 distinct requests. Entry and request
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

Selected files, workspace helpers, directory handles and OPFS persistence belong
to later stories. This package currently provides hosted URL mounts only.

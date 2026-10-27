# Host adapter

The `host` package (`@host`) loads configuration from the disk on the
`native` and `js` targets. It fills the inputs that the builder does not hold,
then answers the file requests from the pure `@config.load` until loading is done.
The async `@host.load` API is the same on both targets. The package is empty
on wasm and wasm-gc so portable hosting can import it. Hosting calls `load`
only from its native and js driver; wasm hosts load an injected `FileTree`
through the pure configuration core.

| Input | Where it comes from |
| --- | --- |
| Variable set | `@config.env_vars` when given, else the process environment |
| Working directory | `@config.working_dir` when given, else the process working directory |
| Platform | `@config.platform` when given, else the running system |
| Files on native | `moonbitlang/async` |
| Files on js | Synchronous `node:fs` calls through the TypeScript adapter |

The js adapter runs on the pinned Node and Bun versions. Its generated MoonBit
FFI file is checked in, so `moon build` and `moon test` do not need Bun. After an
edit to `pkgs/config/adapters/node/`, run `mise run build:node-adapter`. Both
`mise run check:node-adapter` and `mise run check` reject a stale generated file.

A missing file or directory becomes an absence record. Other I/O errors are
raised, so an inaccessible file does not silently disappear from discovery.
Listings include hidden entries and follow symbolic links to classify entries.
A listed entry that the adapter cannot inspect, such as `D:/pagefile.sys` that
Windows locks, has the kind `Inaccessible` and does not stop the listing. The load
reads such an entry only when it is a candidate, and that read raises the error.
An entry that disappears before the adapter inspects it, or a link that points
nowhere, is not in the listing.
Paths use `/` in the file tree, reports, origins, and errors on every platform.
The adapter gives the process working directory in its native form. The pure
load parses it, and each explicit file and candidate, one time with
`FileTreePath::from_native` for the platform of the run. So on Windows
`C:\cfg\app.toml` and `C:/cfg/app.toml` select the same file, a UNC path keeps
its `//server/share` root, and a drive-relative path such as `C:app.toml` is a
configuration error before any file call. A file call uses
`FileTreePath::to_native`, which converts `/` to `\` only on Windows. A listed
entry keeps the name that the system gives; only a candidate name has to form a
file-tree path.

This example reads the module manifest from the process working directory with
a format that accepts its text. It runs as a doc test on native and js.

```mbt check
///|
#cfg(any(target="native", target="js"))
async test "read a file through the host adapter" {
  let format : @config.Format = {
    name: "module",
    extensions: ["mod"],
    parse: (text, _) => @config.fields([("text", @config.string(text))]),
  }
  let config = @config.builder()
    |> @config.format(format)
    |> @config.file("moon.mod")
    |> @host.load
  @expect.expect(@config.get_text(config, "text").contains("moonrockz/moon-lander")).to_equal(true)
}
```

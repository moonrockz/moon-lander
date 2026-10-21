# Host adapter

The `config/host` package (`@host`) loads configuration from the disk on the
`native` and `js` targets. It fills the inputs that the builder does not hold,
then answers the file requests from the pure `@config.load` until loading is done.
The async `@host.load` API is the same on both targets.

| Input | Where it comes from |
| --- | --- |
| Variable set | `@config.env_vars` when given, else the process environment |
| Working directory | `@config.working_dir` when given, else the process working directory |
| Platform | `@config.platform` when given, else the running system |
| Files on native | `moonbitlang/async` |
| Files on js | Synchronous `node:fs` calls through the TypeScript adapter |

The js adapter runs on the pinned Node and Bun versions. Its generated MoonBit
FFI file is checked in, so `moon build` and `moon test` do not need Bun. After an
edit to `pkgs/lander/adapters/node/`, run `mise run build:node-adapter`. Both
`mise run check:node-adapter` and `mise run check` reject a stale generated file.

A missing file or directory becomes an absence record. Other I/O errors are
raised, so an inaccessible file does not silently disappear from discovery.
Listings include hidden entries and follow symbolic links to classify entries.
On Windows paths use `/` in the file tree, reports, origins, and errors. The
adapter converts to native separators only for file calls.

This example reads the module manifest from the process working directory with
a format that accepts its text. It runs as a doc test on native and js.

```mbt check
///|
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

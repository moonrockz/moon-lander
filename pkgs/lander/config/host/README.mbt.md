# Host adapter

The `config/host` package (`@host`) loads configuration from the disk on the
`native` target. It is the host side of the pure `@config.load`: it fills the
inputs that the builder does not hold, then answers each file request until the
load is done. The `js` adapter comes in a later change.

Import `moonrockz/moon-lander/config/host` as `@host` in a `native` package. The
`mbt check` block on this page runs as a test with `mise run test`.

| Input | Where it comes from |
| --- | --- |
| Variable set | `@config.env_vars` when given, else the process environment |
| Working directory | `@config.working_dir` when given, else the process working directory |
| Platform | `@config.platform` when given, else the running system |
| Files | The disk, through `moonbitlang/async` |

A file or a directory that does not exist becomes an absence record, so the
loop never asks for one path twice. On Windows the adapter changes `\` to `/`
when it reads a path, and back for each file call, so reports and errors show
`C:/repo/app.toml` on every platform.

```mbt check
///|
async test "load the project file from the disk" {
  let dir = @fs.tmpdir(prefix="lander-readme")
  defer @fs.rmdir(dir, recursive=true)
  let root = dir.replace_all(old="\\", new="/")
  @fs.write_file("\{dir}/acme.toml", "project.name = \"acme\"")
  @fs.mkdir("\{dir}/src", allow_exist=true)
  let config = @config.builder()
    |> @config.working_dir("\{root}/src")
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.app_dirs("acme"))
    |> @host.load
  @expect.expect(@config.get_text(config, "project.name")).to_equal("acme")
}
```

# Conventions

The `config/conventions` package (`@conventions`) finds an application's
configuration files, so the application does not list paths itself. It plugs into
the core builder as a source provider. Discovery is pure: it reads the file tree
and the working directory that the run gives, never the disk or the process.

Import `moonrockz/moon-lander/config/conventions` as `@conventions`. Each
`mbt check` block on this page runs as a test with `mise run test`.

> [!NOTE]
> This is the first part of discovery. `app_dirs` finds `<app>.<ext>` by walking
> up from the working directory. The `.<app>/` and `.config/<app>/` layouts, the
> system and user directories, overrides, the stop boundary, workspaces, and
> environments come in later parts.

## Walk up to the project root

Discovery starts at the working directory of the run and moves to each parent. The
first directory that holds `<app>.<ext>` as a file is the project root. Its file
becomes the project source, with the role `Workspace` and the priority 300.

```text
/w/acme.toml          <- found: the project primary
/w/src/
/w/src/nested/        <- the working directory
```

| Step | What discovery does |
| --- | --- |
| Start | The working directory that `@config.working_dir` sets |
| Search | `<app>.<ext>` for each extension of the registered formats, by exact name |
| Walk | Each parent directory, up to the file-system root |
| Stop | At the first directory with a primary; two primaries there are `Ambiguous` |
| None found | The report shows `NotFound` with the candidates at the start directory |

The file names come from the formats that the builder registers. Register only
TOML, and discovery never finds `acme.yaml`, a file that the run could not parse.

```mbt check
///|
test "find the project file from a nested directory" {
  let builder = @config.builder()
    |> @config.working_dir("/w/src/nested")
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.app_dirs("acme"))
  let tree = @config.FileTree::new(complete=true)
    .with_listing("/w", [
      { name: "acme.toml", kind: File },
      { name: "src", kind: Directory },
    ])
    .with_listing("/w/src", [{ name: "nested", kind: Directory }])
    .with_listing("/w/src/nested", [])
    .with_file("/w/acme.toml", "project.name = \"acme\"")
  guard @config.load(builder, tree) is Done(config) else {
    fail("a complete tree never asks for files")
  }
  @expect.expect(@config.get_text(config, "project.name")).to_equal("acme")
  @expect.expect(config.reports()[0].path).to_equal(Some("/w/acme.toml"))
}
```

## One directory at a time

With an incomplete tree, discovery asks for one listing per step, nearest first.
It stops asking once it finds the root, so it never lists more parents than it
needs. A host answers each request and calls `@config.load` again.

```mbt check
///|
test "discovery asks for the listing of the working directory first" {
  let builder = @config.builder()
    |> @config.working_dir("/w/src")
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.app_dirs("acme"))
  guard @config.load(builder, @config.FileTree::new()) is Need(requests) else {
    fail("an empty tree needs a listing")
  }
  @expect.expect(requests).to_equal([ListDir("/w/src")])
}
```

## Names

| Part | Value |
| --- | --- |
| `base(name, prefix?, display?)` | An empty convention set: no layouts and no walk-up |
| `app_dirs(name, prefix?, display?)` | `base` with the standard parts |
| `prefix` | The environment variable prefix; defaults to the name in upper case with `-` changed to `_` |
| `display` | The name that the ambiguity message shows; defaults to the name |
| `DiscoveryOptions` | The inputs that a host gives from its arguments: environment, explicit primary, isolated mode, and project |

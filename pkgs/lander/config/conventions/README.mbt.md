# Conventions

The `config/conventions` package (`@conventions`) finds an application's
configuration files, so the application does not list paths itself. It plugs into
the core builder as a source provider. Discovery is pure: it reads the file tree
and the working directory that the run gives, never the disk or the process.

Import `moonrockz/moon-lander/config/conventions` as `@conventions`. Each
`mbt check` block on this page runs as a test with `mise run test`.

> [!NOTE]
> Discovery finds the project file in three layouts by walking up from the
> working directory, with a stop boundary, a legacy fallback, and isolated mode.
> The system and user directories, overrides, workspaces, and environments come
> in later parts.

## Walk up to the project root

Discovery starts at the working directory of the run and moves to each parent. The
first directory that holds a primary file is the project root. Its file becomes
the project source, with the role `Workspace` and the priority 300.

```text
/w/acme.toml          <- found: the project primary
/w/src/
/w/src/nested/        <- the working directory
```

A primary file has one of three layouts in a directory:

| Layout | Example for `acme` with TOML |
| --- | --- |
| `<app>.<ext>` | `acme.toml` |
| `.<app>/<app>.<ext>` | `.acme/acme.toml` |
| `.config/<app>/config.<ext>` | `.config/acme/config.toml` |

Two primary files in one directory, in one layout or in two, are an error,
`Ambiguous`. Discovery never merges them or picks one, and it does not look
further up.

| Step | What discovery does |
| --- | --- |
| Start | The working directory that `@config.working_dir` sets; it must be absolute |
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

## Stop boundary and isolated mode

`boundary(dir)` stops the walk-up at `dir`: discovery looks in `dir` and never
above it. A test sets the boundary to its temporary root, so a file above the
root never leaks into the test. A working directory outside the boundary is an
error, `OutsideBoundary`.

```mbt check
///|
test "a test root keeps files above it out" {
  let builder = @config.builder()
    |> @config.working_dir("/tmp/case/src")
    |> @config.format(@toml.format())
    |> @conventions.add(
      @conventions.app_dirs("acme") |> @conventions.boundary("/tmp/case"),
    )
  let tree = @config.FileTree::new(complete=true)
    .with_listing("/tmp", [
      { name: "acme.toml", kind: File },
      { name: "case", kind: Directory },
    ])
    .with_listing("/tmp/case", [{ name: "src", kind: Directory }])
    .with_listing("/tmp/case/src", [])
  guard @config.load(builder, tree) is Done(config) else {
    fail("a complete tree never asks for files")
  }
  @expect.expect(config.reports()[0].status).to_equal(NotFound)
}
```

Isolated mode comes from `DiscoveryOptions(isolated=true)`, for example from an
`--isolated` flag that a host parses. It skips the files of the user and the
machine: the system directory, the global user directory, and the local and
user overrides. The project file and the environment variables stay. Those
parts come later; each one reports `Skipped` in isolated mode. Discovery does
not read the `environment`, `config`, and `project` options yet, and a given
value adds a `Note` warning.

## Legacy fallback

`legacy(name, format~, decode~)` names an older file, for example `acme.json`.
At a location with no primary file, the legacy file is the primary and marks the
project root. Its format parses it but is not registered, so `.json` never
becomes a searched extension, and `decode` turns the parsed value into a layer.

## One directory at a time

With an incomplete tree, discovery asks for the listings of one directory per
step, nearest first: the directory itself, `.<app>/`, and `.config/<app>/`. It
stops asking once it finds the root, so it never lists more parents than it
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
  @expect.expect(requests).to_equal([
    ListDir("/w/src"),
    ListDir("/w/src/.acme"),
    ListDir("/w/src/.config/acme"),
  ])
}
```

## Names

| Part | Value |
| --- | --- |
| `base(name, prefix?, display?)` | An empty convention set: no layouts and no walk-up |
| `app_dirs(name, prefix?, display?)` | `base` with the three layouts and walk-up |
| `boundary(dir)` | The walk-up stop; a relative `dir` joins the working directory |
| `legacy(name, format~, decode~)` | A legacy fallback file with its own format |
| `add(builder, conventions, options?)` | The provider that runs discovery during `@config.load` |
| `prefix` | The environment variable prefix; defaults to the name in upper case with `-` changed to `_` |
| `display` | The name that the ambiguity message shows; defaults to the name |
| `DiscoveryOptions` | The inputs that a host gives from its arguments: environment, explicit primary, isolated mode, and project |

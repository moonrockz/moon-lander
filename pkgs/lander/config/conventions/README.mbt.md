# Conventions

The `config/conventions` package (`@conventions`) finds an application's
configuration files, so the application does not list paths itself. It plugs into
the core builder as a source provider. Discovery is pure: it reads the file tree
and the working directory that the run gives, never the disk or the process.

Import `moonrockz/moon-lander/config/conventions` as `@conventions`. Each
`mbt check` block on this page runs as a test with `mise run test`.

> [!NOTE]
> Discovery finds the system file, the global user file, and the project file in
> three layouts by walking up from the working directory, with local and user
> overrides next to the project file, an explicit project file, a stop boundary,
> a legacy fallback, isolated mode, and environment files. Workspaces come in a
> later part.

`app_dirs("acme")` gives these sources, in merge order:

| Priority | Source | Role | Files for `acme` with TOML on Linux |
| --- | --- | --- | --- |
| 100 | System | `System` | `/etc/acme/acme.toml` |
| 200 | Global user | `Global` | `~/.config/acme/acme.toml` or `~/.acme/acme.toml` |
| 300 | Project | `Workspace` | `acme.toml`, `.acme/acme.toml`, or `.config/acme/config.toml`, found by walk-up |
| 375 | Environment file | `EnvironmentFile` | `acme.Production.toml` next to the project file, when environments are on |
| 390 | Local override | `LocalOverride` | `acme.local.toml` next to the project file |
| 400 | User override | `UserOverride` | `acme.user.toml` next to the project file |

The environment-variable source (600) of the core comes after them, so a
variable wins over every file.

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
  let project = config
    .reports()
    .iter()
    .find_first(report => report.kind == File(Workspace))
  @expect.expect(project.map(report => report.path)).to_equal(
    Some(Some("/w/acme.toml")),
  )
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
  let project = config
    .reports()
    .iter()
    .find_first(report => report.kind == File(Workspace))
  @expect.expect(project.map(report => report.status)).to_equal(Some(NotFound))
}
```

Isolated mode comes from `DiscoveryOptions(isolated=true)`, for example from an
`--isolated` flag that a host parses. It skips the files of the user and the
machine: the system directory, the global user directory, and the local and
user overrides. Each of them reports `Skipped`. The project file, its
environment file and the environment variables stay. Discovery does not read
the `project` option yet, and a given value adds a `Note` warning.

## System and global user directories

The system source and the global user source come from the platform and the
variable set of the run, which `@config.platform` and `@config.env_vars` give.
Discovery never reads the process environment. The host adapter
`@config/host.load` fills both from the running system when the builder holds
none. With no platform, the two sources report `Skipped` and discovery adds a
`Note` warning.

| Directory | Linux | macOS | Windows |
| --- | --- | --- | --- |
| System | `/etc/<app>` | `/etc/<app>` | `%PROGRAMDATA%/<app>`, else `C:/ProgramData/<app>` |
| User configuration | `$XDG_CONFIG_HOME/<app>`, else `$HOME/.config/<app>` | `$XDG_CONFIG_HOME/<app>`, else `$HOME/Library/Application Support/<app>` | `%APPDATA%/<app>` |
| Application home | `$<PREFIX>_HOME`, else `$HOME/.<app>` | `$<PREFIX>_HOME`, else `$HOME/.<app>` | `$<PREFIX>_HOME`, else `%USERPROFILE%/.<app>` |

- The file name in each directory is `<app>.<ext>`.
- An empty variable counts as unset. `XDG_CONFIG_HOME` counts only when it is
  absolute, and it has no effect on Windows.
- The user configuration directory and the application home are one global
  source. Two global files are `Ambiguous`.
- On Windows, `\` becomes `/` in each variable. An absolute Windows path starts
  with a drive and a separator (`C:/`) or with `//server/share`; `C:foo` is not
  absolute. A relative value joins the working directory.

```mbt check
///|
test "the global candidates come from the variable set of the run" {
  let builder = @config.builder()
    |> @config.working_dir("/w")
    |> @config.platform(Linux)
    |> @config.env_vars({ "HOME": "/home/alice", "ACME_HOME": "/opt/acme" })
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.app_dirs("acme"))
  guard @config.load(builder, @config.FileTree::new(complete=true))
    is Done(config) else {
    fail("a complete tree never asks for files")
  }
  let global = config
    .reports()
    .iter()
    .find_first(report => report.kind == File(Global))
  @expect.expect(global.map(report => report.candidates)).to_equal(
    Some(["/home/alice/.config/acme/acme.toml", "/opt/acme/acme.toml"]),
  )
}
```

## Overrides next to the project file

A local override is for one checkout, and git ignores it. A user override is the
preference of one person, so it wins over the local override. Both sit in the
directory of the project file:

| Project file | Local override | User override |
| --- | --- | --- |
| `acme.toml` | `acme.local.toml` | `acme.user.toml` |
| `.acme/acme.toml` | `.acme/acme.local.toml` | `.acme/acme.user.toml` |
| `.config/acme/config.toml` | `.config/acme/config.local.toml` | `.config/acme/config.user.toml` |

The extensions come from the registered formats, so `acme.user.yaml` can
override `acme.toml`. Two overrides of one kind, such as `acme.user.toml` and
`acme.user.yaml`, are `Ambiguous`. A legacy file has no overrides, and with no
project file there is no override source.

```mbt check
///|
test "the user override wins over the project file" {
  let builder = @config.builder()
    |> @config.working_dir("/w")
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.app_dirs("acme"))
  let tree = @config.FileTree::new(complete=true)
    .with_listing("/w", [
      { name: "acme.toml", kind: File },
      { name: "acme.user.toml", kind: File },
    ])
    .with_file("/w/acme.toml", "ui.theme = \"shared\"")
    .with_file("/w/acme.user.toml", "ui.theme = \"personal\"")
  guard @config.load(builder, tree) is Done(config) else {
    fail("a complete tree never asks for files")
  }
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("personal")
}
```

## An explicit project file

`DiscoveryOptions(config=Explicit(path))`, for example from a `--config` flag,
names the project file. Discovery does not walk up. A relative path joins the
working directory, and on Windows `\` becomes `/`. The source has the role `Explicit`, and a missing file is an
error, `FileNotFound`. When the path has a standard layout, such as
`configs/acme.toml`, its local and user overrides apply. Other files, such as
`configs/project.yaml`, have no overrides. `Skip` skips the project file.

## Environments

An environment file holds the values of one environment, such as `Production`,
next to the project file. Environments are off until the application turns them
on with `environments(default?)`. The name of the run comes from the first of
these sources that gives one:

| Order | Source | Example |
| --- | --- | --- |
| 1 | The `environment` value of `DiscoveryOptions` | A host fills it from `--environment Staging` |
| 2 | `<PREFIX>_ENVIRONMENT` in the variable set of the run | `ACME_ENVIRONMENT=Production`; an empty value counts as unset |
| 3 | The default of `environments` | `environments(default="Development")` |

With no name, no environment file loads. With environments off, a given
`environment` option adds a `Note` warning. Discovery never reads the process
arguments, so a host parses `--environment` and gives the value as the option.

The environment file has the priority 375: it wins over the project file, and
the local and user overrides win over it. It follows the layout of the project
file:

| Project file | Environment file for `Production` |
| --- | --- |
| `acme.toml` | `acme.Production.toml` |
| `.acme/acme.toml` | `.acme/acme.Production.toml` |
| `.config/acme/config.toml` | `.config/acme/config.Production.toml` |

- The name matches exactly, so `acme.production.toml` is not the file for
  `Production`.
- An environment file alone does not mark a project root.
- Two environment files for one project file, such as `acme.Production.toml` and
  `acme.Production.yaml`, are `Ambiguous`.
- The system file, the global user file, a legacy file and an explicit file
  outside the standard layouts have no environment file.

A name must not be empty, must not contain `/`, `\`, `.` or a control
character, and must not be `user` or `local` in any letter case, so an override
is never an environment file. A bad name raises `InvalidEnvironmentName`, which
names the source of the name. `environment_name` gives the name of the run with
the same rules, and `check_environment_name` checks a name from another source.

An application without a host gives the environment-variable source the
reserved names `<PREFIX>_ENVIRONMENT` and `<PREFIX>_HOME` itself. These
variables select files, so they must not become configuration keys:

```mbt check
///|
test "the environment file of the run wins over the project file" {
  let conventions = @conventions.app_dirs("acme")
    |> @conventions.environments(default="Development")
  let vars = { "ACME_ENVIRONMENT": "Production", "ACME_UI__THEME": "dark" }
  let builder = @config.builder()
    |> @config.working_dir("/w")
    |> @config.env_vars(vars)
    |> @config.format(@toml.format())
    |> @conventions.add(conventions)
    |> @config.env(prefix="ACME", reserved=["ACME_ENVIRONMENT", "ACME_HOME"])
  let tree = @config.FileTree::new(complete=true)
    .with_listing("/w", [
      { name: "acme.toml", kind: File },
      { name: "acme.Production.toml", kind: File },
    ])
    .with_file("/w/acme.toml", "log.level = \"info\"")
    .with_file("/w/acme.Production.toml", "log.level = \"warn\"")
  guard @config.load(builder, tree) is Done(config) else {
    fail("a complete tree never asks for files")
  }
  @expect.expect(@conventions.environment_name(conventions, vars)).to_equal(
    Some("Production"),
  )
  @expect.expect(@config.get_text(config, "log.level")).to_equal("warn")
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("dark")
  // The reserved names give no configuration key.
  @expect.expect(config.get(@config.KeyPath::parse("environment"))).to_equal(
    None,
  )
}
```

## Choose the parts

`app_dirs` uses every standard part. `without(part)` removes one, and `base`
with single parts gives full control:

```mbt check
///|
test "remove the system part, or build from single parts" {
  // No system file, for a tool that never installs machine-wide.
  let tool = @conventions.app_dirs("acme") |> @conventions.without(SystemDir)
  // Only the project file in three layouts and a user override.
  let minimal = @conventions.base("acme")
    |> @conventions.layouts
    |> @conventions.user_overrides
  let kinds = (conventions : @conventions.Conventions) => {
    let builder = @config.builder()
      |> @config.working_dir("/w")
      |> @config.platform(Linux)
      |> @config.env_vars({ "HOME": "/home/alice" })
      |> @config.format(@toml.format())
      |> @conventions.add(conventions)
    let tree = @config.FileTree::new(complete=true)
      .with_listing("/w", [{ name: "acme.toml", kind: File }])
      .with_file("/w/acme.toml", "a = 1")
    guard @config.load(builder, tree) is Done(config) else {
      fail("a complete tree never asks for files")
    }
    config.reports().map(report => report.kind.report_name())
  }
  @expect.expect(kinds(tool)).to_equal([
    "global", "project", "local-override", "user-override",
  ])
  @expect.expect(kinds(minimal)).to_equal(["project", "user-override"])
}
```

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
| `base(name, prefix?, display?)` | An empty convention set: no parts and no walk-up |
| `app_dirs(name, prefix?, display?)` | `base` with every standard part and walk-up |
| `system_dir`, `user_config_dir`, `app_home` | The system, user configuration, and application home directories |
| `layouts` | The three primary layouts |
| `local_overrides`, `user_overrides` | `*.local.*` and `*.user.*` files next to the project file |
| `without(part)` | Removes one `Part`: `SystemDir`, `UserConfigDir`, `AppHome`, `Layouts`, `LocalOverrides`, or `UserOverrides` |
| `boundary(dir)` | The walk-up stop; a relative `dir` joins the working directory |
| `legacy(name, format~, decode~)` | A legacy fallback file with its own format |
| `environments(default?)` | Turns on environment files, with an optional default name |
| `environment_name(conventions, options?, env_vars)` | The environment name of the run, or `None` |
| `check_environment_name(name, source~)` | Checks a name with the environment name rules |
| `add(builder, conventions, options?)` | The provider that runs discovery during `@config.load` |
| `prefix` | The environment variable prefix; defaults to the name in upper case with `-` changed to `_` |
| `display` | The name that the ambiguity message shows; defaults to the name |
| `DiscoveryOptions` | The inputs that a host gives from its arguments: environment, explicit primary, isolated mode, and project |

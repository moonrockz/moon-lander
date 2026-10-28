# Conventions

The `conventions` package (`@conventions`) finds an application's
configuration files, so the application does not list paths itself. It plugs into
the core builder as a source provider. Discovery is pure: it reads the file tree
and the working directory that the run gives, never the disk or the process.

Import `moonrockz/moon-lander-config/conventions` as `@conventions`. Each
`mbt check` block on this page runs as a test with `mise run test`.

> [!NOTE]
> Discovery finds the system file, the global user file, and the project file in
> three layouts by walking up from the working directory, with local and user
> overrides next to the project file, an explicit project file, a stop boundary,
> a legacy fallback, isolated mode, environment files, and workspaces with
> members and key filters.

`app_dirs("acme")` gives these sources, in merge order:

| Priority | Source | Role | Files for `acme` with TOML on Linux |
| --- | --- | --- | --- |
| 100 | System | `System` | `/etc/acme/acme.toml` |
| 200 | Global user | `Global` | `~/.config/acme/acme.toml` or `~/.acme/acme.toml` |
| 300 | Project | `Workspace` | `acme.toml`, `.acme/acme.toml`, or `.config/acme/config.toml`, found by walk-up |
| 350 | Member | `Member` | `packages/billing/acme.toml`, when the workspace part selects a member |
| 375 | Environment file | `EnvironmentFile` | `acme.Production.toml` next to the project file, when environments are on |
| 390 | Local override | `LocalOverride` | `acme.local.toml` next to the project file |
| 400 | User override | `UserOverride` | `acme.user.toml` next to the project file |

The environment-variable source (600) of the core comes after them, so a
variable wins over every file.

## Find a declared workspace

Select `WorkspaceFirst` with a parsed section path to inspect documents while
walking up. An empty workspace object counts as a declaration. Discovery stops
at the nearest declaration, even when that workspace excludes the project. It
does not inspect an ancestor above that workspace or the explicit boundary.
If no workspace is found, the nearest primary is the project fallback. An
examined parse failure or ambiguity remains an error.

`ExplicitOnly` suppresses automatic single-member selection. An explicit project
selector still applies. The pure `roots`
method always returns root evidence without selecting a member. It uses the
same `Need`/`Done` file-tree protocol as `load`; the host supplies any requested
entries. The result exposes the workspace, nearest project and parsed primary
sources, so an application can retain its own all-member walk.

```mbt check
///|
test "inspect root evidence without selecting a member" {
  let root = @config.FileTreePath::parse("/w")
  let child = @config.FileTreePath::parse("/w/a")
  let conventions = @conventions.app_dirs("acme")
    |> @conventions.workspace
    |> @conventions.root_policy(WorkspaceFirst(@config.KeyPath::parse("workspace")))
    |> @conventions.member_loading(ExplicitOnly)
  let tree = @config.FileTree::new(complete=true)
    .with_listing(root, [{ name: "acme.toml", kind: File }, { name: "a", kind: Directory }])
    .with_listing(child, [{ name: "acme.toml", kind: File }])
    .with_file(root.child("acme.toml"), "[workspace]\nmarker='root'")
    .with_file(child.child("acme.toml"), "project.name='a'")
  let context : @config.LoadContext = {
    tree, working_dir: Some(child), platform: Some(Linux),
    env_vars: Map([]), formats: [@toml.format()],
  }
  guard conventions.roots(context) is Done(roots) else { fail("complete tree needs I/O") }
  assert_eq(roots.workspace(), Some(root))
  assert_eq(roots.nearest_project(), Some(child))
  let config = @config.build(roots.sources())
  assert_eq(@config.get_text(config, "workspace.marker"), "root")
}
```

`NearestFile` and `Automatic` remain the defaults. Existing calls retain the
nearest-file and enclosing-member rules below. A workspace section must be an
object; a scalar has a typed decode failure.

## Order formats at each stage

Opt into `FormatLayers` to merge formats at one location. Later groups win;
extensions inside a group are alternatives, so two existing ordinary files in
that group are ambiguous, including files in different layouts. Every declared
extension needs a registered parser. Registration order has no precedence
effect, and registered extensions outside the policy are not searched.

An optional `SupplementalFile` belongs to its group and loads before that
group's ordinary primary. The application owns its file name and pure
transformation. Discovery reuses the transformed value for workspace
classification, profile controls, and the final source. A supplemental file
can declare a workspace by itself; it does not create a new override or profile
stem. Its name cannot collide with an enabled ordinary primary.

```mbt check
///|
test "declare ordered groups with an application-owned workspace file" {
  let json = @conventions.Extension::parse("json")
  let toml = @conventions.Extension::parse("toml")
  let layers = @conventions.FormatLayers::new([
    @conventions.FormatGroup::new([json], supplemental=
      @conventions.SupplementalFile::new("acme-workspace.json", json)),
    @conventions.FormatGroup::new([toml]),
  ])
  let conventions = @conventions.base("acme") |> @conventions.layouts
    |> @conventions.format_layers(layers)
    |> @conventions.root_policy(WorkspaceFirst(@config.KeyPath::parse("workspace")))
  let tree = @config.FileTree::new(complete=true)
    .with_listing(@config.FileTreePath::parse("/w"), [
      { name: "acme-workspace.json", kind: File },
      { name: "acme.toml", kind: File },
    ])
    .with_file(@config.FileTreePath::parse("/w/acme-workspace.json"),
      "{workspace:{}, shared:'json', retained:true}")
    .with_file(@config.FileTreePath::parse("/w/acme.toml"), "shared='toml'")
  let builder = @config.builder() |> @config.working_dir("/w")
    |> @config.format(@toml.format()) |> @config.format(@json5.format())
    |> @conventions.add(conventions)
  guard @config.load(builder, tree) is Done(config) else { fail("complete tree") }
  assert_eq(@config.get_text(config, "shared"), "toml")
  assert_eq(@config.bind(config, "retained"), true)
}
```

Group order applies inside each enabled system, global, workspace, member,
environment, local and user stage. Stage priorities stay as listed above: even
the first member format wins over the last workspace format. Workspace
classification uses the merged primary documents at that location. With
profiles enabled, all eligible base documents supply one control policy with
each control's own origin. For each active name, workspace groups precede member
groups at priority 380, before the next active name. Isolated mode retains
eligible profile files and skips machine, global, local and user sources.

Omitting `format_layers` retains the ambiguity rules described below.

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
    .with_listing(@config.FileTreePath::parse("/w"), [
      { name: "acme.toml", kind: File },
      { name: "src", kind: Directory },
    ])
    .with_listing(@config.FileTreePath::parse("/w/src"), [{ name: "nested", kind: Directory }])
    .with_listing(@config.FileTreePath::parse("/w/src/nested"), [])
    .with_file(@config.FileTreePath::parse("/w/acme.toml"), "project.name = \"acme\"")
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
    .with_listing(@config.FileTreePath::parse("/tmp"), [
      { name: "acme.toml", kind: File },
      { name: "case", kind: Directory },
    ])
    .with_listing(@config.FileTreePath::parse("/tmp/case"), [{ name: "src", kind: Directory }])
    .with_listing(@config.FileTreePath::parse("/tmp/case/src"), [])
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
environment file and the environment variables stay. The `project` option
selects a workspace member, as [Workspaces and members](#workspaces-and-members)
shows.

## System and global user directories

The system source and the global user source come from the platform and the
variable set of the run, which `@config.platform` and `@config.env_vars` give.
Discovery never reads the process environment. The host adapter
`@host.load` fills both from the running system when the builder holds
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
    .with_listing(@config.FileTreePath::parse("/w"), [
      { name: "acme.toml", kind: File },
      { name: "acme.user.toml", kind: File },
    ])
    .with_file(@config.FileTreePath::parse("/w/acme.toml"), "ui.theme = \"shared\"")
    .with_file(@config.FileTreePath::parse("/w/acme.user.toml"), "ui.theme = \"personal\"")
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
    .with_listing(@config.FileTreePath::parse("/w"), [
      { name: "acme.toml", kind: File },
      { name: "acme.Production.toml", kind: File },
    ])
    .with_file(@config.FileTreePath::parse("/w/acme.toml"), "log.level = \"info\"")
    .with_file(@config.FileTreePath::parse("/w/acme.Production.toml"), "log.level = \"warn\"")
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
      .with_listing(@config.FileTreePath::parse("/w"), [{ name: "acme.toml", kind: File }])
      .with_file(@config.FileTreePath::parse("/w/acme.toml"), "a = 1")
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

## Workspaces and members

`workspace()` turns on workspaces. A project file that sets `workspace.members`
or `workspace.default_member` is a workspace, and each member directory has its
own primary file. The member primary loads after the workspace primary, with
the role `Member` and the priority 350. Then the adjacent files load in pairs,
the workspace file first: the environment files, the local overrides, and the
user overrides.

```text
/w/acme.toml                        <- workspace primary: members = ["packages/*"]
/w/acme.user.toml                   <- workspace user override
/w/packages/billing/acme.toml       <- member primary
/w/packages/billing/acme.user.toml  <- member user override, which wins
/w/packages/billing/src/            <- the working directory
```

The walk-up finds the nearest primary first. Then discovery looks from the
parent of that root up to the boundary for a workspace that has the root as a
member. It passes over a directory with no file, with two files, with a file
that does not parse, or with a file that is not a workspace. With no enclosing
workspace, the found file is the project primary, and when it is a workspace,
discovery selects a member in this order:

| Order | Member |
| --- | --- |
| 1 | The member that holds the working directory |
| 2 | The default member, when it is in the workspace and not excluded |
| 3 | The only member, when the member entries give one |

With none of them, no member source loads.

A member entry is a path relative to the workspace root, with `/` between
segments. `*` matches any run of characters in one segment, and `**` matches
zero or more segments. Other characters, such as `?` and `[`, match themselves.
A literal entry, such as `members/alpha`, names its directory whether or not
it exists, so a missing member reports `NotFound` with its candidates. A
wildcard entry gives only the directories that hold a primary or legacy file,
and it never enters a hidden directory. An entry that is absolute, starts with
a drive, holds `\`, or holds a `..` segment gives a `Note` warning, and
discovery skips it. The workspace root is never its own member.

The members, exclude entries and default member come from the system file, the
global user file and the workspace primary, merged. `workspace(members?,
exclude?, default_member?, project_name?)` gives other key paths.

```mbt check
///|
test "the member file wins over the workspace file" {
  let builder = @config.builder()
    |> @config.working_dir("/w/packages/billing/src")
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.app_dirs("acme") |> @conventions.workspace)
  let tree = @config.FileTree::new(complete=true)
    .with_listing(@config.FileTreePath::parse("/w"), [
      { name: "acme.toml", kind: File },
      { name: "packages", kind: Directory },
    ])
    .with_listing(@config.FileTreePath::parse("/w/packages"), [{ name: "billing", kind: Directory }])
    .with_listing(@config.FileTreePath::parse("/w/packages/billing"), [
      { name: "acme.toml", kind: File },
      { name: "src", kind: Directory },
    ])
    .with_listing(@config.FileTreePath::parse("/w/packages/billing/src"), [])
    .with_file(@config.FileTreePath::parse("/w/acme.toml"),
      "workspace.members = [\"packages/*\"]\nui.theme = \"light\"",
    )
    .with_file(@config.FileTreePath::parse("/w/packages/billing/acme.toml"), "ui.theme = \"dark\"")
  guard @config.load(builder, tree) is Done(config) else {
    fail("a complete tree never asks for files")
  }
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("dark")
  let roles = config
    .reports()
    .filter(report => report.kind is File(Workspace | Member))
    .map(report => (report.kind, report.priority, report.path))
  @expect.expect(roles).to_equal([
    (File(Workspace), 300, Some("/w/acme.toml")),
    (File(Member), 350, Some("/w/packages/billing/acme.toml")),
  ])
}
```

`DiscoveryOptions(project=selector)`, for example from a `--project` flag,
selects a project by name or path. `.` selects the root project. Then the
selector matches a member path, such as `packages/billing`. Then it matches the
project name of the root or of a member primary. No match is an error,
`UnknownProject`. Two name matches are an error, `AmbiguousProject`, and the
message asks for a member path. Without the workspace part, a given `project`
option adds a `Note` warning.

### Key filters

Two filters remove keys from layers through the core `exclude`. A removed value
has no origin.

| Filter | Removes the keys from | Warning |
| --- | --- | --- |
| `member_scope_keys(paths)` | The member primary and its environment file, local override and user override | `KeyRemoved` in the report of the source, when the key was set |
| `inherited_filter(keys)` | The system file, the global user file, and the workspace primary and its adjacent files, when a member is selected | None |

Use `member_scope_keys` for a key that only the workspace can set, such as an
output directory. Use `inherited_filter` for the tables that describe the root
project, so that a member does not inherit them.

```mbt check
///|
test "a member cannot set a workspace key and does not inherit the root project" {
  let conventions = @conventions.app_dirs("acme")
    |> @conventions.workspace
    |> @conventions.member_scope_keys(["workspace.out_dir"])
    |> @conventions.inherited_filter(["project"])
  let builder = @config.builder()
    |> @config.working_dir("/w/app")
    |> @config.format(@toml.format())
    |> @conventions.add(conventions)
  let tree = @config.FileTree::new(complete=true)
    .with_listing(@config.FileTreePath::parse("/w"), [
      { name: "acme.toml", kind: File },
      { name: "app", kind: Directory },
    ])
    .with_listing(@config.FileTreePath::parse("/w/app"), [{ name: "acme.toml", kind: File }])
    .with_file(@config.FileTreePath::parse("/w/acme.toml"),
      "workspace.members = [\"app\"]\nworkspace.out_dir = \"out\"\nproject.name = \"root\"",
    )
    .with_file(@config.FileTreePath::parse("/w/app/acme.toml"), "workspace.out_dir = \"mine\"")
  guard @config.load(builder, tree) is Done(config) else {
    fail("a complete tree never asks for files")
  }
  @expect.expect(@config.get_text(config, "workspace.out_dir")).to_equal("out")
  @expect.expect(config.get(@config.KeyPath::parse("project.name"))).to_equal(
    None,
  )
  let member_report = config
    .reports()
    .iter()
    .find_first(report => report.kind == File(Member))
  @expect.expect(member_report.map(report => report.warnings.length())).to_equal(
    Some(1),
  )
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
    ListDir(@config.FileTreePath::parse("/w/src")),
    ListDir(@config.FileTreePath::parse("/w/src/.acme")),
    ListDir(@config.FileTreePath::parse("/w/src/.config/acme")),
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
| `workspace(members?, exclude?, default_member?, project_name?)` | Turns on workspaces and member selection, with the key paths of the workspace values |
| `member_scope_keys(paths)` | Keys that only the workspace can set; a member layer loses them with a `KeyRemoved` warning |
| `inherited_filter(keys)` | Keys that a selected member does not inherit from the system, global and workspace layers |
| `environment_name(conventions, options?, env_vars)` | The environment name of the run, or `None` |
| `check_environment_name(name, source~)` | Checks a name with the environment name rules |
| `add(builder, conventions, options?)` | The provider that runs discovery during `@config.load` |
| `prefix` | The environment variable prefix; defaults to the name in upper case with `-` changed to `_` |
| `display` | The name that the ambiguity message shows; defaults to the name |
| `DiscoveryOptions` | The inputs that a host gives from its arguments: environment, explicit primary, isolated mode, and project |

## Compose configuration profiles

Enable profiles explicitly. They use files such as `acme.profile.metrics.toml`,
independently of `acme.Production.toml`. Includes precede the selected roots;
groups expand in order, retain the group name, and keep each name's last
occurrence. Profile layers use priority 380, after environment files and before
local and user overrides. Missing files leave active code-only markers.

```mbt check
///|
test "load controls and a profile with recorded metadata" {
  let tree = @config.FileTree::new(complete=true)
    .with_listing(@config.FileTreePath::parse("/workspace"), [
      { name: "acme.toml", kind: File },
      { name: "acme.profile.metrics.toml", kind: File },
    ])
    .with_file(@config.FileTreePath::parse("/workspace/acme.toml"),
      "[profiles]\nactive=['production']\n[profiles.groups]\nproduction=['metrics']")
    .with_file(@config.FileTreePath::parse("/workspace/acme.profile.metrics.toml"),
      "telemetry=true")
  let builder = @config.builder()
    |> @config.working_dir("/workspace") |> @config.env_vars({})
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.base("acme") |> @conventions.layouts
      |> @conventions.profiles(@profiles.Policy::new()))
  guard @config.load(builder,tree) is Done(config) else { fail("complete tree") }
  assert_true(config.profiles().contains(@config.ProfileName::parse("metrics")))
  assert_eq(config.get(@config.KeyPath::parse("profiles")),None)
}
```

Selection precedence is discovery options, `<PREFIX>_PROFILES`, base `active`,
base `default`, then policy fallback. Use `Selected(ProfileNames::new([]))` to
suppress defaults while keeping includes; use `Disabled` to suppress both. A
present empty selector variable also disables profiles. Standalone environment
sources must reserve that exact variable, for example
`@config.env(prefix="ACME", reserved=["ACME_PROFILES"])`.

Only the standard-layout workspace primaries, or project primaries without a
workspace, supply controls. Ordered formats and their supplemental documents
form one base; each winning control retains its supplying source. Selected member and overlay controls fail before
key filters. Enabled controls stay out of application values and provenance;
`Config::profiles()` gives the recorded selector, active order and reasons.
The [profile policy guide](../profiles/README.mbt.md) covers names, groups and
limits. Existing applications keep their behavior until they enable profiles.

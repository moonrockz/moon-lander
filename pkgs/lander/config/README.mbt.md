# Configuration

The `config` package (`@config`) loads configuration for a MoonBit application. It
reads ordered sources, parses files with the formats that you register, and merges
everything into one value tree. The package is pure: it never reads a file, the
process environment, or the working directory itself. A host gives it those inputs,
so a load gives the same result on `wasm`, `wasm-gc`, `js`, and `native`.

Import `moonrockz/moon-lander/config` as `@config` and a format package such as
`moonrockz/moon-lander/config/formats/toml` as `@toml`. Each `mbt check` block on
this page runs as a test with `mise run test`.

> [!NOTE]
> The configuration core is in progress. This page shows the API that exists
> today. Environment variables, provenance, the YAML, JSON and Ion formats, the
> host adapters, discovery, and binding come in later changes. The
> [design overview](../../../docs/design/overview.md) shows the full plan.

## One load, start to finish

An application describes its sources with a builder. The pure `load` reads only
the builder and a file tree. When the tree does not hold a file that a source
needs, `load` asks for it. The host reads the files and calls `load` again.

```mermaid
graph TD
  B[Builder and file tree] --> L[Load]
  L --> N[Need: file requests]
  N --> H[Host adds the answers to the tree]
  H --> A[Load again]
  A --> C[Done: Config]
```

| Step | What happens |
| --- | --- |
| Describe | Add sources and formats to a `ConfigBuilder`, in merge order |
| Load | `@config.load(builder, tree)` gives `Need(requests)` or `Done(config)` |
| Answer | The host adds each answer to the tree and loads again |
| Merge | Each source is parsed, filtered, and merged over the sources before it |
| Read | `Config::get`, `get_text`, `Config::reports`, and `Config::warnings` |

## The smallest program

Sources that hold values need no files. `build` loads them over an empty, complete
file tree. A later source wins.

```mbt check
///|
test "the smallest program" {
  let config = @config.build([
    @config.in_memory_pairs([("app.name", @config.string("demo"))]),
    @config.in_memory_pairs([("app.name", @config.string("acme"))]),
  ])
  @expect.expect(@config.get_text(config, "app.name")).to_equal("acme")
}
```

## Sources and the builder

Each source has a kind, a display name, a display priority, and an input. Add
them to the builder in merge order: low first, high last. Every function returns
a new builder, so you can keep a base builder and extend it.

| Constructor | Kind | Input |
| --- | --- | --- |
| `ConfigSource::defaults(json)`, `@config.defaults(builder, json)` | `Defaults` | A JSON object, for example `Defaults::default().to_json()` |
| `ConfigSource::defaults_value(value)` | `Defaults` | A value tree |
| `in_memory(value)`, `in_memory_pairs(pairs)` | `InMemory` | A value tree, or key-path and value pairs |
| `ConfigSource::file(path, role~)`, `@config.file(builder, path)` | `File(role)` | One explicit file |
| `ConfigSource::candidates(paths, display~)` | `File(role)` | A list of candidate files at one location |
| `ConfigSource::skipped(kind)` | any | Nothing; the report shows `Skipped` |

```mbt check
///|
test "describe sources with a builder" {
  let base = @config.builder()
    |> @config.format(@toml.format())
    |> @config.defaults({ "server": { "port": 8080, "host": "localhost" } })
  let builder = base
    |> @config.file("/srv/app.toml")
    |> @config.add(
      @config.in_memory_pairs([("server.port", @config.int(9000))]),
    )
  let tree = @config.FileTree::new(complete=true).with_file(
    "/srv/app.toml",
    (
      #|[server]
      #|host = "example.org"
    ),
  )
  guard @config.load(builder, tree) is Done(config) else {
    fail("a complete tree never asks for files")
  }
  @expect.expect(@config.get_text(config, "server.host")).to_equal(
    "example.org",
  )
  @expect.expect(@config.get_text(config, "server.port")).to_equal("9000")
}
```

## The layer stack

Merge order decides which value wins. Each source also has a priority that reports
show. When you give no priority, it comes from the kind and the file role. An
in-memory source takes the priority of the source before it, so it fits at any
position.

```layers
Overrides (700) | command-line values
Environment variables (600) | APP_SERVER__PORT=9000
User override file (400) | app.user.toml
Local override file (390) | app.local.toml
Environment file (375) | app.Staging.toml
Workspace member file (350) | pkgs/api/app.toml
Workspace, explicit, or legacy file (300) | app.toml
Global user file (200) | ~/.config/app/
System file (100) | /etc/app/
Defaults (0) | compiled in
```

Added in this order, the sources merge from the bottom up, so the top layer wins.
A priority that is lower than the one before it is an error, because the list
order and the reports would disagree. Equal priorities are allowed.

```mbt check
///|
test "a decreasing priority is an error" {
  let builder = @config.builder()
    |> @config.add(@config.ConfigSource::skipped(Environment))
    |> @config.file("/srv/app.toml", priority=300)
  try @config.load(builder, @config.FileTree::new(complete=true)) catch {
    SourceOrder(previous~, previous_priority~, ..) =>
      @expect.expect((previous, previous_priority)).to_equal((
        "environment", 600,
      ))
    _ => fail("expected a source-order error")
  } noraise {
    _ => fail("expected a source-order error")
  }
}
```

## Files and the request loop

A `FileTree` is an immutable snapshot of what the host has read: directory
listings, file text, and absence records. A path is held, missing, or unknown.
`load` asks only for unknown paths, and it asks for all of them in one step. In a
complete tree every path that the tree does not hold is missing, so `load` never
asks.

| `FileTree` call | Effect |
| --- | --- |
| `FileTree::new(complete?)` | An empty tree |
| `with_file(path, text)` | Holds the text of a file |
| `with_listing(dir, entries)` | Holds a directory listing with the real names |
| `with_missing(path)` | Records a path as absent; a directory makes every path under it absent |

A host runs this loop. Native and js hosts read the disk; a wasm host gives a
complete tree. The loop below answers from a map, so it runs on every target.

```mbt check
///|
/// Answer one request from `disk`, a map from file path to text. A directory
/// exists when a file path in `disk` is below it.
fn answer(
  tree : @config.FileTree,
  request : @config.FileRequest,
  disk : Map[String, String],
) -> @config.FileTree {
  match request {
    ReadFile(path) =>
      match disk.get(path) {
        Some(text) => tree.with_file(path, text)
        None => tree.with_missing(path)
      }
    ListDir(dir) => {
      let entries : Array[@config.DirEntry] = []
      for path, _ in disk {
        guard path.has_prefix(dir + "/") else { continue }
        let rest = path[dir.length() + 1:].to_owned()
        let entry : @config.DirEntry = match rest.find("/") {
          Some(index) => { name: rest[:index].to_owned(), kind: Directory }
          None => { name: rest, kind: File }
        }
        if !entries.contains(entry) {
          entries.push(entry)
        }
      }
      if entries.is_empty() {
        tree.with_missing(dir)
      } else {
        tree.with_listing(dir, entries)
      }
    }
  }
}

///|
/// Load until the configuration is done, answering each request from `disk`.
fn load_from(
  builder : @config.ConfigBuilder,
  disk : Map[String, String],
  tree? : @config.FileTree = @config.FileTree::new(),
) -> @config.Config raise @config.ConfigError {
  match @config.load(builder, tree) {
    Done(config) => config
    Need(requests) =>
      load_from(
        builder,
        disk,
        tree=requests.fold(init=tree, (tree, request) => {
          answer(tree, request, disk)
        }),
      )
  }
}

///|
test "a host answers the requests of a load" {
  let builder = @config.builder()
    |> @config.working_dir("/srv")
    |> @config.format(@toml.format())
    |> @config.file("conf/app.toml")
  let config = load_from(builder, { "/srv/conf/app.toml": "name = \"acme\"" })
  @expect.expect(@config.get_text(config, "name")).to_equal("acme")
  @expect.expect(config.reports()[0].path).to_equal(Some("/srv/conf/app.toml"))
}
```

A relative path joins the working directory that `@config.working_dir` sets. A
missing explicit file is an error, `FileNotFound`.

## Candidate files

A candidate list names the files that may hold one source, for example
`app.toml` and `app.yaml` in one directory. A candidate exists when the listing of
its directory holds its exact name as a file, also on a file system that ignores
case. The load never chooses between two existing candidates.

| Existing candidates | Result |
| --- | --- |
| None | The report shows `NotFound` and the source adds nothing |
| One | The load reads and parses it; the report shows `Loaded` and its path |
| More than one | `Ambiguous(display~, location~, candidates~)` |

```mbt check
///|
test "one existing candidate loads" {
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.add(
      @config.ConfigSource::candidates(
        ["/srv/app.toml", "/srv/.config/app.toml"],
        display="App",
      ),
    )
  let config = load_from(builder, { "/srv/.config/app.toml": "mode = \"dev\"" })
  let report = config.reports()[0]
  @expect.expect((report.status, report.path)).to_equal((
    Loaded,
    Some("/srv/.config/app.toml"),
  ))
}

///|
test "two existing candidates are ambiguous" {
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.add(
      @config.ConfigSource::candidates(
        ["/srv/app.toml", "/srv/.config/app.toml"],
        display="App",
      ),
    )
  let disk = { "/srv/app.toml": "", "/srv/.config/app.toml": "" }
  try load_from(builder, disk) catch {
    Ambiguous(location~, candidates~, ..) as error => {
      @expect.expect(location).to_equal("/srv")
      @expect.expect(candidates.length()).to_equal(2)
      @expect.expect(error.message()).to_start_with(
        "Ambiguous App configuration; found:",
      )
    }
    _ => fail("expected an ambiguity error")
  } noraise {
    _ => fail("expected an ambiguity error")
  }
}
```

## Formats

A format turns file text into a value tree with a struct root. Register the
formats that the application reads; the file extension selects one, compared in
lowercase. `parse_file` gives other packages the same selection.

| Package | Format | Extensions | Status |
| --- | --- | --- | --- |
| `config/formats/toml` | TOML | `toml` | Available; dates come later |
| YAML, JSON and JSON5, Ion | | `yaml`, `yml`, `json`, `json5`, `ion` | Later changes |

```mbt check
///|
test "the extension selects the format" {
  let formats = @config.builder()
    |> @config.format(@toml.format())
    |> @config.ConfigBuilder::formats
  @expect.expect(@config.parse_file(formats, "/srv/APP.TOML", "a = 1")).to_equal(
    @config.fields([("a", @config.int(1))]),
  )
  try @config.parse_file(formats, "/srv/app.ion", "{}") catch {
    UnsupportedFormat(extensions~, ..) =>
      @expect.expect(extensions).to_equal(["toml"])
    _ => fail("expected an unsupported-format error")
  } noraise {
    _ => fail("expected an unsupported-format error")
  }
}
```

## Merge rules

| Base | Overlay | Result |
| --- | --- | --- |
| struct | struct | Fields merge one by one; base fields first, new fields after |
| any | any other value | The overlay wins |
| list | list | The overlay list replaces the base list |

## Excluding a subtree

A source can drop key paths after the parse and before the merge. A layer that a
project inherits can drop the identity of another project without a warning. A
member layer can drop a key that only the workspace may set, with a warning.

```mbt check
///|
test "an excluded key warns" {
  let source = @config.in_memory_pairs([
      ("workspace.out_dir", @config.string("out")),
      ("ir.layout", @config.string("tree")),
    ])
    .exclude([@config.KeyPath::parse("workspace.out_dir")], warn=true)
  let config = @config.build([source])
  @expect.expect(config.get(@config.KeyPath::parse("workspace.out_dir"))).to_equal(
    None,
  )
  @expect.expect(config.warnings().length()).to_equal(1)
}
```

## Source providers

A source provider gives sources during the load, at its position in the list.
Discovery uses this hook. A provider gets a `LoadContext` with the file tree, the
platform, the variable set, the working directory, and the formats. It gives
`Need(requests)` until the tree holds what it reads, then `Done` with its sources
and warnings. A provider reads only the context, never the process.

```mbt check
///|
test "a provider adds the file of its directory" {
  let local_file : @config.SourceProvider = {
    name: "local",
    expand: context => {
      guard context.working_dir is Some(dir) else {
        return Done({ sources: [], warnings: [] })
      }
      Done({
        sources: [
          @config.ConfigSource::candidates(
            ["\{dir}/app.local.toml"],
            display="local",
            role=LocalOverride,
          ),
        ],
        warnings: [],
      })
    },
  }
  let builder = @config.builder()
    |> @config.working_dir("/srv")
    |> @config.format(@toml.format())
    |> @config.provider(local_file)
  let config = load_from(builder, { "/srv/app.local.toml": "debug = true" })
  @expect.expect(@config.get_text(config, "debug")).to_equal("true")
  @expect.expect(config.reports()[0].priority).to_equal(390)
}
```

## Errors

Every failure is one `ConfigError` case with labelled fields, so a caller matches
the case and does not compare text. `message()` gives text for people.

| Case | When |
| --- | --- |
| `Parse`, `InvalidRoot`, `DuplicateKey` | A file or value tree is not valid |
| `FileNotFound` | An explicit file does not exist |
| `UnsupportedFormat` | No registered format reads the extension |
| `Ambiguous` | More than one candidate exists |
| `SourceOrder` | A priority decreases |
| `InvalidKeyPath`, `KeyNotFound`, `Render` | A key path or a lookup fails |

Later changes raise the other cases: environment keys, merge keys, secrets,
discovery, and binding.

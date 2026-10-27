///|
/// A stand-in for the YAML format, which a later task adds.
fn yaml_stub() -> @config.Format {
  {
    name: "YAML",
    extensions: ["yaml", "yml"],
    parse: (_, _) => @config.fields([("format", @config.string("yaml"))]),
  }
}

///|
fn files(names : Array[String]) -> Array[@config.DirEntry] {
  names.map(name => { name, kind: File })
}

///|
fn dirs(names : Array[String]) -> Array[@config.DirEntry] {
  names.map(name => { name, kind: Directory })
}

///|
fn acme(working_dir : String) -> @config.ConfigBuilder {
  @config.builder()
  |> @config.working_dir(working_dir)
  |> @config.format(@toml.format())
  |> @conventions.add(@conventions.app_dirs("acme"))
}

///|
fn done(step : @config.LoadStep[@config.Config]) -> @config.Config {
  guard step is Done(config) else { abort("expected a configuration") }
  config
}

///|
/// The report of the project primary.
fn project(config : @config.Config) -> @config.SourceReport {
  guard config
    .reports()
    .search_by(report => report.kind is File(Workspace | Legacy | Explicit))
    is Some(index) else {
    abort("expected a project report")
  }
  config.reports()[index]
}

///|
/// The note that discovery adds when the run gives no platform.
let no_platform : String = "discovery has no platform, so it skips the system and global user directories"

///|
test "discovery reads one listing of a complete tree" {
  let tree = @config.FileTree::new(complete=true)
    .with_listing(p("/w"), files(["acme.toml"]))
    .with_file(p("/w/acme.toml"), "project.name = \"demo\"")
  let config = acme("/w") |> @config.load(tree) |> done
  @expect.expect(@config.get_text(config, "project.name")).to_equal("demo")
}

///|
test "Configuration found from a nested directory" {
  let tree = @config.FileTree::new(complete=true)
    .with_listing(p("/w"), [..files(["acme.toml"]), ..dirs(["src"])])
    .with_listing(p("/w/src"), dirs(["nested"]))
    .with_listing(p("/w/src/nested"), [])
    .with_file(p("/w/acme.toml"), "project.name = \"root\"")
  let config = acme("/w/src/nested") |> @config.load(tree) |> done
  let report = project(config)
  @expect.expect((report.kind, report.priority, report.path, report.status)).to_equal((
    File(Workspace),
    300,
    Some("/w/acme.toml"),
    Loaded,
  ))
  @expect.expect(@config.get_text(config, "project.name")).to_equal("root")
}

///|
test "Nearest configuration wins" {
  let tree = @config.FileTree::new(complete=true)
    .with_listing(p("/w"), [..files(["acme.toml"]), ..dirs(["sub"])])
    .with_listing(p("/w/sub"), [..files(["acme.toml"]), ..dirs(["deep"])])
    .with_listing(p("/w/sub/deep"), [])
    .with_file(p("/w/acme.toml"), "project.name = \"root\"")
    .with_file(p("/w/sub/acme.toml"), "project.name = \"sub\"")
  let config = acme("/w/sub/deep") |> @config.load(tree) |> done
  @expect.expect(@config.get_text(config, "project.name")).to_equal("sub")
}

///|
/// Load until done, answering each request from `disk`, a map from file path
/// to text. A directory exists when a file path in `disk` is below it.
fn load_from(
  builder : @config.ConfigBuilder,
  disk : Map[String, String],
  rounds? : Ref[Int] = Ref(0),
  tree? : @config.FileTree = @config.FileTree::new(),
) -> @config.Config raise @config.ConfigError {
  match @config.load(builder, tree) {
    Done(config) => config
    Need(requests) => {
      rounds.val += 1
      let tree = requests.fold(init=tree, (tree, request) => {
        match request {
          ReadFile(path) =>
            match disk.get(path.to_string()) {
              Some(text) => tree.with_file(path, text)
              None => tree.with_missing(path)
            }
          ListDir(dir) => {
            let entries : Array[@config.DirEntry] = []
            for text, _ in disk {
              let path = p(text)
              guard path != dir && path.is_within(dir) else { continue }
              let below = path.names()[dir.names().length():]
              let entry : @config.DirEntry = if below.length() > 1 {
                { name: below[0], kind: Directory }
              } else {
                { name: below[0], kind: File }
              }
              if !entries.contains(entry) {
                entries.push(entry)
              }
            }
            tree.with_listing(dir, entries)
          }
        }
      })
      load_from(builder, disk, rounds~, tree~)
    }
  }
}

///|
test "the core load runs discovery and asks for each directory" {
  let rounds = Ref(0)
  let config = load_from(
    acme("/w/src/nested"),
    { "/w/acme.toml": "project.name = \"walked\"", "/w/src/nested/x.txt": "" },
    rounds~,
  )
  @expect.expect(@config.get_text(config, "project.name")).to_equal("walked")
  // The listings of /w/src/nested, /w/src and /w, then the file.
  @expect.expect(rounds.val).to_equal(4)
}

///|
test "the first request lists the layout directories of the start directory" {
  let step = acme("/w/src") |> @config.load(@config.FileTree::new())
  @expect.expect(needs(step)).to_equal([
    ListDir(p("/w/src")),
    ListDir(p("/w/src/.acme")),
    ListDir(p("/w/src/.config/acme")),
  ])
}

///|
test "no primary reports not-found at the start directory" {
  let config = load_from(acme("/w/src"), { "/w/src/main.mbt": "" })
  let report = project(config)
  @expect.expect((report.status, report.candidates)).to_equal((
    NotFound,
    ["/w/src/acme.toml", "/w/src/.acme/acme.toml", "/w/src/.config/acme/config.toml"],
  ))
}

///|
test "two primaries in the nearest directory are ambiguous" {
  let builder = acme("/w/sub") |> @config.format(yaml_stub())
  let disk = {
    "/w/acme.toml": "",
    "/w/sub/acme.toml": "",
    "/w/sub/acme.yaml": "",
  }
  try load_from(builder, disk) catch {
    Ambiguous(display~, location~, candidates~) => {
      @expect.expect((display, location)).to_equal(("acme", "/w/sub"))
      @expect.expect(candidates).to_equal(["/w/sub/acme.toml", "/w/sub/acme.yaml"])
    }
    _ => fail("expected an ambiguity error")
  } noraise {
    _ => fail("expected an ambiguity error")
  }
}

///|
test "searched extensions come from the registered formats" {
  let builder = acme("/w")
  let config = load_from(builder, { "/w/acme.yaml": "a: 1" })
  @expect.expect(project(config).status).to_equal(NotFound)
}

///|
test "discovery without a working directory is skipped with a note" {
  let config = @config.builder()
    |> @conventions.add(@conventions.app_dirs("acme", display="Acme"))
    |> @config.load(@config.FileTree::new())
    |> done
  @expect.expect(project(config).status).to_equal(Skipped)
  @expect.expect(config.warnings()).to_equal([
    Note(source="Acme", message=no_platform),
    Note(
      source="Acme",
      message="discovery has no working directory to start from",
    ),
  ])
}

///|
test "a base convention set searches no file" {
  let config = @config.builder()
    |> @config.working_dir("/w")
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.base("acme"))
    |> @config.load(@config.FileTree::new())
    |> done
  @expect.expect(project(config).candidates).to_equal([])
}

///|
test "the prefix and display name have defaults" {
  let conventions = @conventions.base("my-app")
  @expect.expect((conventions.prefix(), conventions.display())).to_equal((
    "MY_APP", "my-app",
  ))
  let named = @conventions.app_dirs("morphir", prefix="MORPHIR", display="Morphir")
  @expect.expect((named.name(), named.prefix(), named.display())).to_equal((
    "morphir", "MORPHIR", "Morphir",
  ))
}

///|
test "discovery options default to not given" {
  @expect.expect(@conventions.DiscoveryOptions::new()).to_equal({
    environment: None,
    config: Discover,
    isolated: false,
    project: None,
  })
}

///|
test "discovery needs an absolute working directory" {
  let tree = @config.FileTree::new(complete=true)
    .with_listing(p("repo/sub"), [{ name: "acme.toml", kind: File }])
    .with_file(p("repo/sub/acme.toml"), "a = 1")
  let config = acme("repo/sub") |> @config.load(tree) |> done
  @expect.expect(project(config).status).to_equal(Skipped)
  @expect.expect(config.warnings()).to_equal([
    Note(source="acme", message=no_platform),
    Note(
      source="acme",
      message="discovery needs an absolute working directory, not repo/sub",
    ),
  ])
}

///|
/// The parsed path of the test path `text`.
fn p(text : String) -> @config.FileTreePath {
  @config.FileTreePath::parse(text) catch {
    _ => abort("invalid test path \{text}")
  }
}

///|
/// The requests of a load step that needs files.
fn[T] needs(step : @config.LoadStep[T]) -> Array[@config.FileRequest] {
  guard step is Need(requests) else { abort("the load step needs no files") }
  requests
}

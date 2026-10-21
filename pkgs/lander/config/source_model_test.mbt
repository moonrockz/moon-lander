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
fn done(step : @config.LoadStep[@config.Config]) -> @config.Config {
  guard step is Done(config) else { abort("expected a configuration") }
  config
}

///|
fn load_error(run : () -> Unit raise @config.ConfigError) -> @config.ConfigError {
  try run() catch {
    error => error
  } noraise {
    _ => abort("expected a configuration error")
  }
}

///|
fn statuses(config : @config.Config) -> Array[@config.SourceStatus] {
  config.reports().map(report => report.status)
}

///|
fn priorities(config : @config.Config) -> Array[Int] {
  config.reports().map(report => report.priority)
}

///|
fn complete() -> @config.FileTree {
  @config.FileTree::new(complete=true)
}

///|
test "Skip a source" {
  let config = @config.builder()
    |> @config.env_vars({ "APP_IR__LAYOUT": "tree" })
    |> @config.add(@config.ConfigSource::skipped(Environment))
    |> @config.load(complete())
    |> done
  @expect.expect(config.get(key("ir.layout"))).to_equal(None)
  @expect.expect(statuses(config)).to_equal([Skipped])
}

///|
test "Same kind at two positions" {
  let config = @config.build([
    @config.in_memory_pairs([("a", @config.int(1))]),
    @config.ConfigSource::defaults({ "b": 1 }),
    @config.in_memory_pairs([("a", @config.int(2))]),
  ])
  @expect.expect(@config.get_text(config, "a")).to_equal("2")
}

///|
test "Defaults from JSON" {
  let config = @config.builder()
    |> @config.defaults({ "ir": { "layout": "tree" } })
    |> @config.load(complete())
    |> done
  @expect.expect(@config.get_text(config, "ir.layout")).to_equal("tree")
  let report = config.reports()[0]
  @expect.expect((report.kind, report.name)).to_equal((Defaults, "defaults"))
}

///|
test "a defaults root that is not an object raises an invalid-root error" {
  let error = load_error(() => {
    @config.ConfigSource::defaults([1, 2]) |> ignore
  })
  @expect.expect(error).to_equal(InvalidRoot(origin="defaults", found="list"))
}

///|
test "Default priorities" {
  let config = @config.builder()
    |> @config.format(@toml.format())
    |> @config.defaults({ "a": 1 })
    |> @config.file("/w/app.toml")
    |> @config.add(@config.in_memory_pairs([("b", @config.int(2))]))
    |> @config.add(@config.ConfigSource::skipped(Environment))
    |> @config.add(@config.ConfigSource::skipped(Overrides))
    |> @config.load(complete().with_file("/w/app.toml", "c = 3"))
    |> done
  @expect.expect(priorities(config)).to_equal([0, 300, 300, 600, 700])
}

///|
test "default priorities of the other file roles" {
  let config = @config.build(
    ([System, Global, Legacy, Workspace, Member] : Array[@config.FileRole]).map(role => {
      @config.ConfigSource::skipped(File(role))
    }),
  )
  @expect.expect(priorities(config)).to_equal([100, 200, 300, 300, 350])
}

///|
test "Override file priorities" {
  let config = @config.build(
    ([EnvironmentFile, LocalOverride, UserOverride] : Array[@config.FileRole]).map(role => {
      @config.ConfigSource::skipped(File(role))
    }),
  )
  @expect.expect(priorities(config)).to_equal([375, 390, 400])
}

///|
test "a first in-memory source has the priority 0" {
  let config = @config.build([
    @config.in_memory_pairs([("a", @config.int(1))]),
    @config.ConfigSource::skipped(Environment),
    @config.in_memory_pairs([("a", @config.int(2))]),
  ])
  @expect.expect(priorities(config)).to_equal([0, 600, 600])
}

///|
test "Decreasing priority" {
  let builder = @config.builder()
    |> @config.add(@config.ConfigSource::skipped(Environment))
    |> @config.file("/w/app.toml", priority=300)
  let error = load_error(() => {
    @config.load(builder, complete()) |> ignore
  })
  @expect.expect(error).to_equal(
    SourceOrder(
      source="/w/app.toml",
      priority=300,
      previous="environment",
      previous_priority=600,
    ),
  )
}

///|
test "equal priorities are allowed" {
  let config = @config.build([
    @config.ConfigSource::skipped(File(Workspace), name="a"),
    @config.ConfigSource::skipped(File(Explicit), name="b"),
  ])
  @expect.expect(priorities(config)).to_equal([300, 300])
}

///|
test "Incomplete tree asks for files" {
  let step = @config.builder()
    |> @config.format(@toml.format())
    |> @config.file("/w/app.toml")
    |> @config.load(@config.FileTree::new())
  @expect.expect(step is Need([ReadFile("/w/app.toml")])).to_equal(true)
}

///|
test "Complete tree never asks" {
  let config = @config.builder()
    |> @config.format(@toml.format())
    |> @config.add(
      @config.ConfigSource::candidates(["/w/.config/app.toml"], display="App"),
    )
    |> @config.load(complete())
    |> done
  @expect.expect(statuses(config)).to_equal([NotFound])
}

///|
test "Absence record answers a request" {
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.file("/w/app.toml")
  let tree = @config.FileTree::new().with_missing("/w/app.toml")
  let error = load_error(() => {
    @config.load(builder, tree) |> ignore
  })
  @expect.expect(error).to_equal(FileNotFound(path="/w/app.toml"))
}

///|
test "Missing directory answers its children" {
  let tree = @config.FileTree::new().with_missing("/w/.config")
  let config = @config.builder()
    |> @config.format(@toml.format())
    |> @config.add(
      @config.ConfigSource::candidates(
        ["/w/.config/app.toml", "/w/.config/sub/app.toml"],
        display="App",
      ),
    )
    |> @config.load(tree)
    |> done
  @expect.expect(statuses(config)).to_equal([NotFound])
  @expect.expect(tree.file("/w/.config/sub/app.toml")).to_equal(Missing)
  @expect.expect(tree.listing("/w/.configs")).to_equal(Unknown)
}

///|
test "the load asks for every unknown path in one step" {
  let step = @config.builder()
    |> @config.format(@toml.format())
    |> @config.file("/w/a.toml")
    |> @config.add(
      @config.ConfigSource::candidates(["/w/b.toml", "/v/b.toml"], display="B"),
    )
    |> @config.file("/w/a.toml", name="again")
    |> @config.load(@config.FileTree::new())
  @expect.expect(step is Need([ReadFile("/w/a.toml"), ListDir("/w"), ListDir("/v")])).to_equal(
    true,
  )
}

///|
/// A provider that gives one file source at `/w/app.toml` once the tree holds
/// the listing of `/w`, and records the context that it gets.
fn file_provider(seen : Ref[@config.LoadContext?]) -> @config.SourceProvider {
  {
    name: "files",
    expand: context => {
      seen.val = Some(context)
      match context.tree.listing("/w") {
        Unknown => Need([ListDir("/w")])
        _ =>
          Done({
            sources: [@config.ConfigSource::file("/w/app.toml", priority=300)],
            warnings: [Note(source="files", message="one file")],
          })
      }
    },
  }
}

///|
test "Provider sources take its position" {
  let seen = Ref(None)
  let tree = complete()
    .with_listing("/w", [{ name: "app.toml", kind: File }])
    .with_file("/w/app.toml", "a = 1")
  let config = @config.builder()
    |> @config.format(@toml.format())
    |> @config.defaults({ "a": 0 })
    |> @config.provider(file_provider(seen))
    |> @config.add(@config.ConfigSource::skipped(Environment))
    |> @config.load(tree)
    |> done
  @expect.expect(config.reports().map(report => report.name)).to_equal([
    "defaults", "/w/app.toml", "environment",
  ])
  @expect.expect(@config.get_text(config, "a")).to_equal("1")
  @expect.expect(config.warnings()).to_equal([
    Note(source="files", message="one file"),
  ])
}

///|
test "Provider requests pass out of the load" {
  let seen = Ref(None)
  let step = @config.builder()
    |> @config.format(@toml.format())
    |> @config.provider(file_provider(seen))
    |> @config.file("/w/other.toml")
    |> @config.load(@config.FileTree::new())
  @expect.expect(step is Need([ListDir("/w"), ReadFile("/w/other.toml")])).to_equal(
    true,
  )
}

///|
test "Provider gets the platform" {
  let seen = Ref(None)
  @config.builder()
  |> @config.platform(Windows)
  |> @config.env_vars({ "APP_A": "1" })
  |> @config.working_dir("/w")
  |> @config.format(@toml.format())
  |> @config.provider(file_provider(seen))
  |> @config.load(@config.FileTree::new())
  |> ignore
  guard seen.val is Some(context) else { fail("the provider did not run") }
  @expect.expect(context.platform).to_equal(Some(Windows))
  @expect.expect(context.env_vars).to_equal({ "APP_A": "1" })
  @expect.expect(context.working_dir).to_equal(Some("/w"))
  @expect.expect(context.formats.map(format => format.name)).to_equal(["TOML"])
}

///|
test "a provider gets an empty variable set and no platform by default" {
  let seen = Ref(None)
  @config.builder()
  |> @config.provider(file_provider(seen))
  |> @config.load(@config.FileTree::new())
  |> ignore
  guard seen.val is Some(context) else { fail("the provider did not run") }
  @expect.expect((context.platform, context.env_vars.length())).to_equal((
    None, 0,
  ))
}

///|
test "Registered formats are visible" {
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.format(yaml_stub())
  @expect.expect(
    builder.formats().map(format => (format.name, format.extensions)),
  ).to_equal([("TOML", ["toml"]), ("YAML", ["yaml", "yml"])])
}

///|
test "Parse with the registry" {
  let formats = [@toml.format(), yaml_stub()]
  @expect.expect(@config.parse_file(formats, "/w/app.yaml", "a: 1")).to_equal(
    @config.fields([("format", @config.string("yaml"))]),
  )
  @expect.expect(@config.parse_file(formats, "/w/APP.TOML", "a = 1")).to_equal(
    @config.fields([("a", @config.int(1))]),
  )
}

///|
test "Extension selects the format" {
  let config = @config.builder()
    |> @config.format(@toml.format())
    |> @config.format(yaml_stub())
    |> @config.file("conf/app.yaml")
    |> @config.load(complete().with_file("conf/app.yaml", "a: 1"))
    |> done
  @expect.expect(@config.get_text(config, "format")).to_equal("yaml")
}

///|
test "Missing explicit file" {
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.file("conf/app.toml")
  let error = load_error(() => {
    @config.load(builder, complete()) |> ignore
  })
  @expect.expect(error).to_equal(FileNotFound(path="conf/app.toml"))
}

///|
test "Unregistered extension" {
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.file("app.ion")
  let error = load_error(() => {
    @config.load(builder, complete()) |> ignore
  })
  @expect.expect(error).to_equal(
    UnsupportedFormat(path="app.ion", extensions=["toml"]),
  )
}

///|
test "a file with no extension is unsupported" {
  let error = load_error(() => {
    @config.parse_file([@toml.format()], "/w/.toml", "") |> ignore
  })
  @expect.expect(error).to_equal(
    UnsupportedFormat(path="/w/.toml", extensions=["toml"]),
  )
}

///|
test "Relative path joins the working directory" {
  let builder = @config.builder()
    |> @config.working_dir("/w")
    |> @config.format(@toml.format())
    |> @config.file("conf/app.toml")
    |> @config.file("/etc/app.toml")
    |> @config.file("C:/app.toml")
  let step = builder |> @config.load(@config.FileTree::new())
  @expect.expect(
    step
    is Need(
      [
        ReadFile("/w/conf/app.toml"),
        ReadFile("/etc/app.toml"),
        ReadFile("C:/app.toml"),
      ]
    ),
  ).to_equal(true)
  let config = builder
    |> @config.load(
      complete()
      .with_file("/w/conf/app.toml", "a = 1")
      .with_file("/etc/app.toml", "b = 1")
      .with_file("C:/app.toml", "c = 1"),
    )
    |> done
  @expect.expect(config.reports().map(report => report.path)).to_equal([
    Some("/w/conf/app.toml"),
    Some("/etc/app.toml"),
    Some("C:/app.toml"),
  ])
}

///|
fn listing(names : Array[String]) -> Array[@config.DirEntry] {
  names.map(name => { name, kind: File })
}

///|
test "Two candidates exist" {
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.format(yaml_stub())
    |> @config.add(
      @config.ConfigSource::candidates(
        ["/w/app.toml", "/w/app.yaml"],
        display="App",
      ),
    )
  let tree = complete().with_listing("/w", listing(["app.toml", "app.yaml"]))
  let error = load_error(() => {
    @config.load(builder, tree) |> ignore
  })
  guard error is Ambiguous(location~, candidates~, ..) else {
    fail("expected an ambiguity error")
  }
  @expect.expect((location, candidates)).to_equal((
    "/w",
    ["/w/app.toml", "/w/app.yaml"],
  ))
  @expect.expect(error.message()).to_start_with(
    "Ambiguous App configuration; found:",
  )
}

///|
test "One candidate exists" {
  let config = @config.builder()
    |> @config.working_dir("/w")
    |> @config.format(@toml.format())
    |> @config.format(yaml_stub())
    |> @config.add(
      @config.ConfigSource::candidates(["app.toml", "app.yaml"], display="App"),
    )
    |> @config.load(
      complete()
      .with_listing("/w", listing(["app.yaml", "README.md"]))
      .with_file("/w/app.yaml", "a: 1"),
    )
    |> done
  let report = config.reports()[0]
  @expect.expect((report.path, report.candidates, report.status)).to_equal((
    Some("/w/app.yaml"),
    ["/w/app.toml", "/w/app.yaml"],
    Loaded,
  ))
  @expect.expect(@config.get_text(config, "format")).to_equal("yaml")
}

///|
test "No candidate exists" {
  let config = @config.builder()
    |> @config.format(@toml.format())
    |> @config.add(
      @config.ConfigSource::candidates(["/w/app.toml"], display="App"),
    )
    |> @config.load(complete().with_listing("/w", []))
    |> done
  @expect.expect(config.value()).to_equal(@config.fields([]))
  @expect.expect(statuses(config)).to_equal([NotFound])
}

///|
test "Name match is exact" {
  let config = @config.builder()
    |> @config.format(@toml.format())
    |> @config.add(
      @config.ConfigSource::candidates(["/w/app.toml"], display="App"),
    )
    |> @config.load(complete().with_listing("/w", listing(["App.toml"])))
    |> done
  @expect.expect(statuses(config)).to_equal([NotFound])
}

///|
test "a directory with a candidate name does not exist as a file" {
  let tree = complete().with_listing("/w", [
    { name: "app.toml", kind: Directory },
  ])
  @expect.expect(tree.is_file("/w/app.toml")).to_equal(Found(false))
}

///|
test "ambiguity names the common directory of the candidates" {
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.add(
      @config.ConfigSource::candidates(
        ["/w/app.toml", "/w/.config/app.toml"],
        display="App",
      ),
    )
  let tree = @config.FileTree::new()
    .with_listing("/w", listing(["app.toml"]))
    .with_listing("/w/.config", listing(["app.toml"]))
  let error = load_error(() => {
    @config.load(builder, tree) |> ignore
  })
  @expect.expect(error).to_equal(
    Ambiguous(
      display="App",
      location="/w",
      candidates=["/w/app.toml", "/w/.config/app.toml"],
    ),
  )
}

///|
test "Inherited layer drops project identity" {
  let config = @config.builder()
    |> @config.format(@toml.format())
    |> @config.add(
      @config.ConfigSource::file("/w/app.toml").exclude(
        [key("project"), key("workspace")],
        warn=false,
      ),
    )
    |> @config.load(
      complete().with_file(
        "/w/app.toml",
        (
          #|ir.layout = "tree"
          #|project.name = "A"
        ),
      ),
    )
    |> done
  @expect.expect(@config.get_text(config, "ir.layout")).to_equal("tree")
  @expect.expect(config.get(key("project"))).to_equal(None)
  @expect.expect(config.warnings()).to_equal([])
}

///|
test "Member layer removal warns" {
  let config = @config.builder()
    |> @config.format(@toml.format())
    |> @config.add(@config.in_memory_pairs([("workspace.out_dir", @config.string("base"))]))
    |> @config.add(
      @config.ConfigSource::file("/w/m/app.toml", role=Member).exclude(
        [key("workspace.out_dir")],
        warn=true,
      ),
    )
    |> @config.load(
      complete().with_file(
        "/w/m/app.toml",
        (
          #|workspace.out_dir = "out"
          #|workspace.name = "m"
        ),
      ),
    )
    |> done
  @expect.expect(@config.get_text(config, "workspace.out_dir")).to_equal("base")
  @expect.expect(@config.get_text(config, "workspace.name")).to_equal("m")
  @expect.expect(config.reports()[1].warnings).to_equal([
    KeyRemoved(key("workspace.out_dir"), {
      kind: File(Member),
      source: "/w/m/app.toml",
      priority: 350,
      location: Some("/w/m/app.toml"),
    }),
  ])
}

///|
test "Absent key gives no warning" {
  let config = @config.build([
    @config.in_memory_pairs([("ir.layout", @config.string("tree"))]).exclude(
      [key("workspace.out_dir"), key("ir.layout.deep")],
      warn=true,
    ),
  ])
  @expect.expect(config.warnings()).to_equal([])
  @expect.expect(@config.get_text(config, "ir.layout")).to_equal("tree")
}

///|
test "a registered format does not change when the caller changes its extensions" {
  let extensions = ["toml"]
  let toml = @config.Format::{ ..@toml.format(), extensions, }
  let builder = @config.builder() |> @config.format(toml)
  extensions.push("ini")
  builder.formats()[0].extensions.push("cfg")
  @expect.expect(builder.formats()[0].extensions).to_equal(["toml"])
}

///|
test "a report does not change when the caller changes its arrays" {
  let config = @config.build([
    @config.in_memory_pairs([("a", @config.int(1))]).exclude(
      [key("a")],
      warn=true,
    ),
  ])
  config.reports()[0].warnings.clear()
  config.reports()[0].candidates.push("/x")
  @expect.expect(config.reports()[0].warnings.length()).to_equal(1)
  @expect.expect(config.reports()[0].candidates).to_equal([])
}

///|
test "a candidate named twice is one candidate" {
  let config = @config.builder()
    |> @config.working_dir("/w")
    |> @config.format(@toml.format())
    |> @config.add(
      @config.ConfigSource::candidates(
        ["app.toml", "/w/app.toml", "app.toml"],
        display="App",
      ),
    )
    |> @config.load(
      complete()
      .with_listing("/w", listing(["app.toml"]))
      .with_file("/w/app.toml", "a = 1"),
    )
    |> done
  let report = config.reports()[0]
  @expect.expect((report.status, report.candidates)).to_equal((
    Loaded,
    ["/w/app.toml"],
  ))
}

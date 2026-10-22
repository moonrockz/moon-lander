///|
/// A complete tree that holds `files` (path and text) and the listing of every
/// directory above them, down from `/`.
fn disk(files : Array[(String, String)]) -> @config.FileTree {
  let listings : Map[String, Array[@config.DirEntry]] = Map([])
  let add_entry = (dir : String, entry : @config.DirEntry) => {
    let entries = listings.get(dir).unwrap_or([])
    if !entries.contains(entry) {
      entries.push(entry)
    }
    listings[dir] = entries
  }
  let mut tree = @config.FileTree::new(complete=true)
  for file in files {
    let (path, text) = file
    tree = tree.with_file(path, text)
    let parts = path[1:].split("/").map(part => part.to_owned()).collect()
    let mut dir = "/"
    for index, part in parts {
      let kind : @config.EntryKind = if index == parts.length() - 1 {
        File
      } else {
        Directory
      }
      add_entry(dir, { name: part, kind })
      dir = if dir == "/" { "/\{part}" } else { "\{dir}/\{part}" }
    }
  }
  for dir, entries in listings {
    tree = tree.with_listing(dir, entries)
  }
  tree
}

///|
/// A YAML stand-in limited to `.yaml`.
fn yaml_only() -> @config.Format {
  { ..yaml_stub(), extensions: ["yaml"] }
}

///|
fn discover_in(
  start : String,
  files : Array[(String, String)],
  conventions? : @conventions.Conventions = @conventions.app_dirs("acme"),
  formats? : Array[@config.Format] = [@toml.format()],
  options? : @conventions.DiscoveryOptions = @conventions.DiscoveryOptions::new(),
  platform? : @config.Platform,
  env_vars? : Map[String, String],
) -> @config.Config raise @config.ConfigError {
  let mut builder = formats.fold(
    init=@config.builder() |> @config.working_dir(start),
    (builder, format) => builder |> @config.format(format),
  )
  if platform is Some(platform) {
    builder = builder |> @config.platform(platform)
  }
  if env_vars is Some(vars) {
    builder = builder |> @config.env_vars(vars)
  }
  builder
  |> @conventions.add(conventions, options~)
  |> @config.load(disk(files))
  |> done
}

///|
fn ambiguity(run : () -> Unit raise @config.ConfigError) -> (String, Array[String]) {
  try run() catch {
    Ambiguous(location~, candidates~, ..) => (location, candidates)
    error => abort("expected an ambiguity error, got \{error.message()}")
  } noraise {
    _ => abort("expected an ambiguity error")
  }
}

///|
fn primary_path(config : @config.Config) -> String? {
  project(config).path
}

///|
test "Root layout found" {
  let config = discover_in("/w", [("/w/acme.toml", "a = 1")])
  @expect.expect(primary_path(config)).to_equal(Some("/w/acme.toml"))
}

///|
test "Dot-config layout found" {
  let config = discover_in("/w", [("/w/.config/acme/config.toml", "a = 1")])
  @expect.expect(primary_path(config)).to_equal(
    Some("/w/.config/acme/config.toml"),
  )
}

///|
test "Hidden directory layout found" {
  let config = discover_in("/w", [("/w/.acme/acme.yaml", "a: 1")], formats=[
    yaml_stub(),
  ])
  @expect.expect(primary_path(config)).to_equal(Some("/w/.acme/acme.yaml"))
}

///|
test "Unregistered extension ignored" {
  let config = discover_in("/w", [("/w/acme.json", "{}")], formats=[
    @toml.format(),
    yaml_only(),
  ])
  @expect.expect(project(config).status).to_equal(NotFound)
  @expect.expect(project(config).candidates.length()).to_equal(6)
}

///|
test "Registration order does not choose" {
  let (_, candidates) = ambiguity(() => {
    discover_in("/w", [("/w/acme.toml", ""), ("/w/acme.yaml", "")], formats=[
      @toml.format(),
      yaml_only(),
    ])
    |> ignore
  })
  @expect.expect(candidates).to_equal(["/w/acme.toml", "/w/acme.yaml"])
}

///|
test "Two serializations of one layout" {
  let (location, candidates) = ambiguity(() => {
    discover_in("/w", [("/w/acme.toml", ""), ("/w/acme.yaml", "")], formats=[
      @toml.format(),
      yaml_stub(),
    ])
    |> ignore
  })
  @expect.expect((location, candidates)).to_equal((
    "/w",
    ["/w/acme.toml", "/w/acme.yaml"],
  ))
}

///|
test "Primaries in two layouts" {
  let (location, candidates) = ambiguity(() => {
    discover_in("/w", [("/w/acme.toml", ""), ("/w/.acme/acme.toml", "")])
    |> ignore
  })
  @expect.expect((location, candidates)).to_equal((
    "/w",
    ["/w/acme.toml", "/w/.acme/acme.toml"],
  ))
}

///|
test "Ambiguity in the nearest directory stops discovery" {
  let (location, _) = ambiguity(() => {
    discover_in(
      "/w/sub",
      [("/w/acme.toml", ""), ("/w/sub/acme.toml", ""), ("/w/sub/acme.yaml", "")],
      formats=[@toml.format(), yaml_stub()],
    )
    |> ignore
  })
  @expect.expect(location).to_equal("/w/sub")
}

///|
/// A legacy format that keeps the text, and a decoder that puts it below
/// `legacy`.
fn with_legacy() -> @conventions.Conventions {
  @conventions.app_dirs("acme")
  |> @conventions.legacy(
    "acme.json",
    format={
      name: "Legacy JSON",
      extensions: ["json"],
      parse: (text, _) => @config.fields([("text", @config.string(text))]),
    },
    decode=value => @config.fields([("legacy", value)]),
  )
}

///|
test "Legacy file used when no primary exists" {
  let config = discover_in("/w/src", [("/w/acme.json", "{}")], conventions=with_legacy())
  let report = project(config)
  @expect.expect((report.kind, report.path, report.status)).to_equal((
    File(Legacy),
    Some("/w/acme.json"),
    Loaded,
  ))
  @expect.expect(@config.get_text(config, "legacy.text")).to_equal("{}")
  @expect.expect(
    config.origins(@config.KeyPath::parse("legacy.text"))[0].location,
  ).to_equal(Some("/w/acme.json"))
}

///|
test "Primary wins over legacy file" {
  let config = discover_in(
    "/w",
    [("/w/acme.json", "{}"), ("/w/acme.toml", "a = 1")],
    conventions=with_legacy(),
  )
  @expect.expect(primary_path(config)).to_equal(Some("/w/acme.toml"))
  @expect.expect(config.get(@config.KeyPath::parse("legacy"))).to_equal(None)
}

///|
test "the legacy format adds no searched extension" {
  let config = discover_in("/w", [("/w/main.mbt", "")], conventions=with_legacy())
  @expect.expect(project(config).candidates).to_equal([
    "/w/acme.toml", "/w/.acme/acme.toml", "/w/.config/acme/config.toml",
  ])
}

///|
test "Ancestor configuration above the boundary is ignored" {
  let config = discover_in(
    "/tmp/case/src",
    [("/tmp/acme.toml", "a = 1"), ("/tmp/case/src/main.mbt", "")],
    conventions=@conventions.app_dirs("acme") |> @conventions.boundary("/tmp/case"),
  )
  @expect.expect(project(config).status).to_equal(NotFound)
}

///|
test "Configuration at the boundary is found" {
  let config = discover_in(
    "/tmp/case/src",
    [("/tmp/case/acme.toml", "a = 1"), ("/tmp/case/src/main.mbt", "")],
    conventions=@conventions.app_dirs("acme") |> @conventions.boundary("/tmp/case/"),
  )
  @expect.expect(primary_path(config)).to_equal(Some("/tmp/case/acme.toml"))
}

///|
test "Start directory outside the boundary" {
  try
    discover_in(
      "/srv/other",
      [],
      conventions=@conventions.app_dirs("acme") |> @conventions.boundary("/tmp/case"),
    )
  catch {
    error =>
      @expect.expect(error).to_equal(
        OutsideBoundary(start="/srv/other", boundary="/tmp/case"),
      )
  } noraise {
    _ => fail("expected an outside-boundary error")
  }
}

///|
test "a relative boundary joins the working directory" {
  let config = discover_in(
    "/w/a/b",
    [("/w/acme.toml", "a = 1"), ("/w/a/acme.toml", "a = 2"), ("/w/a/b/x", "")],
    conventions=@conventions.app_dirs("acme") |> @conventions.boundary("."),
  )
  @expect.expect(project(config).status).to_equal(NotFound)
}

///|
test "Isolated mode keeps environment variables" {
  let builder = @config.builder()
    |> @config.working_dir("/w")
    |> @config.format(@toml.format())
    |> @conventions.add(
      @conventions.app_dirs("acme"),
      options=@conventions.DiscoveryOptions::new(isolated=true),
    )
    |> @config.env(prefix="ACME", selection=Explicit({ "ACME_IR__FORMAT_VERSION": "4" }))
  let config = builder
    |> @config.load(disk([("/w/acme.toml", "ir.format_version = 3")]))
    |> done
  @expect.expect(@config.get_text(config, "ir.format_version")).to_equal("4")
}

///|
test "Isolated mode keeps the project primary and loads no override file" {
  let config = discover_in(
    "/w",
    [
      ("/w/acme.toml", "a = 1"),
      ("/w/acme.local.toml", "b = 1"),
      ("/w/acme.user.toml", "c = 1"),
    ],
    options=@conventions.DiscoveryOptions::new(isolated=true),
  )
  @expect.expect(config.value()).to_equal(
    @config.fields([("a", @config.int(1))]),
  )
}

///|
test "an option that the convention set does not use adds a note" {
  let config = discover_in(
    "/w",
    [("/w/acme.toml", "a = 1")],
    options=@conventions.DiscoveryOptions::new(
      environment="Staging",
      project="api",
    ),
  )
  @expect.expect(
    config
    .warnings()
    .map(warning => {
      guard warning is Note(message~, ..) else { "" }
      message
    }),
  ).to_equal([
    "environments are off, so discovery ignores the environment option", "the convention set has no workspace part, so discovery ignores the project option",
    no_platform,
  ])
}

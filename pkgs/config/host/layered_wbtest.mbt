///|
fn layered_conventions() -> @conventions.Conventions raise @config.ConfigError {
  let json = @conventions.Extension::parse("json")
  @conventions.app_dirs("acme")
  |> @conventions.workspace
  |> @conventions.root_policy(WorkspaceFirst(@config.KeyPath::parse("workspace")))
  |> @conventions.format_layers(@conventions.FormatLayers::new([
    @conventions.FormatGroup::new([json, @conventions.Extension::parse("json5")],
      supplemental=@conventions.SupplementalFile::new("acme-workspace.json", json,
        transform=value => @config.fields([("workspace", value)]))),
    @conventions.FormatGroup::new(["yaml", "yml"].map(@conventions.Extension::parse)),
    @conventions.FormatGroup::new([@conventions.Extension::parse("toml")]),
  ]))
  |> @conventions.selected_file_policy(Overlay)
  |> @conventions.profiles(@profiles.Policy::new())
}

///|
fn layered_host_builder(start : String, conventions : @conventions.Conventions, options : @conventions.DiscoveryOptions) -> @config.ConfigBuilder {
  @config.builder() |> @config.working_dir(start) |> @config.env_vars({})
  |> @config.format(@toml.format()) |> @config.format(@yaml.format()) |> @config.format(@json5.format())
  |> @conventions.add(conventions, options~)
}

///|
// On js answer is synchronous; native needs the async callback type.
#warnings("-67")
async test "disk adapters compose layered member workspace profiles and selected overlays" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/acme.toml", "malformed ancestor [")
  let root = "\{dir}/w"
  write("\{root}/acme-workspace.json", "{members:['a']}")
  write("\{root}/acme.json5", "{profiles:{active:['metrics']},shared:'json',jsonOnly:true}")
  write("\{root}/acme.toml", "shared='toml'\ntomlOnly=true")
  write("\{root}/a/acme.yml", "project:\n  name: a\nshared: member")
  write("\{root}/a/src/main.mbt", "")
  write("\{root}/acme.profile.metrics.json", "{profileValue:'json'}")
  write("\{root}/acme.profile.metrics.toml", "profileValue='toml'")
  write("\{root}/a/acme.profile.metrics.yaml", "profileValue: member")
  write("\{root}/acme.user.toml", "malformed isolated override [")
  let builder = layered_host_builder("\{root}/a/src", layered_conventions() |> @conventions.boundary(dir),
    @conventions.DiscoveryOptions::new(config=Explicit("../.././acme.json5"), isolated=true))
  let seen = []
  let config = load_by(builder, async fn(tree, request, platform) {
    seen.push(request)
    answer(tree, request, platform)
  })
  assert_eq(@config.get_text(config, "shared"), "member")
  assert_eq(@config.get_text(config, "profileValue"), "member")
  assert_eq(@config.bind(config, "jsonOnly"), true)
  assert_eq(@config.bind(config, "tomlOnly"), true)
  assert_eq(config.origins(@config.KeyPath::parse("shared"))[0].location, Some("\{root}/a/acme.yml"))
  assert_eq(config.origins(@config.KeyPath::parse("profileValue"))[0].priority, 380)
  assert_eq(config.reports().filter(report => report.path == Some("\{root}/acme.json5")).map(report => report.priority), [325])
  assert_true(seen.all(request => match request {
    ListDir(path) | ReadFile(path) => path.is_within(@config.FileTreePath::parse(root))
  }))
}

///|
// On js answer is synchronous; native needs the async callback type.
#warnings("-67")
async test "disk adapters stop layered discovery at an isolated boundary without a root" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/acme.toml", "malformed ancestor [")
  let root = "\{dir}/w"
  write("\{root}/a/src/main.mbt", "")
  let seen = []
  let config = load_by(layered_host_builder("\{root}/a/src", layered_conventions() |> @conventions.boundary(root),
    @conventions.DiscoveryOptions::new(isolated=true)), async fn(tree, request, platform) {
    seen.push(request)
    answer(tree, request, platform)
  })
  assert_true(config.reports().all(report => report.status != Loaded))
  assert_true(seen.all(request => match request {
    ListDir(path) | ReadFile(path) => path.is_within(@config.FileTreePath::parse(root))
  }))
}

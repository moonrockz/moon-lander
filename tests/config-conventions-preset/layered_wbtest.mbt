///|
fn layered_builder(conventions : @conventions.Conventions, options : @conventions.DiscoveryOptions) -> @config.ConfigBuilder {
  layered_formats().fold(init=@config.builder() |> @config.working_dir("/case/w/packages/a/src") |> @config.env_vars({}) |> @config.platform(Linux),
    (builder, format) => builder |> @config.format(format)) |> @conventions.add(conventions, options~)
}

///|
fn answer_complete(tree : @config.FileTree, complete : @config.FileTree, requests : Array[@config.FileRequest], seen : Array[@config.FileRequest]) -> @config.FileTree raise {
  let mut tree = tree
  for request in requests {
    seen.push(request)
    match request {
      ListDir(path) => match complete.listing(path) {
        Found(entries) => tree = tree.with_listing(path, entries)
        Missing => tree = tree.with_missing(path)
        Unknown => fail("complete fixture has an unknown listing")
      }
      ReadFile(path) => match complete.file(path) {
        Found(text) => tree = tree.with_file(path, text)
        Missing => tree = tree.with_missing(path)
        Unknown => fail("complete fixture has an unknown file")
      }
    }
  }
  tree
}

///|
fn incremental_load(builder : @config.ConfigBuilder, complete : @config.FileTree, seen : Array[@config.FileRequest]) -> @config.Config raise {
  let mut tree = @config.FileTree::new()
  for _ in 0..<100 {
    match @config.load(builder, tree) {
      Done(config) => return config
      Need(requests) => tree = answer_complete(tree, complete, requests, seen)
    }
  }
  fail("incremental load did not complete")
}

///|
test "Morphir supplemental-only workspace uses standard profile names" {
  let complete = tree([
    ("w/morphir-workspace.json", "{members:[]}"),
    ("w/morphir.profile.metrics.toml", "enabled=true"),
    ("w/morphir-workspace.profile.metrics.json", "invalid JSON"),
  ])
  let options = @conventions.DiscoveryOptions::new(isolated=true, profiles=Selected(@config.ProfileNames::new([@config.ProfileName::parse("metrics")])))
  guard @config.load(layered_builder(layered_morphir(), options), complete) is Done(config) else { fail("complete tree requested I/O") }
  assert_eq(@config.bind(config, "enabled"), true)
  assert_eq(config.origins(@config.KeyPath::parse("enabled"))[0].location, Some("/case/w/morphir.profile.metrics.toml"))
}

///|
test "Morphir layered public preset retains roots profiles overlays and origins" {
  let complete = tree([
    ("morphir.toml", "malformed ancestor ["),
    ("w/morphir-workspace.json", "{members:['packages/a'], out_dir:'root-output'}"),
    ("w/morphir.json5", "{profiles:{default:['env']}, shared:'json', jsonOnly:true}"),
    ("w/morphir.yml", "profiles:\n  include: [common]\nshared: yaml\nyamlOnly: true"),
    ("w/morphir.toml", "profiles.groups.env=['metrics']\nshared='toml'\ntomlOnly=true"),
    ("w/packages/a/morphir.json", "{project:{name:'a'}}"),
    ("w/morphir.profile.common.toml", "profileOrder='common'"),
    ("w/morphir.profile.metrics.json", "{profileOrder:'metrics-json'}"),
    ("w/morphir.profile.metrics.yaml", "profileOrder: metrics-yaml"),
    ("w/morphir.profile.metrics.toml", "profileOrder='metrics-toml'"),
    ("w/packages/a/morphir.profile.metrics.toml", "memberProfile=true"),
  ])
  let conventions = layered_morphir()
  let options = @conventions.DiscoveryOptions::new(config=Explicit("../../../morphir.json5"), isolated=true)
  let builder = layered_builder(conventions, options)
  guard @config.load(builder, complete) is Done(config) else { fail("complete tree requested I/O") }
  let seen = []
  let incremental = incremental_load(builder, complete, seen)
  assert_eq(config.value(), incremental.value())
  assert_eq(config.reports(), incremental.reports())
  assert_eq(config.profiles(), incremental.profiles())
  assert_eq(@config.get_text(config, "shared"), "json")
  for key in ["jsonOnly", "yamlOnly", "tomlOnly"] { assert_eq(@config.bind(config, key), true) }
  assert_eq(@config.get_text(config, "profileOrder"), "metrics-toml")
  assert_true(config.reports().all(report => !(report.kind is File(Member))))
  let origin = config.origins(@config.KeyPath::parse("shared"))[0]
  assert_eq(origin.location, Some("/case/w/morphir.json5"))
  assert_eq(origin.priority, 325)
  assert_eq(config.origins(@config.KeyPath::parse("tomlOnly")), incremental.origins(@config.KeyPath::parse("tomlOnly")))
  guard config.profiles() is Resolved(resolution) else { fail("profiles were not enabled") }
  assert_eq(resolution.active().names().map(name => name.to_string()), ["common", "env", "metrics"])
  for (key, path) in [("profiles.default", "/case/w/morphir.json5"), ("profiles.include", "/case/w/morphir.yml"), ("profiles.groups.env", "/case/w/morphir.toml")] {
    assert_true(resolution.controls().any(control => match control { Control(source, control) => control.to_string() == key && source.location == Some(path); _ => false }))
  }
  let context : @config.LoadContext = { tree: complete, working_dir: Some(fixture_path("/case/w/packages/a/src")), platform: Some(Linux), env_vars: Map([]), formats: layered_formats() }
  guard conventions.roots(context, options~) is Done(roots) else { fail("complete roots requested I/O") }
  assert_eq(roots.workspace(), Some(fixture_path("/case/w")))
  assert_eq(roots.nearest_project(), Some(fixture_path("/case/w/packages/a")))
  assert_eq(roots.sources().length(), 4)
  let mut partial = @config.FileTree::new()
  let mut evidence = None
  for _ in 0..<100 {
    match conventions.roots({ ..context, tree: partial }, options~) {
      Done(roots) => { evidence = Some(roots); break }
      Need(requests) => partial = answer_complete(partial, complete, requests, seen)
    }
  }
  guard evidence is Some(incremental_roots) else { fail("partial roots did not finish") }
  assert_eq(incremental_roots.workspace(), roots.workspace())
  assert_eq(incremental_roots.nearest_project(), roots.nearest_project())
  assert_true(seen.all(request => match request {
    ListDir(path) | ReadFile(path) => path.is_within(fixture_path("/case/w"))
  }))
  let chosen = layered_builder(conventions, { ..options, project: Some("packages/a") }) |> @config.load(complete)
  guard chosen is Done(chosen) else { fail("complete member requested I/O") }
  assert_eq(@config.get_text(chosen, "project.name"), "a")
  assert_eq(@config.bind(chosen, "memberProfile"), true)
}

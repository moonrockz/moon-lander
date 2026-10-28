///|
fn ordered_conventions(supplemental? : @conventions.SupplementalFile) -> @conventions.Conventions raise @config.ConfigError {
  let groups = @conventions.FormatLayers::new([
    @conventions.FormatGroup::new(["json", "json5"].map(@conventions.Extension::parse), supplemental?),
    @conventions.FormatGroup::new(["yaml", "yml"].map(@conventions.Extension::parse)),
    @conventions.FormatGroup::new([@conventions.Extension::parse("toml")]),
  ])
  workspace_first() |> @conventions.format_layers(groups)
}

///|
fn ordered_formats() -> Array[@config.Format] { [@json5.format(), @yaml.format(), @toml.format()] }

///|
test "nearest-file ordered discovery passes over an ambiguous enclosing candidate" {
  let config = discover_in("/w/mid/a", [
    ("/w/acme.toml", "workspace.members=['mid/a']\nshared='workspace'"),
    ("/w/mid/acme.json", "{}"),
    ("/w/mid/acme.json5", "{}"),
    ("/w/mid/a/acme.toml", "project.name='a'"),
  ], conventions=ordered_conventions() |> @conventions.root_policy(NearestFile), formats=ordered_formats())
  assert_eq(@config.get_text(config, "shared"), "workspace")
  assert_eq(@config.get_text(config, "project.name"), "a")
  assert_eq(config.reports().filter(report => report.kind is File(Workspace) && report.status is Loaded).map(report => report.path), [Some("/w/acme.toml")])
}

///|
test "ordered formats merge at one root independent of parser registration order" {
  let files = [
    ("/w/acme.json5", "{ shared: 'json', jsonOnly: true, workspace: {} }"),
    ("/w/acme.yaml", "shared: yaml\nyamlOnly: true"),
    ("/w/acme.toml", "shared='toml'\ntomlOnly=true"),
  ]
  for formats in [ordered_formats(), ordered_formats().rev()] {
    let config = discover_in("/w", files, conventions=ordered_conventions(), formats~)
    assert_eq(@config.get_text(config, "shared"), "toml")
    assert_eq(@config.bind(config, "jsonOnly"), true)
    assert_eq(@config.bind(config, "yamlOnly"), true)
    assert_eq(@config.bind(config, "tomlOnly"), true)
    let loaded = config.reports().filter(report => report.status is Loaded)
    assert_eq(loaded.map(report => report.path), [Some("/w/acme.json5"), Some("/w/acme.yaml"), Some("/w/acme.toml")])
    assert_eq(config.origins(@config.KeyPath::parse("shared"))[0].location, Some("/w/acme.toml"))
  }
}

///|
test "supplemental JSON transforms once below ordinary JSON and keeps its origin" {
  let calls = Ref(0)
  let supplemental = @conventions.SupplementalFile::new("acme-workspace.json", @conventions.Extension::parse("json"), transform=value => {
    calls.val += 1
    @config.fields([("workspace", value)])
  })
  let conventions = ordered_conventions(supplemental~) |> @conventions.member_loading(ExplicitOnly)
  let config = discover_in("/w/a", [
    ("/w/acme-workspace.json", "{members:['a'], outDir:'supplemental'}"),
    ("/w/acme.json5", "{workspace:{outDir:'ordinary'}}"),
    ("/w/acme.toml", "tomlOnly=true"),
  ], conventions~, formats=ordered_formats())
  assert_eq(calls.val, 1)
  assert_eq(@config.get_text(config, "workspace.outDir"), "ordinary")
  assert_eq(config.origins(@config.KeyPath::parse("workspace.members"))[0].location, Some("/w/acme-workspace.json"))
  assert_eq(config.reports().filter(report => report.status is Loaded).map(report => report.path), [Some("/w/acme-workspace.json"), Some("/w/acme.json5"), Some("/w/acme.toml")])
}

///|
test "ordered groups retain same-group and layout ambiguity with supplements" {
  let supplemental = @conventions.SupplementalFile::new("acme-workspace.json", @conventions.Extension::parse("json"))
  for files in [
    [("/w/acme.json", "{}"), ("/w/acme.json5", "{}"), ("/w/acme-workspace.json", "{}")],
    [("/w/acme.yaml", "a: 1"), ("/w/acme.yml", "a: 2")],
    [("/w/acme.toml", "a=1"), ("/w/.acme/acme.toml", "a=2")],
  ] {
    let (_, paths) = ambiguity(() => ignore(discover_in("/w", files, conventions=ordered_conventions(supplemental~), formats=ordered_formats())))
    assert_eq(paths.length(), 2)
    assert_false(paths.contains("/w/acme-workspace.json"))
  }
}

///|
test "root evidence exposes each parsed format layer" {
  let tree = disk([("/w/acme.json", "{workspace:{}, a:1}"), ("/w/acme.toml", "b=2")])
  let context : @config.LoadContext = { tree, working_dir: Some(p("/w")), platform: Some(Linux), env_vars: Map([]), formats: ordered_formats() }
  guard ordered_conventions().roots(context) is Done(evidence) else { fail("complete tree requested I/O") }
  assert_eq(evidence.workspace(), Some(p("/w")))
  assert_eq(evidence.sources().length(), 2)
  let config = @config.build(evidence.sources())
  assert_eq(@config.bind(config, "a"), 1)
  assert_eq(@config.bind(config, "b"), 2)
}

///|
test "ordered machine and global stages retain priorities and common-root values" {
  let config = discover_in("/w", [
    ("/etc/acme/acme.yaml", "shared: system-yaml\nsystemOnly: true"),
    ("/etc/acme/acme.toml", "shared='system-toml'"),
    ("/home/u/.config/acme/acme.yaml", "shared: global-yaml"),
    ("/home/u/.config/acme/acme.toml", "shared='global-toml'"),
    ("/w/acme.toml", "[workspace]"),
  ], conventions=ordered_conventions(), formats=ordered_formats(), platform=Linux, env_vars={ "HOME": "/home/u" })
  assert_eq(@config.get_text(config, "shared"), "global-toml")
  assert_eq(@config.bind(config, "systemOnly"), true)
  assert_eq(config.reports().filter(report => report.status is Loaded).map(report => (report.kind, report.priority, report.path)), [
    (File(System), 100, Some("/etc/acme/acme.yaml")), (File(System), 100, Some("/etc/acme/acme.toml")),
    (File(Global), 200, Some("/home/u/.config/acme/acme.yaml")), (File(Global), 200, Some("/home/u/.config/acme/acme.toml")),
    (File(Workspace), 300, Some("/w/acme.toml")),
  ])
}

///|
test "environment local and user stages use format order without changing priority" {
  let conventions = ordered_conventions() |> @conventions.environments(default="Prod")
  let config = discover_in("/w", [
    ("/w/acme.json", "{workspace:{}, shared:'base-json'}"),
    ("/w/acme.toml", "shared='base-toml'"),
    ("/w/acme.Prod.yaml", "shared: env-yaml"), ("/w/acme.Prod.toml", "shared='env-toml'"),
    ("/w/acme.local.yaml", "shared: local-yaml"), ("/w/acme.local.toml", "shared='local-toml'"),
    ("/w/acme.user.yaml", "shared: user-yaml"), ("/w/acme.user.toml", "shared='user-toml'"),
  ], conventions~, formats=ordered_formats())
  assert_eq(@config.get_text(config, "shared"), "user-toml")
  assert_eq(config.reports().filter(report => report.status is Loaded).map(report => (report.kind, report.priority)), [
    (File(Workspace), 300), (File(Workspace), 300),
    (File(EnvironmentFile), 375), (File(EnvironmentFile), 375),
    (File(LocalOverride), 390), (File(LocalOverride), 390),
    (File(UserOverride), 400), (File(UserOverride), 400),
  ])
}

///|
test "a member lower format overrides all workspace primaries at the member stage" {
  let config = discover_in("/w/a/src", [
    ("/w/acme.json", "{workspace:{members:['a']}, shared:'workspace-json'}"),
    ("/w/acme.toml", "shared='workspace-toml'\nworkspaceOnly=true"),
    ("/w/a/acme.json", "{project:{name:'a'}, shared:'member-json'}"),
  ], conventions=ordered_conventions(), formats=ordered_formats())
  assert_eq(@config.get_text(config, "shared"), "member-json")
  assert_eq(@config.bind(config, "workspaceOnly"), true)
  let origin = config.origins(@config.KeyPath::parse("shared"))[0]
  assert_true(origin.kind is File(Member))
  assert_eq(origin.priority, 350)
  assert_eq(origin.location, Some("/w/a/acme.json"))
}

///|
test "merged formats select the nearest workspace before any ancestor" {
  let config = discover_in("/w/inner/a", [
    ("/w/acme.json", "not valid JSON"),
    ("/w/inner/acme.json", "{workspace:{}}"),
    ("/w/inner/acme.toml", "workspace.outDir='build'"),
    ("/w/inner/a/acme.toml", "project.name='a'"),
  ], conventions=ordered_conventions(), formats=ordered_formats())
  assert_eq(primary_path(config), Some("/w/inner/acme.json"))
  assert_eq(@config.get_text(config, "workspace.outDir"), "build")
  assert_eq(member_report(config), None)
}

///|
test "ordered root controls and profiles agree with an incremental file tree" {
  let entries = [
    ("/w/acme.json", "{workspace:{members:['a']}, profiles:{active:['metrics']}}"),
    ("/w/acme.toml", "workspace.outDir='build'"),
    ("/w/a/acme.yaml", "project:\n  name: a"),
    ("/w/acme.profile.metrics.json", "{profileValue:'workspace'}"),
    ("/w/a/acme.profile.metrics.toml", "profileValue='member'"),
  ]
  let conventions = ordered_conventions() |> @conventions.profiles(@profiles.Policy::new())
  let builder = ordered_formats().fold(init=@config.builder() |> @config.working_dir("/w/a/src"), (builder, format) => builder |> @config.format(format)) |> @conventions.add(conventions)
  let complete = @config.load(builder, disk(entries)) |> done
  let partial = load_from(builder, Map::from_array(entries))
  assert_eq(complete.value(), partial.value())
  assert_eq(report_rows(complete), report_rows(partial))
  assert_eq(complete.profiles(), partial.profiles())
  assert_eq(@config.get_text(partial, "profileValue"), "member")
}

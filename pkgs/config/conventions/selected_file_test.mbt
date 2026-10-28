///|
fn overlay_conventions() -> @conventions.Conventions raise @config.ConfigError {
  ordered_conventions() |> @conventions.selected_file_policy(Overlay)
}

///|
test "selected member adjacent and supplemental identities retain member-scope filters" {
  let supplemental = @conventions.SupplementalFile::new("acme-workspace.json", @conventions.Extension::parse("json"))
  let conventions = ordered_conventions(supplemental~)
    |> @conventions.selected_file_policy(Overlay)
    |> @conventions.member_scope_keys(["workspace.out_dir"])
    |> @conventions.inherited_filter(["project"])
    |> @conventions.environments(default="Prod")
    |> @conventions.profiles(@profiles.Policy::new())
  let entries = [
    ("/w/acme.json", "{workspace:{members:['a'],out_dir:'root'},profiles:{active:['metrics']}}"),
    ("/w/a/acme.toml", "project.name='a'"),
    ("/w/a/acme-workspace.json", "{workspace:{out_dir:'member-supplemental'}}"),
    ("/w/a/acme.Prod.toml", "workspace.out_dir='member-env'"),
    ("/w/a/acme.local.toml", "workspace.out_dir='member-local'"),
    ("/w/a/acme.user.toml", "workspace.out_dir='member-user'"),
    ("/w/a/acme.profile.metrics.toml", "workspace.out_dir='member-profile'"),
  ]
  for file in ["acme-workspace.json", "acme.Prod.toml", "acme.local.toml", "acme.user.toml", "acme.profile.metrics.toml"] {
    let config = discover_in("/w", entries, conventions~, formats=ordered_formats(), options=@conventions.DiscoveryOptions::new(config=Explicit("a/./" + file), project="a"))
    assert_eq(@config.get_text(config, "workspace.out_dir"), "root")
    let selected = config.reports().filter(report => report.path == Some("/w/a/" + file))
    assert_eq(selected.length(), 1)
    assert_eq(selected[0].priority, 325)
    assert_true(selected[0].warnings.any(warning => match warning {
      KeyRemoved(key, _) => key.to_string() == "workspace.out_dir"
      _ => false
    }))
  }
}

///|
test "selected JSON moves above TOML once and member primaries remain higher" {
  let files = [
    ("/w/acme.json", "{workspace:{members:['a']}, shared:'json', jsonOnly:true}"),
    ("/w/acme.toml", "shared='toml'\ntomlOnly=true"),
    ("/w/a/acme.toml", "shared='member'"),
  ]
  let conventions = overlay_conventions() |> @conventions.member_loading(ExplicitOnly)
  for path in ["acme.json", "./acme.json", "a/../acme.json", "/w/./acme.json"] {
    let config = discover_in("/w", files, conventions~, formats=ordered_formats(), options=@conventions.DiscoveryOptions::new(config=Explicit(path)))
    assert_eq(@config.get_text(config, "shared"), "json")
    assert_eq(@config.bind(config, "tomlOnly"), true)
    let loaded = config.reports().filter(report => report.status is Loaded)
    assert_eq(loaded.map(report => (report.path, report.priority)), [(Some("/w/acme.toml"), 300), (Some("/w/acme.json"), 325)])
    assert_true(config.origins(@config.KeyPath::parse("shared"))[0].kind is File(Explicit))
  }
  let config = discover_in("/w/a", files, conventions=overlay_conventions(), formats=ordered_formats(), options=@conventions.DiscoveryOptions::new(config=Explicit("../acme.json")))
  assert_eq(@config.get_text(config, "shared"), "member")
  assert_eq(config.reports().filter(report => report.status is Loaded).map(report => report.priority), [300, 325, 350])
}

///|
test "selecting a supplemental file parses and transforms once" {
  let parses = Ref(0)
  let transforms = Ref(0)
  let json = @json5.format()
  let counted = { ..json, parse: (text, path) => { parses.val += 1; (json.parse)(text, path) } }
  let supplemental = @conventions.SupplementalFile::new("acme-workspace.json", @conventions.Extension::parse("json"), transform=value => {
    transforms.val += 1
    @config.fields([("workspace", value)])
  })
  let conventions = ordered_conventions(supplemental~) |> @conventions.selected_file_policy(Overlay)
  let config = discover_in("/w", [
    ("/w/acme-workspace.json", "{outDir:'supplemental'}"),
    ("/w/acme.toml", "workspace.outDir='toml'\nretained=true"),
  ], conventions~, formats=[counted, @yaml.format(), @toml.format()], options=@conventions.DiscoveryOptions::new(config=Explicit("./a/../acme-workspace.json")))
  assert_eq(parses.val, 1)
  assert_eq(transforms.val, 1)
  assert_eq(@config.get_text(config, "workspace.outDir"), "supplemental")
  assert_eq(@config.bind(config, "retained"), true)
  assert_eq(config.reports().filter(report => report.status is Loaded).map(report => report.path), [Some("/w/acme.toml"), Some("/w/acme-workspace.json")])
}

///|
test "selected base controls keep original per-format authority and origins" {
  let calls = Ref(0)
  let json = @json5.format()
  let counted = { ..json, parse: (text, path) => { calls.val += 1; (json.parse)(text, path) } }
  let config = discover_in("/w", [
    ("/w/acme.json", "{workspace:{}, profiles:{default:['env'],groups:{env:['wrong']}}, shared:'json'}"),
    ("/w/acme.toml", "profiles.groups.env=['metrics']\nshared='toml'"),
    ("/w/acme.profile.metrics.toml", "enabled=true"),
  ], conventions=overlay_conventions() |> @conventions.profiles(@profiles.Policy::new()), formats=[counted,@yaml.format(),@toml.format()], options=@conventions.DiscoveryOptions::new(config=Explicit("acme.json")))
  assert_eq(calls.val, 1)
  assert_eq(@config.get_text(config, "shared"), "json")
  assert_eq(@config.bind(config, "enabled"), true)
  guard config.profiles() is Resolved(resolution) else { fail("no profiles") }
  guard resolution.selector() is BaseDefault(origin) else { fail("no base default") }
  assert_eq(origin.location, Some("/w/acme.json"))
  assert_eq(origin.priority, 300)
  assert_true(origin.kind is File(Workspace))
  let origins = resolution.controls().filter_map(control => match control {
    Control(source, key) if key.to_string() == "profiles.groups.env" => source.location
    _ => None
  })
  assert_eq(origins, ["/w/acme.toml"])
  assert_true(config.get(@config.KeyPath::parse("profiles")) is None)
  assert_eq(config.reports().filter(report => report.path == Some("/w/acme.json")).length(), 1)
}

///|
test "external selected controls are refused before filters and disabled controls strip" {
  let conventions = overlay_conventions() |> @conventions.profiles(@profiles.Policy::new()) |> @conventions.inherited_filter(["profiles"])
  let files = [("/w/acme.toml", "workspace.members=['a']"), ("/w/a/acme.toml", "base=true"), ("/w/custom.json", "{profiles:{active:['metrics']}, enabled:true}")]
  try ignore(discover_in("/w", files, conventions~, formats=ordered_formats(), options=@conventions.DiscoveryOptions::new(config=Explicit("custom.json")))) catch {
    @config.Profile(failure~) => assert_eq(failure.rule(), ForbiddenLocation)
    error => raise error
  } noraise { _ => fail("external controls accepted") }
  let config = discover_in("/w", files, conventions~, formats=ordered_formats(), options=@conventions.DiscoveryOptions::new(config=Explicit("custom.json"), profiles=Disabled))
  assert_eq(@config.bind(config, "enabled"), true)
  assert_true(config.get(@config.KeyPath::parse("profiles")) is None)
}

///|
test "selected legacy fallback reuses its decoder once" {
  let calls = Ref(0)
  let conventions = @conventions.app_dirs("acme")
    |> @conventions.legacy("old.json", format=@json5.format(), decode=value => { calls.val += 1; @config.fields([("legacy", value)]) })
    |> @conventions.selected_file_policy(Overlay)
  let config = discover_in("/w", [("/w/old.json", "{enabled:true}")], conventions~, options=@conventions.DiscoveryOptions::new(config=Explicit("old.json")))
  assert_eq(calls.val, 1)
  assert_eq(@config.bind(config, "legacy.enabled"), true)
  assert_eq(config.reports().filter(report => report.status is Loaded).map(report => (report.path, report.priority)), [(Some("/w/old.json"), 325)])
}

///|
test "selected overlay complete and partial trees retain the same metadata and reports" {
  let entries = [
    ("/w/acme.json", "{workspace:{members:['a']}, profiles:{active:['metrics']}, shared:'json'}"),
    ("/w/acme.toml", "shared='toml'\nretained=true"),
    ("/w/a/acme.toml", "project.name='a'"),
    ("/w/acme.profile.metrics.toml", "enabled=true"),
  ]
  let conventions = overlay_conventions() |> @conventions.profiles(@profiles.Policy::new())
  let builder = ordered_formats().fold(init=@config.builder() |> @config.working_dir("/w/a"), (builder, format) => builder |> @config.format(format))
    |> @conventions.add(conventions, options=@conventions.DiscoveryOptions::new(config=Explicit("../acme.json")))
  let complete = @config.load(builder, disk(entries)) |> done
  let partial = load_from(builder, Map::from_array(entries))
  assert_eq(complete.value(), partial.value())
  assert_eq(report_rows(complete), report_rows(partial))
  assert_eq(complete.profiles(), partial.profiles())
  assert_eq(complete.origins(@config.KeyPath::parse("shared")), partial.origins(@config.KeyPath::parse("shared")))
}

///|
test "Windows selected identities use one canonical path and parse" {
  let calls = Ref(0)
  let toml = @toml.format()
  let counted = { ..toml, parse: (text, path) => { calls.val += 1; (toml.parse)(text, path) } }
  let tree = @config.FileTree::new(complete=true)
    .with_listing(p("C:/w"), files(["acme.toml"]))
    .with_file(p("C:/w/acme.toml"), "base=true")
  for selection in [".\\acme.toml", "a\\..\\acme.toml", "C:\\w\\.\\acme.toml"] {
    calls.val = 0
    let config = @config.builder() |> @config.working_dir("C:/w")
      |> @config.platform(Windows) |> @config.format(counted)
      |> @conventions.add(@conventions.app_dirs("acme") |> @conventions.selected_file_policy(Overlay), options=@conventions.DiscoveryOptions::new(config=Explicit(selection)))
      |> @config.load(tree) |> done
    assert_eq(calls.val, 1)
    assert_eq(config.reports().filter(report => report.status is Loaded).map(report => (report.path, report.priority)), [(Some("C:/w/acme.toml"), 325)])
  }
}

///|
test "selected machine values move once without changing member selection" {
  let conventions = overlay_conventions()
  let config = discover_in("/w", [
    ("/etc/acme/acme.toml", "workspace.members=['a']\nworkspace.default_member='a'\nshared='system'"),
    ("/w/acme.json", "{workspace:{}, shared:'workspace'}"),
    ("/w/a/acme.toml", "shared='member'"),
  ], conventions~, formats=ordered_formats(), platform=Linux, options=@conventions.DiscoveryOptions::new(config=Explicit("/etc/acme/acme.toml")))
  assert_eq(@config.get_text(config, "shared"), "member")
  assert_eq(config.reports().filter(report => report.kind is File(Member) && report.status is Loaded).map(report => report.path), [Some("/w/a/acme.toml")])
  assert_eq(config.reports().filter(report => report.path == Some("/etc/acme/acme.toml")).map(report => report.priority), [325])
}

///|
test "selected adjacent files leave one overlay report" {
  for selected in ["acme.user.toml", "acme.profile.metrics.toml"] {
    let config = discover_in("/w", [
      ("/w/acme.json", "{workspace:{}, profiles:{active:['metrics']}}"),
      ("/w/acme.user.toml", "shared='user'"),
      ("/w/acme.profile.metrics.toml", "shared='profile'"),
    ], conventions=overlay_conventions() |> @conventions.profiles(@profiles.Policy::new()), formats=ordered_formats(), options=@conventions.DiscoveryOptions::new(config=Explicit(selected)))
    assert_eq(config.reports().filter(report => report.path == Some("/w/" + selected)).map(report => report.priority), [325])
  }
}

///|
test "a missing selected overlay has a typed file error" {
  try ignore(discover_in("/w", [("/w/acme.toml", "[workspace]")], conventions=overlay_conventions(), formats=ordered_formats(), options=@conventions.DiscoveryOptions::new(config=Explicit("absent.toml")))) catch {
    @config.FileNotFound(path~) => assert_eq(path, "/w/absent.toml")
    error => raise error
  } noraise { _ => fail("missing overlay accepted") }
}

///|
test "overlay policy also deduplicates the default single-format primary" {
  let calls = Ref(0)
  let toml = @toml.format()
  let counted = { ..toml, parse: (text, path) => { calls.val += 1; (toml.parse)(text, path) } }
  let config = discover_in("/w", [("/w/acme.toml", "profiles.active=['metrics']\nbase=true"), ("/w/acme.profile.metrics.toml", "enabled=true")],
    conventions=@conventions.app_dirs("acme") |> @conventions.selected_file_policy(Overlay) |> @conventions.profiles(@profiles.Policy::new()), formats=[counted], options=@conventions.DiscoveryOptions::new(config=Explicit("./acme.toml")))
  assert_eq(calls.val, 2)
  assert_eq(@config.bind(config, "enabled"), true)
  assert_eq(config.reports().filter(report => report.status is Loaded).map(report => report.priority), [325, 380])
}

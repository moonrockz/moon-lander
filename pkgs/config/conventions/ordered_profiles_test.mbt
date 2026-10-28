///|
test "reserved env group metadata bypasses ordinary secret interpretation" {
  let conventions = ordered_conventions() |> @conventions.profiles(@profiles.Policy::new())
  for selection in [@config.ProfileSelection::Unspecified, Disabled] {
    let config = discover_in("/w", [
      ("/w/acme.json", "{workspace:{}, profiles:{active:['env'], groups:{env:['metrics']}}}"),
      ("/w/acme.toml", "base=true"),
      ("/w/acme.profile.metrics.toml", "enabled=true"),
    ], conventions~, formats=ordered_formats(), options=@conventions.DiscoveryOptions::new(profiles=selection))
    assert_eq(@config.bind(config, "base"), true)
    assert_true(config.get(@config.KeyPath::parse("profiles")) is None)
    guard config.profiles() is Resolved(resolution) else { fail("no profile resolution") }
    if selection is Disabled { assert_true(resolution.disabled()) } else {
      assert_eq(resolution.active().names().map(name => name.to_string()), ["env", "metrics"])
      assert_eq(@config.bind(config, "enabled"), true)
    }
  }
}

///|
test "layered profile controls retain individual origins and active-name order" {
  let conventions = ordered_conventions() |> @conventions.profiles(@profiles.Policy::new())
  let config = discover_in("/w", [
    ("/w/acme.json", "{workspace:{}, profiles:{active:['alpha']}}"),
    ("/w/acme.yaml", "profiles:\n  include: [extra]"),
    ("/w/acme.toml", "profiles.groups.alpha=['metrics']"),
    ("/w/acme.profile.extra.toml", "shared='extra-toml'"),
    ("/w/acme.profile.metrics.json5", "{shared:'metrics-json'}"),
  ], conventions~, formats=ordered_formats())
  assert_eq(@config.get_text(config, "shared"), "metrics-json")
  guard config.profiles() is Resolved(resolution) else { fail("no profile resolution") }
  assert_eq(resolution.active().names().map(name => name.to_string()), ["extra", "alpha", "metrics"])
  for (key, path) in [("profiles.active", "/w/acme.json"), ("profiles.include", "/w/acme.yaml"), ("profiles.groups.alpha", "/w/acme.toml")] {
    let origins = resolution.controls().filter_map(origin => match origin {
      Control(source, control) if control.to_string() == key => source.location
      _ => None
    })
    assert_eq(origins, [path])
  }
  let reports = config.reports().filter(report => report.status is Loaded && report.kind is File(ProfileFile(_)))
  assert_eq(reports.map(report => (report.priority, report.path)), [(380, Some("/w/acme.profile.extra.toml")), (380, Some("/w/acme.profile.metrics.json5"))])
}

///|
test "a wholly replaced base control stays eligible without reading its inactive profile" {
  let conventions = ordered_conventions() |> @conventions.profiles(@profiles.Policy::new())
  let config = discover_in("/w", [
    ("/w/acme.json", "{workspace:{}, profiles:{active:['ignored']}}"),
    ("/w/acme.toml", "profiles.active=['chosen']"),
    ("/w/acme.profile.ignored.toml", "not valid toml ["),
    ("/w/acme.profile.chosen.toml", "selected=true"),
  ], conventions~, formats=ordered_formats())
  assert_eq(@config.bind(config, "selected"), true)
  guard config.profiles() is Resolved(resolution) else { fail("no profile resolution") }
  assert_eq(resolution.active().names().map(name => name.to_string()), ["chosen"])
  assert_true(config.get(@config.KeyPath::parse("profiles")) is None)
}

///|
test "supplemental-only roots use the ordinary application profile stem" {
  let supplemental = @conventions.SupplementalFile::new("acme-workspace.json", @conventions.Extension::parse("json"))
  let conventions = ordered_conventions(supplemental~) |> @conventions.profiles(@profiles.Policy::new())
  let config = discover_in("/w", [
    ("/w/acme-workspace.json", "{workspace:{}, profiles:{active:['metrics']}}"),
    ("/w/acme.profile.metrics.toml", "selected='ordinary-stem'"),
    ("/w/acme-workspace.profile.metrics.json", "not valid JSON"),
  ], conventions~, formats=ordered_formats())
  assert_eq(@config.get_text(config, "selected"), "ordinary-stem")
}

///|
test "profile names precede workspace member and format order" {
  let conventions = ordered_conventions() |> @conventions.profiles(@profiles.Policy::new())
  let config = discover_in("/w/a/src", [
    ("/w/acme.json", "{workspace:{members:['a']}, profiles:{active:['early','late']}}"),
    ("/w/acme.toml", "base=true"),
    ("/w/a/acme.toml", "project.name='a'"),
    ("/w/acme.profile.early.json", "{shared:'workspace-json'}"),
    ("/w/acme.profile.early.toml", "shared='workspace-toml'"),
    ("/w/a/acme.profile.early.json", "{shared:'member-json'}"),
    ("/w/a/acme.profile.early.toml", "shared='member-toml'"),
    ("/w/acme.profile.late.json", "{shared:'later-workspace-json'}"),
  ], conventions~, formats=ordered_formats())
  assert_eq(@config.get_text(config, "shared"), "later-workspace-json")
  let reports = config.reports().filter(report => report.status is Loaded && report.kind is File(ProfileFile(_)))
  assert_eq(reports.map(report => report.path), [
    Some("/w/acme.profile.early.json"), Some("/w/acme.profile.early.toml"),
    Some("/w/a/acme.profile.early.json"), Some("/w/a/acme.profile.early.toml"),
    Some("/w/acme.profile.late.json"),
  ])
  assert_true(reports.all(report => report.priority == 380))
}

///|
test "profile layout reuse reads one identity and keeps same-group ambiguity" {
  let conventions = ordered_conventions() |> @conventions.profiles(@profiles.Policy::new())
  let base = [("/w/acme.json", "{workspace:{}, profiles:{active:['metrics']}}"), ("/w/.acme/acme.toml", "base=true")]
  let config = discover_in("/w", base + [("/w/acme.profile.metrics.json", "{enabled:true}")], conventions~, formats=ordered_formats())
  assert_eq(@config.bind(config, "enabled"), true)
  assert_eq(config.reports().filter(report => report.status is Loaded && report.kind is File(ProfileFile(_))).length(), 1)
  let (_, paths) = ambiguity(() => ignore(discover_in("/w", base + [
    ("/w/acme.profile.metrics.toml", "enabled=true"),
    ("/w/.acme/acme.profile.metrics.toml", "enabled=false"),
  ], conventions~, formats=ordered_formats())))
  assert_eq(paths.length(), 2)
}

///|
test "isolated ordered profiles stay inside the boundary and retain activation" {
  let conventions = ordered_conventions()
    |> @conventions.boundary("/w")
    |> @conventions.profiles(@profiles.Policy::new())
  let config = discover_in("/w/a", [
    ("/acme.toml", "not valid toml ["),
    ("/w/acme.json", "{workspace:{}, profiles:{active:['metrics']}}"),
    ("/w/acme.profile.metrics.json", "{shared:'json', retained:true}"),
    ("/w/acme.profile.metrics.toml", "shared='toml'"),
    ("/w/acme.local.toml", "not valid toml ["),
    ("/w/acme.user.toml", "not valid toml ["),
    ("/w/acme.profile.inactive.toml", "not valid toml ["),
  ], conventions~, formats=ordered_formats(), options=@conventions.DiscoveryOptions::new(isolated=true))
  assert_eq(@config.get_text(config, "shared"), "toml")
  assert_eq(@config.bind(config, "retained"), true)
  guard config.profiles() is Resolved(resolution) else { fail("no profile resolution") }
  assert_eq(resolution.active().names().map(name => name.to_string()), ["metrics"])
  let reports = config.reports().filter(report => report.status is Loaded && report.kind is File(ProfileFile(_)))
  assert_eq(reports.map(report => report.path), [Some("/w/acme.profile.metrics.json"), Some("/w/acme.profile.metrics.toml")])
}

///|
test "disabled layered profiles strip invalid controls without reading profile files" {
  let conventions = ordered_conventions() |> @conventions.profiles(@profiles.Policy::new())
  let config = discover_in("/w", [
    ("/w/acme.json", "{workspace:{}, profiles:false, base:true}"),
    ("/w/acme.toml", "profiles.active=42"),
    ("/w/acme.profile.metrics.toml", "not valid toml ["),
  ], conventions~, formats=ordered_formats(), options=@conventions.DiscoveryOptions::new(profiles=Disabled, isolated=true))
  assert_true(config.get(@config.KeyPath::parse("profiles")) is None)
  assert_eq(@config.bind(config, "base"), true)
  assert_true(config.reports().all(report => !(report.kind is File(ProfileFile(_)))))
}

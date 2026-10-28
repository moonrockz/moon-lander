///|
fn profile_builder() -> @config.ConfigBuilder raise @config.ConfigError {
  @config.builder()
  |> @config.working_dir("/w")
  |> @config.env_vars({})
  |> @config.format(@toml.format())
  |> @conventions.add(
    @conventions.base("acme") |> @conventions.layouts |> @conventions.profiles(@profiles.Policy::new()),
    options=@conventions.DiscoveryOptions::new(profiles=Selected(@config.ProfileNames::new([@config.ProfileName::parse("metrics")]))),
  )
}

///|
test "profile vertical proof preserves role priority provenance and membership" {
  let config = load_from(profile_builder(), {
    "/w/acme.toml": "mode = \"base\"",
    "/w/acme.profile.metrics.toml": "mode = \"metrics\"",
  })
  let metrics = @config.ProfileName::parse("metrics")
  @expect.expect(@config.get_text(config, "mode")).to_equal("metrics")
  @expect.expect(config.profiles().contains(metrics)).to_equal(true)
  let origin = config.origins(@config.KeyPath::parse("mode"))[0]
  @expect.expect((origin.kind, origin.priority, origin.location)).to_equal((File(ProfileFile(metrics)), 380, Some("/w/acme.profile.metrics.toml")))
  @expect.expect(config.reports().map(report => report.priority)).to_equal([300, 380])
}

///|
test "unknown profile content returns Need instead of final metadata" {
  let tree = @config.FileTree::new()
    .with_listing(p("/w"), files(["acme.toml", "acme.profile.metrics.toml"]))
    .with_missing(p("/w/.acme"))
    .with_missing(p("/w/.config/acme"))
    .with_file(p("/w/acme.toml"), "mode = \"base\"")
  guard @config.load(profile_builder(), tree) is Need(requests) else { fail("profile contents are unknown") }
  @expect.expect(requests).to_equal([ReadFile(p("/w/acme.profile.metrics.toml"))])
}

///|
test "competing enabled providers fail with both identities" {
  let builder = profile_builder() |> @conventions.add(
    @conventions.base("other") |> @conventions.profiles(@profiles.Policy::new()),
  )
  try {
    ignore(@config.load(builder, @config.FileTree::new(complete=true)))
    fail("expected competing providers")
  } catch {
    @config.Profile(failure~) => @expect.expect(failure.rule()).to_equal(CompetingProviders("acme", "other"))
    error => raise error
  }
}

///|
fn named(text : String) -> @config.ProfileNames raise @config.ConfigError { @config.ProfileNames::parse_csv(text) }

///|
fn profiles_options(selection? : @config.ProfileSelection = Unspecified, vars? : Map[String, String] = {}, conventions? : @conventions.Conventions) -> @config.ConfigBuilder raise @config.ConfigError {
  let conventions = conventions.unwrap_or(@conventions.app_dirs("acme") |> @conventions.without(SystemDir) |> @conventions.without(UserConfigDir) |> @conventions.without(AppHome))
  @config.builder() |> @config.working_dir("/w") |> @config.platform(Linux) |> @config.env_vars(vars)
  |> @config.format(@toml.format())
  |> @conventions.add(conventions |> @conventions.boundary("/w") |> @conventions.profiles(@profiles.Policy::new() |> @profiles.fallback(named("fallback"))), options=@conventions.DiscoveryOptions::new(profiles=selection))
}

///|
fn active(config : @config.Config) -> Array[String] {
  match config.profiles() { Off => []; Resolved(resolution) => resolution.active().names().map(name => name.to_string()) }
}

///|
test "base controls choose groups remove controls and retain source origins" {
  let config = load_from(profiles_options(), {
    "/w/acme.toml": "[profiles]\ninclude=['metrics']\nactive=['production','postgres']\n[profiles.groups]\nproduction=['postgres','metrics']\n",
    "/w/acme.profile.postgres.toml": "mode='postgres'",
    "/w/acme.profile.metrics.toml": "mode='metrics'",
  })
  @expect.expect(active(config)).to_equal(["production", "metrics", "postgres"])
  @expect.expect(@config.get_text(config,"mode")).to_equal("postgres")
  @expect.expect(config.get(@config.KeyPath::parse("profiles"))).to_equal(None)
  @expect.expect(config.origins(@config.KeyPath::parse("profiles.active"))).to_equal([])
  guard config.profiles() is Resolved(resolution) else { fail("enabled") }
  @expect.expect(resolution.selector()).to_equal(BaseActive({kind:File(Workspace), source:"acme", priority:300, location:Some("/w/acme.toml")}))
  @expect.expect(resolution.controls().is_empty()).to_equal(false)
}

///|
test "selection precedence empty active and variable disable are distinct" {
  let disk = { "/w/acme.toml": "[profiles]\ninclude=['common']\nactive=[]\ndefault=['development']" }
  @expect.expect(active(load_from(profiles_options(), disk))).to_equal(["common"])
  @expect.expect(active(load_from(profiles_options(vars={"ACME_PROFILES":"postgres"}), disk))).to_equal(["common","postgres"])
  @expect.expect(active(load_from(profiles_options(selection=Selected(named("metrics")), vars={"ACME_PROFILES":"postgres"}), disk))).to_equal(["common","metrics"])
  for vars in [{"ACME_PROFILES":""}, {"ACME_PROFILES":" \t\r\n"}] {
    let config = load_from(profiles_options(vars~), disk)
    @expect.expect(active(config)).to_equal([])
    guard config.profiles() is Resolved(resolution) else { fail("enabled disabled result") }
    @expect.expect(resolution.disabled()).to_equal(true)
    @expect.expect(resolution.selector()).to_equal(Variable("ACME_PROFILES"))
    @expect.expect(config.reports().any(report => report.kind is File(ProfileFile(_)))).to_equal(false)
  }
}

///|
test "disable ignores invalid controls across loaded sources and strips them" {
  let config = load_from(profiles_options(selection=Disabled), {
    "/w/acme.toml":"profiles.active=42\nmode='base'",
    "/w/acme.local.toml":"profiles=17\nmode='local'",
    "/w/acme.profile.metrics.toml":"not TOML [",
  })
  @expect.expect(@config.get_text(config,"mode")).to_equal("local")
  @expect.expect(config.get(@config.KeyPath::parse("profiles"))).to_equal(None)
  @expect.expect(active(config)).to_equal([])
}

///|
test "invalid controls fail even with explicit higher priority selection" {
  for controls in ["active=42", "bogus=[]", "active=['Metrics']", "include=[{env='PROFILES'}]"] {
    try {
      ignore(load_from(profiles_options(selection=Selected(named("metrics"))), {"/w/acme.toml":"[profiles]\n\{controls}"}))
      fail("invalid controls must fail")
    } catch {
      @config.Profile(failure~) => {
        guard failure.origin() is Control(origin, _) else { fail("file control origin") }
        @expect.expect(origin.location).to_equal(Some("/w/acme.toml"))
      }
      error => raise error
    }
  }
}

///|
test "forbidden overlays fail before inherited and member filters" {
  for path in ["/w/acme.profile.metrics.toml", "/w/acme.local.toml", "/w/acme.user.toml", "/w/acme.Production.toml"] {
    let conventions = @conventions.app_dirs("acme") |> @conventions.environments(default="Production")
    let disk = Map::from_array([("/w/acme.toml","[profiles]\nactive=['metrics']"), (path,"profiles.include=['other']")])
    try { ignore(load_from(profiles_options(conventions~), disk)); fail("forbidden controls") } catch {
      @config.Profile(failure~) => {
        @expect.expect(failure.rule()).to_equal(ForbiddenLocation)
        guard failure.origin() is Control(origin, _) else { fail("origin") }
        @expect.expect(origin.location).to_equal(Some(path))
      }
      error => raise error
    }
  }
  let conventions = @conventions.app_dirs("acme") |> @conventions.workspace |> @conventions.inherited_filter(["profiles"]) |> @conventions.member_scope_keys(["profiles"])
  try {
    ignore(load_from(profiles_options(conventions~), {"/w/acme.toml":"workspace.members=['member']\nworkspace.default_member='member'", "/w/member/acme.toml":"profiles.active=['metrics']"}))
    fail("member controls cannot hide in filters")
  } catch { @config.Profile(failure~) => @expect.expect(failure.rule()).to_equal(ForbiddenLocation); error => raise error }
}

///|
test "generic override and nested variable controls cannot activate profiles" {
  for source in [@config.ConfigSource::overrides_value(@config.fields([("profiles",@config.fields([("active",@config.string("metrics"))]))])), @config.ConfigSource::env(prefix="ACME", selection=Explicit({"ACME_PROFILES__ACTIVE":"metrics"}))] {
    try {
      ignore(load_from(profiles_options(selection=Selected(named("metrics"))) |> @config.add(source), {"/w/acme.toml":"mode='base'"}))
      fail("reserved controls from generic source")
    } catch { @config.Profile(failure~) => @expect.expect(failure.rule()).to_equal(ForbiddenLocation); error => raise error }
  }
}

///|
test "all standard layouts exact names ambiguity and missing markers" {
  for stem in ["/w/acme", "/w/.acme/acme", "/w/.config/acme/config"] {
    let disk = Map::from_array([("\{stem}.toml","mode='base'"), ("\{stem}.profile.metrics.toml","mode='profile'"), ("\{stem}.profile.Metrics.toml","not TOML [")])
    let config = load_from(profiles_options(selection=Selected(named("metrics,marker"))), disk)
    @expect.expect(@config.get_text(config,"mode")).to_equal("profile")
    @expect.expect(active(config)).to_equal(["metrics","marker"])
    let reports = config.reports().filter(report => report.kind is File(ProfileFile(_)))
    @expect.expect(reports.map(report => report.status)).to_equal([Loaded,NotFound])
  }
  let builder = profiles_options(selection=Selected(named("metrics"))) |> @config.format(yaml_stub())
  try {
    ignore(load_from(builder, {"/w/acme.toml":"", "/w/acme.profile.metrics.toml":"", "/w/acme.profile.metrics.yaml":""}))
    fail("ambiguous formats")
  } catch { @config.Ambiguous(candidates~, ..) => @expect.expect(candidates.length()).to_equal(2); error => raise error }
}

///|
test "profile workspace stage orders names then locations and respects filters" {
  let conventions = @conventions.app_dirs("acme") |> @conventions.workspace |> @conventions.environments(default="Production")
    |> @conventions.inherited_filter(["project"]) |> @conventions.member_scope_keys(["workspace.out_dir"])
  let disk = {
    "/w/acme.toml":"workspace.members=['member']\nworkspace.default_member='member'\nworkspace.out_dir='root'\n[profiles]\nactive=['postgres','metrics']",
    "/w/member/acme.toml":"mode='member'",
    "/w/acme.Production.toml":"mode='environment'",
    "/w/member/acme.Production.toml":"mode='member-environment'",
    "/w/acme.profile.postgres.toml":"mode='workspace-postgres'",
    "/w/member/acme.profile.postgres.toml":"mode='member-postgres'",
    "/w/acme.profile.metrics.toml":"mode='metrics'\nproject.name='not inherited'",
    "/w/member/acme.profile.metrics.toml":"workspace.out_dir='forbidden'",
    "/w/acme.local.toml":"local=true",
    "/w/member/acme.local.toml":"local=false",
  }
  let config = load_from(profiles_options(conventions~), disk)
  @expect.expect(@config.get_text(config,"mode")).to_equal("metrics")
  @expect.expect(@config.get_text(config,"workspace.out_dir")).to_equal("root")
  @expect.expect(config.get(@config.KeyPath::parse("project.name"))).to_equal(None)
  let reports = config.reports().filter(report => report.kind is File(ProfileFile(_)))
  @expect.expect(reports.map(report => report.path)).to_equal([
    Some("/w/acme.profile.postgres.toml"),Some("/w/member/acme.profile.postgres.toml"),
    Some("/w/acme.profile.metrics.toml"),Some("/w/member/acme.profile.metrics.toml"),
  ])
  @expect.expect(reports[3].warnings.length()).to_equal(1)
  @expect.expect(config.reports().filter(report => report.status is Loaded).map(report => report.priority)).to_equal([300,350,375,375,380,380,380,380,390,390])
}

///|
test "isolated profiles retain project stage while explicit paths require standard layouts" {
  let disk = {"/w/acme.toml":"mode='base'", "/w/acme.profile.metrics.toml":"mode='profile'", "/w/acme.local.toml":"mode='local'", "/w/custom.toml":"mode='custom'", "/w/custom.profile.metrics.toml":"invalid TOML ["}
  let conventions = @conventions.app_dirs("acme") |> @conventions.profiles(@profiles.Policy::new())
  for (filename,expected) in [("acme.toml","profile"),("custom.toml","custom")] {
    let builder = @config.builder() |> @config.working_dir("/w") |> @config.env_vars({}) |> @config.format(@toml.format())
      |> @conventions.add(conventions,options=@conventions.DiscoveryOptions::new(config=Explicit(filename),isolated=true,profiles=Selected(named("metrics"))))
    let config = load_from(builder,disk)
    @expect.expect(@config.get_text(config,"mode")).to_equal(expected)
    @expect.expect(config.reports().filter(report => report.kind is File(ProfileFile(_))).length()).to_equal(if filename == "acme.toml" {1} else {0})
  }
}

///|
test "profile-only directory is no root marker and inaccessible selected candidates request contents" {
  let builder = profiles_options(selection=Selected(named("metrics")))
  let config = load_from(builder,{"/w/acme.profile.metrics.toml":"mode='must not load'"})
  @expect.expect(config.reports().any(report => report.kind is File(ProfileFile(_)))).to_equal(false)
  let tree = @config.FileTree::new()
    .with_listing(p("/w"),[{name:"acme.toml",kind:File},{name:"acme.profile.metrics.toml",kind:Inaccessible}])
    .with_missing(p("/w/.acme")).with_missing(p("/w/.config/acme"))
    .with_file(p("/w/acme.toml"),"mode='base'")
  guard @config.load(builder,tree) is Need(requests) else {fail("inaccessible selected candidate must request contents")}
  @expect.expect(requests).to_equal([ReadFile(p("/w/acme.profile.metrics.toml"))])
}

///|
test "profile processing rejects system global legacy and nonstandard controls" {
  let conventions = @conventions.app_dirs("acme") |> @conventions.boundary("/w") |> @conventions.profiles(@profiles.Policy::new())
  for filename in ["/etc/acme/acme.toml","/home/test/.config/acme/acme.toml"] {
    let builder = @config.builder() |> @config.working_dir("/w") |> @config.platform(Linux)
      |> @config.env_vars({"HOME":"/home/test"}) |> @config.format(@toml.format()) |> @conventions.add(conventions)
    let disk = Map::from_array([("/w/acme.toml","mode='base'"),(filename,"profiles.active=['metrics']")])
    try {ignore(load_from(builder,disk));fail("forbidden controls")} catch {
      @config.Profile(failure~) => @expect.expect(failure.rule()).to_equal(ForbiddenLocation)
      error => raise error
    }
  }
  for filename in ["custom.toml","legacy.toml"] {
    let builder = @config.builder() |> @config.working_dir("/w") |> @config.env_vars({}) |> @config.format(@toml.format())
      |> @conventions.add(conventions,options=@conventions.DiscoveryOptions::new(config=Explicit(filename)))
    try {ignore(load_from(builder,Map::from_array([("/w/\{filename}","profiles.active=['metrics']")])));fail("nonstandard controls")} catch {
      @config.Profile(failure~) => @expect.expect(failure.rule()).to_equal(ForbiddenLocation)
      error => raise error
    }
  }
}


///|
test "legacy fallback controls are forbidden and have no adjacent profile" {
  let conventions = @conventions.base("acme") |> @conventions.layouts
    |> @conventions.legacy("old.toml",format=@toml.format(),decode=value=>value)
    |> @conventions.profiles(@profiles.Policy::new())
  let builder = @config.builder() |> @config.working_dir("/w") |> @config.env_vars({})
    |> @config.format(@toml.format()) |> @conventions.add(conventions,options=@conventions.DiscoveryOptions::new(profiles=Selected(named("metrics"))))
  let config = load_from(builder,{"/w/old.toml":"mode='legacy'","/w/old.profile.metrics.toml":"invalid ["})
  @expect.expect(active(config)).to_equal(["metrics"])
  @expect.expect(config.reports().any(report=>report.kind is File(ProfileFile(_)))).to_equal(false)
  try {ignore(load_from(builder,{"/w/old.toml":"profiles.active=['metrics']"}));fail("legacy controls") } catch {
    @config.Profile(failure~)=>@expect.expect(failure.rule()).to_equal(ForbiddenLocation)
    error=>raise error
  }
}

///|
test "profile values cannot reselect the workspace member" {
  let conventions = @conventions.app_dirs("acme") |> @conventions.workspace
  let config = load_from(profiles_options(conventions~), {
    "/w/acme.toml": "workspace.members=['a','b']\nworkspace.default_member='a'\n[profiles]\nactive=['metrics']",
    "/w/a/acme.toml": "mode='member-a'",
    "/w/b/acme.toml": "mode='member-b'",
    "/w/acme.profile.metrics.toml": "workspace.default_member='b'",
  })
  @expect.expect(@config.get_text(config,"mode")).to_equal("member-a")
  @expect.expect(config.reports().filter(report => report.kind is File(Member)).map(report => report.path)).to_equal([Some("/w/a/acme.toml")])
}

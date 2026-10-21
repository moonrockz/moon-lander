///|
test "Adjacent override wins" {
  let config = discover_in("/w", [
    ("/w/acme.toml", "ui.theme = \"shared\""),
    ("/w/acme.user.toml", "ui.theme = \"personal\""),
  ])
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("personal")
  let report = report_of(config, UserOverride).unwrap()
  @expect.expect((report.priority, report.path, report.kind.report_name())).to_equal((
    400,
    Some("/w/acme.user.toml"),
    "user-override",
  ))
}

///|
test "Dot-config override wins" {
  let config = discover_in("/w", [
    ("/w/.config/acme/config.toml", "ui.theme = \"shared\""),
    ("/w/.config/acme/config.user.toml", "ui.theme = \"personal\""),
  ])
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("personal")
}

///|
test "a hidden-directory primary has its override in the same directory" {
  let config = discover_in("/w", [
    ("/w/.acme/acme.toml", "ui.theme = \"shared\""),
    ("/w/.acme/acme.user.toml", "ui.theme = \"personal\""),
  ])
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("personal")
}

///|
test "Sibling override serializations" {
  let (location, candidates) = ambiguity(() => {
    discover_in(
      "/w",
      [("/w/acme.toml", ""), ("/w/acme.user.toml", ""), ("/w/acme.user.yaml", "")],
      formats=[@toml.format(), yaml_only()],
    )
    |> ignore
  })
  @expect.expect((location, candidates)).to_equal((
    "/w",
    ["/w/acme.user.toml", "/w/acme.user.yaml"],
  ))
}

///|
test "an override of another serialization than the primary loads" {
  let config = discover_in(
    "/w",
    [("/w/acme.toml", "a = 1"), ("/w/acme.user.yaml", "")],
    formats=[@toml.format(), yaml_only()],
  )
  @expect.expect(@config.get_text(config, "format")).to_equal("yaml")
}

///|
test "Local file loads below the user override" {
  let files = [
    ("/w/acme.toml", "ui.theme = \"base\""),
    ("/w/acme.local.toml", "ui.theme = \"local\""),
    ("/w/acme.user.toml", "ui.theme = \"mine\""),
  ]
  let config = discover_in("/w", files)
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("mine")
  let report = report_of(config, LocalOverride).unwrap()
  @expect.expect((report.kind.report_name(), report.priority)).to_equal((
    "local-override", 390,
  ))
  let without_user = discover_in("/w", files[:2].to_owned())
  @expect.expect(@config.get_text(without_user, "ui.theme")).to_equal("local")
}

///|
test "Dot-config local override" {
  let config = discover_in("/w", [
    ("/w/.config/acme/config.toml", "ui.theme = \"shared\""),
    ("/w/.config/acme/config.local.toml", "ui.theme = \"local\""),
  ])
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("local")
}

///|
test "Sibling local override serializations" {
  let (_, candidates) = ambiguity(() => {
    discover_in(
      "/w",
      [("/w/acme.toml", ""), ("/w/acme.local.toml", ""), ("/w/acme.local.yaml", "")],
      formats=[@toml.format(), yaml_only()],
    )
    |> ignore
  })
  @expect.expect(candidates).to_equal(["/w/acme.local.toml", "/w/acme.local.yaml"])
}

///|
test "Standard set loads a local file" {
  let config = discover_in("/w", [
    ("/w/acme.toml", "a = 1"),
    ("/w/acme.local.toml", "b = 1"),
  ])
  let report = report_of(config, LocalOverride).unwrap()
  @expect.expect((report.path, report.status)).to_equal((
    Some("/w/acme.local.toml"),
    Loaded,
  ))
}

///|
test "Base set has no local layer" {
  let config = discover_in(
    "/w",
    [("/w/acme.toml", "a = 1"), ("/w/acme.local.toml", "b = 1")],
    conventions=@conventions.base("acme")
      |> @conventions.layouts
      |> @conventions.user_overrides,
  )
  @expect.expect(report_of(config, LocalOverride)).to_equal(None)
  @expect.expect(config.value()).to_equal(
    @config.fields([("a", @config.int(1))]),
  )
}

///|
test "without removes the local override part" {
  let config = discover_in(
    "/w",
    [("/w/acme.toml", "a = 1"), ("/w/acme.local.toml", "b = 1")],
    conventions=@conventions.app_dirs("acme")
      |> @conventions.without(LocalOverrides),
  )
  @expect.expect(report_of(config, LocalOverride)).to_equal(None)
}

///|
test "a primary with no overrides reports them not found" {
  let config = discover_in("/w", [("/w/acme.toml", "a = 1")])
  let report = report_of(config, UserOverride).unwrap()
  @expect.expect((report.status, report.candidates)).to_equal((
    NotFound,
    ["/w/acme.user.toml"],
  ))
}

///|
test "no primary gives no override source" {
  let config = discover_in("/w", [("/w/acme.user.toml", "a = 1")])
  @expect.expect(config.reports().map(report => report.kind)).to_equal([
    File(System),
    File(Global),
    File(Workspace),
  ])
}

///|
test "a legacy primary has no overrides" {
  let config = discover_in(
    "/w",
    [("/w/acme.json", "{}"), ("/w/acme.user.toml", "a = 1")],
    conventions=with_legacy(),
  )
  @expect.expect(report_of(config, UserOverride)).to_equal(None)
  @expect.expect(report_of(config, LocalOverride)).to_equal(None)
}

///|
test "Isolated mode skips user and machine files" {
  let builder = @config.builder()
    |> @config.working_dir("/w")
    |> @config.platform(Linux)
    |> @config.env_vars({ "HOME": "/home/alice", "ACME_FROM_ENV": "1" })
    |> @config.format(@toml.format())
    |> @config.defaults({ "from_defaults": 1 })
    |> @conventions.add(
      @conventions.app_dirs("acme"),
      options=@conventions.DiscoveryOptions::new(isolated=true),
    )
    |> @config.env(prefix="ACME", reserved=["ACME_HOME"])
  let config = builder
    |> @config.load(
      disk([
        ("/home/alice/.config/acme/acme.toml", "from_global = 1"),
        ("/etc/acme/acme.toml", "from_system = 1"),
        ("/w/acme.toml", "from_project = 1"),
        ("/w/acme.local.toml", "from_local = 1"),
        ("/w/acme.user.toml", "from_user = 1"),
      ]),
    )
    |> done
  @expect.expect(
    config.reports().map(report => (report.kind.report_name(), report.status)),
  ).to_equal([
    ("defaults", Loaded),
    ("system", Skipped),
    ("global", Skipped),
    ("project", Loaded),
    ("local-override", Skipped),
    ("user-override", Skipped),
    ("environment", Loaded),
  ])
  @expect.expect(config.value()).to_equal(
    @config.fields([
      ("from_defaults", @config.int(1)),
      ("from_project", @config.int(1)),
      ("from_env", @config.int(1)),
    ]),
  )
}

///|
test "convention sources are in merge order with rising priorities" {
  let config = discover_in(
    "/w",
    [("/w/acme.toml", "a = 1")],
    platform=Linux,
    env_vars={ "HOME": "/home/alice" },
  )
  @expect.expect(
    config.reports().map(report => (report.kind.report_name(), report.priority)),
  ).to_equal([
    ("system", 100),
    ("global", 200),
    ("project", 300),
    ("local-override", 390),
    ("user-override", 400),
  ])
}

///|
test "Explicit file from another directory" {
  let config = discover_in(
    "/w/elsewhere",
    [("/w/configs/project.yaml", ""), ("/w/elsewhere/acme.toml", "a = 1")],
    formats=[@toml.format(), yaml_only()],
    options=@conventions.DiscoveryOptions::new(
      config=Explicit("../configs/project.yaml"),
    ),
  )
  let report = project(config)
  @expect.expect((report.kind, report.path, report.status)).to_equal((
    File(Explicit),
    Some("/w/configs/project.yaml"),
    Loaded,
  ))
  // The explicit file replaces the walk-up, so the nearer acme.toml stays out.
  @expect.expect(config.get(@config.KeyPath::parse("a"))).to_equal(None)
}

///|
test "Explicit non-standard file has no override" {
  let config = discover_in(
    "/w",
    [("/w/configs/project.yaml", ""), ("/w/configs/project.user.yaml", "")],
    formats=[@toml.format(), yaml_only()],
    options=@conventions.DiscoveryOptions::new(
      config=Explicit("configs/project.yaml"),
    ),
  )
  @expect.expect(report_of(config, UserOverride)).to_equal(None)
  @expect.expect(report_of(config, LocalOverride)).to_equal(None)
}

///|
test "an explicit file in a standard layout has its overrides" {
  let config = discover_in(
    "/w",
    [
      ("/x/.config/acme/config.toml", "ui.theme = \"shared\""),
      ("/x/.config/acme/config.local.toml", "ui.theme = \"local\""),
    ],
    options=@conventions.DiscoveryOptions::new(
      config=Explicit("/x/.config/acme/config.toml"),
    ),
  )
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("local")
  @expect.expect(project(config).path).to_equal(
    Some("/x/.config/acme/config.toml"),
  )
}

///|
test "an explicit Windows path uses the / form" {
  let config = discover_in(
    "C:/work",
    [],
    options=@conventions.DiscoveryOptions::new(
      config=Explicit("configs\\acme.toml"),
    ),
    platform=Windows,
    env_vars={},
  ) catch {
    FileNotFound(path~) => {
      @expect.expect(path).to_equal("C:/work/configs/acme.toml")
      return
    }
    error => fail("expected file-not-found, got \{error.message()}")
  }
  fail("expected file-not-found, got \{project(config).status.to_repr()}")
}

///|
test "a missing explicit file is an error" {
  try
    discover_in(
      "/w",
      [],
      options=@conventions.DiscoveryOptions::new(config=Explicit("/w/nope.toml")),
    )
  catch {
    FileNotFound(path~) => @expect.expect(path).to_equal("/w/nope.toml")
    error => fail("expected file-not-found, got \{error.message()}")
  } noraise {
    _ => fail("expected file-not-found")
  }
}

///|
test "a skipped config option skips the project primary" {
  let config = discover_in(
    "/w",
    [("/w/acme.toml", "a = 1")],
    options=@conventions.DiscoveryOptions::new(config=Skip),
  )
  @expect.expect(project(config).status).to_equal(Skipped)
  @expect.expect(report_of(config, UserOverride)).to_equal(None)
}

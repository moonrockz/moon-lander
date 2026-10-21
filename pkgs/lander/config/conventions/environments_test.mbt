///|
/// The standard convention set with environments on.
fn acme_envs(default? : String) -> @conventions.Conventions {
  @conventions.app_dirs("acme") |> @conventions.environments(default?)
}

///|
fn name_of(
  options? : @conventions.DiscoveryOptions = @conventions.DiscoveryOptions::new(),
  env_vars? : Map[String, String] = {},
  default? : String,
) -> String? raise @config.ConfigError {
  @conventions.environment_name(acme_envs(default?), options~, env_vars)
}

///|
/// The reason of the `InvalidEnvironmentName` error that `run` raises.
fn invalid_name(run : () -> Unit raise @config.ConfigError) -> (String, String) {
  try run() catch {
    InvalidEnvironmentName(name~, reason~) => (name, reason)
    error => abort("expected an invalid name error, got \{error.message()}")
  } noraise {
    _ => abort("expected an invalid name error")
  }
}

///|
test "Option wins" {
  let name = name_of(
    options=@conventions.DiscoveryOptions::new(environment="Staging"),
    env_vars={ "ACME_ENVIRONMENT": "Production" },
  )
  @expect.expect(name).to_equal(Some("Staging"))
}

///|
test "Variable wins over default" {
  let name = name_of(
    env_vars={ "ACME_ENVIRONMENT": "Production" },
    default="Development",
  )
  @expect.expect(name).to_equal(Some("Production"))
}

///|
test "Empty variable is unset" {
  let name = name_of(env_vars={ "ACME_ENVIRONMENT": "" }, default="Development")
  @expect.expect(name).to_equal(Some("Development"))
}

///|
test "No source gives no name" {
  @expect.expect(name_of()).to_equal(None)
  let config = discover_in(
    "/w",
    [("/w/acme.toml", "a = 1"), ("/w/acme.Production.toml", "a = 2")],
    conventions=acme_envs(),
  )
  @expect.expect(report_of(config, EnvironmentFile)).to_equal(None)
  @expect.expect(@config.get_text(config, "a")).to_equal("1")
}

///|
test "Arguments are not read" {
  // Discovery has no input for the process arguments, so a `--environment`
  // flag that a host does not give as the option has no effect.
  @expect.expect(name_of(env_vars={ "OTHER": "--environment Staging" })).to_equal(
    None,
  )
}

///|
test "Default options" {
  let config = discover_in("/w", [("/w/acme.toml", "a = 1")])
  let project = report_of(config, Workspace).unwrap()
  @expect.expect((project.path, project.status)).to_equal(
    (Some("/w/acme.toml"), Loaded),
  )
  @expect.expect(report_of(config, EnvironmentFile)).to_equal(None)
}

///|
test "environments are off unless the application turns them on" {
  let options = @conventions.DiscoveryOptions::new(environment="Staging")
  @expect.expect(
    @conventions.environment_name(@conventions.app_dirs("acme"), options~, {
      "ACME_ENVIRONMENT": "Production",
    }),
  ).to_equal(None)
  let config = discover_in(
    "/w",
    [("/w/acme.toml", "a = 1"), ("/w/acme.Staging.toml", "a = 2")],
    options~,
  )
  @expect.expect(@config.get_text(config, "a")).to_equal("1")
  @expect.expect(
    config
    .warnings()
    .contains(
      Note(
        source="acme",
        message="environments are off, so discovery ignores the environment option",
      ),
    ),
  ).to_equal(true)
}

///|
test "the variable uses the prefix of the convention set" {
  let conventions = @conventions.app_dirs("acme", prefix="ACME_CLI")
    |> @conventions.environments
  @expect.expect(
    @conventions.environment_name(conventions, {
      "ACME_ENVIRONMENT": "Production",
      "ACME_CLI_ENVIRONMENT": "Staging",
    }),
  ).to_equal(Some("Staging"))
}

///|
test "Reserved name rejected" {
  let (name, reason) = invalid_name(() => {
    discover_in("/w", [("/w/acme.toml", "")], conventions=acme_envs(), env_vars={
      "ACME_ENVIRONMENT": "User",
    })
    |> ignore
  })
  @expect.expect((name, reason)).to_equal(
    ("User", "the name is reserved (from ACME_ENVIRONMENT)"),
  )
}

///|
test "Reserved name local rejected" {
  let (_, reason) = invalid_name(() => {
    name_of(options=@conventions.DiscoveryOptions::new(environment="Local"))
    |> ignore
  })
  @expect.expect(reason).to_equal(
    "the name is reserved (from the discovery options)",
  )
}

///|
test "Path name rejected" {
  let (name, reason) = invalid_name(() => {
    name_of(options=@conventions.DiscoveryOptions::new(environment="../prod"))
    |> ignore
  })
  @expect.expect((name, reason)).to_equal(
    (
      "../prod", "the name contains /, \\, . or a control character (from the discovery options)",
    ),
  )
}

///|
test "the name rules" {
  let reason = (name : String) => {
    try {
      @conventions.check_environment_name(name, source="--environment")
      None
    } catch {
      InvalidEnvironmentName(reason~, ..) => Some(reason)
      _ => Some("another error")
    }
  }
  let bad_char = Some(
    "the name contains /, \\, . or a control character (from --environment)",
  )
  @expect.expect(
    ["", "uSeR", "LOCAL", "a/b", "a\\b", "Prod.EU", "a\tb", "a\u{7f}"].map(
      reason,
    ),
  ).to_equal([
    Some("the name is empty (from --environment)"),
    Some("the name is reserved (from --environment)"),
    Some("the name is reserved (from --environment)"),
    bad_char,
    bad_char,
    bad_char,
    bad_char,
    bad_char,
  ])
  @expect.expect(
    ["Production", "users", "staging-2", "Développement"].map(reason),
  ).to_equal([None, None, None, None])
}

///|
test "an invalid default names the convention set" {
  let (_, reason) = invalid_name(() => name_of(default="") |> ignore)
  @expect.expect(reason).to_equal(
    "the name is empty (from the default of acme)",
  )
}

///|
test "Environment file between primary and override" {
  let files = [
    ("/w/acme.toml", "ui.theme = \"base\""),
    ("/w/acme.Production.toml", "ui.theme = \"prod\""),
    ("/w/acme.user.toml", "ui.theme = \"mine\""),
  ]
  let options = @conventions.DiscoveryOptions::new(environment="Production")
  let config = discover_in("/w", files, conventions=acme_envs(), options~)
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("mine")
  let report = report_of(config, EnvironmentFile).unwrap()
  @expect.expect((report.path, report.priority, report.kind.report_name())).to_equal(
    (Some("/w/acme.Production.toml"), 375, "environment-file"),
  )
  let without_user = discover_in(
    "/w",
    files[:2].to_owned(),
    conventions=acme_envs(),
    options~,
  )
  @expect.expect(@config.get_text(without_user, "ui.theme")).to_equal("prod")
}

///|
test "Local file loads between environment file and user override" {
  let files = [
    ("/w/acme.toml", "ui.theme = \"base\""),
    ("/w/acme.Production.toml", "ui.theme = \"prod\""),
    ("/w/acme.local.toml", "ui.theme = \"local\""),
    ("/w/acme.user.toml", "ui.theme = \"mine\""),
  ]
  let config = discover_in(
    "/w",
    files,
    conventions=acme_envs(default="Production"),
  )
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("mine")
  @expect.expect(
    config.reports().map(report => (report.kind.report_name(), report.priority)),
  ).to_equal([
    ("system", 100),
    ("global", 200),
    ("project", 300),
    ("environment-file", 375),
    ("local-override", 390),
    ("user-override", 400),
  ])
  let without_user = discover_in(
    "/w",
    files[:3].to_owned(),
    conventions=acme_envs(default="Production"),
  )
  @expect.expect(@config.get_text(without_user, "ui.theme")).to_equal("local")
}

///|
test "Case must match" {
  let config = discover_in(
    "/w",
    [("/w/acme.toml", "a = 1"), ("/w/acme.production.toml", "a = 2")],
    conventions=acme_envs(default="Production"),
  )
  @expect.expect(@config.get_text(config, "a")).to_equal("1")
  @expect.expect(
    report_of(config, EnvironmentFile).map(report => report.status),
  ).to_equal(Some(NotFound))
}

///|
test "Environment file without primary" {
  let config = discover_in(
    "/w/src",
    [("/w/acme.toml", "a = 1"), ("/w/src/acme.Production.toml", "a = 2")],
    conventions=acme_envs(default="Production"),
  )
  @expect.expect(report_of(config, Workspace).unwrap().path).to_equal(
    Some("/w/acme.toml"),
  )
  @expect.expect(@config.get_text(config, "a")).to_equal("1")
}

///|
test "environment files follow the layout of the primary" {
  let hidden = discover_in(
    "/w",
    [
      ("/w/.acme/acme.toml", "a = 1"),
      ("/w/.acme/acme.Production.toml", "a = 2"),
    ],
    conventions=acme_envs(default="Production"),
  )
  @expect.expect(@config.get_text(hidden, "a")).to_equal("2")
  let dot_config = discover_in(
    "/w",
    [
      ("/w/.config/acme/config.toml", "a = 1"),
      ("/w/.config/acme/config.Production.toml", "a = 2"),
    ],
    conventions=acme_envs(default="Production"),
  )
  @expect.expect(@config.get_text(dot_config, "a")).to_equal("2")
}

///|
test "two environment files for one primary are ambiguous" {
  let (_, candidates) = ambiguity(() => {
    discover_in(
      "/w",
      [
        ("/w/acme.toml", ""),
        ("/w/acme.Production.toml", ""),
        ("/w/acme.Production.yaml", ""),
      ],
      conventions=acme_envs(default="Production"),
      formats=[@toml.format(), yaml_only()],
    )
    |> ignore
  })
  @expect.expect(candidates).to_equal([
    "/w/acme.Production.toml", "/w/acme.Production.yaml",
  ])
}

///|
test "isolated mode keeps the environment file" {
  let config = discover_in(
    "/w",
    [("/w/acme.toml", "a = 1"), ("/w/acme.Production.toml", "a = 2")],
    conventions=acme_envs(default="Production"),
    options=@conventions.DiscoveryOptions::new(isolated=true),
  )
  @expect.expect(@config.get_text(config, "a")).to_equal("2")
}

///|
test "an explicit file in a standard layout has an environment file" {
  let config = discover_in(
    "/elsewhere",
    [
      ("/configs/acme.toml", "a = 1"),
      ("/configs/acme.Production.toml", "a = 2"),
    ],
    conventions=acme_envs(default="Production"),
    options=@conventions.DiscoveryOptions::new(
      config=Explicit("../configs/acme.toml"),
    ),
  )
  @expect.expect(@config.get_text(config, "a")).to_equal("2")
  let other = discover_in(
    "/w",
    [
      ("/w/configs/project.toml", "a = 1"),
      ("/w/configs/project.Production.toml", "a = 2"),
    ],
    conventions=acme_envs(default="Production"),
    options=@conventions.DiscoveryOptions::new(
      config=Explicit("configs/project.toml"),
    ),
  )
  @expect.expect(@config.get_text(other, "a")).to_equal("1")
  @expect.expect(report_of(other, EnvironmentFile)).to_equal(None)
}

///|
test "a legacy file has no environment file" {
  let config = discover_in(
    "/w",
    [("/w/acme.json", "{}"), ("/w/acme.Production.toml", "a = 2")],
    conventions=acme_envs(default="Production")
      |> @conventions.legacy("acme.json", format=yaml_stub(), decode=value => {
        @config.fields([("legacy", value)])
      }),
  )
  @expect.expect(report_of(config, EnvironmentFile)).to_equal(None)
}

///|
test "No environment file for global configuration" {
  let config = discover_in(
    "/w",
    [
      ("/home/test/.acme/acme.toml", "a = 1"),
      ("/home/test/.acme/acme.Production.toml", "a = 2"),
      ("/etc/acme/acme.Production.toml", "a = 3"),
    ],
    conventions=acme_envs(default="Production"),
    platform=Linux,
    env_vars={ "HOME": "/home/test" },
  )
  @expect.expect(@config.get_text(config, "a")).to_equal("1")
  @expect.expect(
    config
    .reports()
    .filter(report => report.status == Loaded)
    .map(report => report.path),
  ).to_equal([Some("/home/test/.acme/acme.toml")])
}

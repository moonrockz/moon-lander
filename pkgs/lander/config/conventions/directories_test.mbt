///|
/// The report of the file source with `role`, if there is one.
fn report_of(
  config : @config.Config,
  role : @config.FileRole,
) -> @config.SourceReport? {
  config.reports().iter().find_first(report => report.kind == File(role))
}

///|
fn global_report(config : @config.Config) -> @config.SourceReport {
  report_of(config, Global).unwrap()
}

///|
fn system_report(config : @config.Config) -> @config.SourceReport {
  report_of(config, System).unwrap()
}

///|
test "Linux system file" {
  let config = discover_in(
    "/w",
    [("/etc/acme/acme.toml", "machine = true"), ("/w/acme.toml", "a = 1")],
    platform=Linux,
    env_vars={},
  )
  let report = system_report(config)
  @expect.expect((report.priority, report.path, report.status)).to_equal((
    100,
    Some("/etc/acme/acme.toml"),
    Loaded,
  ))
  @expect.expect(@config.get_text(config, "machine")).to_equal("true")
}

///|
test "macOS system directory" {
  let config = discover_in("/w", [], platform=MacOs, env_vars={})
  @expect.expect(system_report(config).candidates).to_equal([
    "/etc/acme/acme.toml",
  ])
}

///|
test "Windows system directory fallback" {
  let config = discover_in("C:/w", [], platform=Windows, env_vars={})
  @expect.expect(system_report(config).candidates).to_equal([
    "C:/ProgramData/acme/acme.toml",
  ])
}

///|
test "Windows system directory from PROGRAMDATA" {
  let config = discover_in("C:/w", [], platform=Windows, env_vars={
    "PROGRAMDATA": "E:\\Data\\",
  })
  @expect.expect(system_report(config).candidates).to_equal([
    "E:/Data/acme/acme.toml",
  ])
}

///|
test "Absolute XDG directory used" {
  let config = discover_in(
    "/w",
    [],
    formats=[@toml.format(), yaml_only()],
    platform=Linux,
    env_vars={ "HOME": "/home/alice", "XDG_CONFIG_HOME": "/srv/alice/config" },
  )
  @expect.expect(global_report(config).candidates).to_equal([
    "/srv/alice/config/acme/acme.toml", "/srv/alice/config/acme/acme.yaml", "/home/alice/.acme/acme.toml",
    "/home/alice/.acme/acme.yaml",
  ])
}

///|
test "Relative XDG directory ignored" {
  let config = discover_in(
    "/w",
    [],
    formats=[yaml_only()],
    platform=Linux,
    env_vars={ "HOME": "/home/alice", "XDG_CONFIG_HOME": "config" },
  )
  @expect.expect(global_report(config).candidates[0]).to_equal(
    "/home/alice/.config/acme/acme.yaml",
  )
}

///|
test "macOS default directory" {
  let config = discover_in(
    "/w",
    [],
    formats=[yaml_only()],
    platform=MacOs,
    env_vars={ "HOME": "/Users/Alice" },
  )
  @expect.expect(global_report(config).candidates[0]).to_equal(
    "/Users/Alice/Library/Application Support/acme/acme.yaml",
  )
}

///|
test "Windows roaming directory" {
  let config = discover_in(
    "C:/w",
    [],
    formats=[yaml_only()],
    platform=Windows,
    env_vars={
      "APPDATA": "D:\\Profiles\\Alice\\Roaming",
      "XDG_CONFIG_HOME": "/srv/alice/config",
      "HOME": "/home/alice",
    },
  )
  // XDG_CONFIG_HOME and HOME have no effect on Windows.
  @expect.expect(global_report(config).candidates).to_equal([
    "D:/Profiles/Alice/Roaming/acme/acme.yaml",
  ])
}

///|
test "Default application home" {
  let config = discover_in("/w", [], platform=Linux, env_vars={
    "HOME": "/home/alice",
  })
  @expect.expect(global_report(config).candidates).to_equal([
    "/home/alice/.config/acme/acme.toml", "/home/alice/.acme/acme.toml",
  ])
}

///|
test "Relocated application home" {
  let config = discover_in("/w", [], platform=Linux, env_vars={
    "HOME": "/home/alice",
    "ACME_HOME": "/tmp/acme-home",
  })
  @expect.expect(global_report(config).candidates).to_equal([
    "/home/alice/.config/acme/acme.toml", "/tmp/acme-home/acme.toml",
  ])
}

///|
test "Windows user home" {
  let config = discover_in("C:/w", [], platform=Windows, env_vars={
    "USERPROFILE": "C:\\Users\\Alice",
    "HOME": "/home/alice",
  })
  @expect.expect(global_report(config).candidates).to_equal([
    "C:/Users/Alice/.acme/acme.toml",
  ])
}

///|
test "Empty home variable is unset" {
  let config = discover_in("/w", [], platform=Linux, env_vars={
    "HOME": "/home/alice",
    "ACME_HOME": "",
  })
  @expect.expect(global_report(config).candidates[1]).to_equal(
    "/home/alice/.acme/acme.toml",
  )
}

///|
test "a relative home variable joins the working directory" {
  let config = discover_in("/w/src", [], platform=Linux, env_vars={
    "ACME_HOME": "../home",
  })
  @expect.expect(global_report(config).candidates).to_equal([
    "/w/home/acme.toml",
  ])
}

///|
test "the application home uses the prefix of the convention set" {
  let config = discover_in(
    "/w",
    [],
    conventions=@conventions.app_dirs("acme", prefix="ACME_TOOL"),
    platform=Linux,
    env_vars={ "ACME_HOME": "/ignored", "ACME_TOOL_HOME": "/opt/acme" },
  )
  @expect.expect(global_report(config).candidates).to_equal([
    "/opt/acme/acme.toml",
  ])
}

///|
test "Directories come only from the given set" {
  let config = discover_in("/w", [], platform=Linux, env_vars={
    "HOME": "/home/test",
    "XDG_CONFIG_HOME": "/srv/test/config",
  })
  @expect.expect(global_report(config).candidates).to_equal([
    "/srv/test/config/acme/acme.toml", "/home/test/.acme/acme.toml",
  ])
}

///|
test "Two global files" {
  let (_, candidates) = ambiguity(() => {
    discover_in(
      "/w",
      [
        ("/home/alice/.config/acme/acme.toml", "a = 1"),
        ("/home/alice/.acme/acme.toml", "a = 2"),
      ],
      platform=Linux,
      env_vars={ "HOME": "/home/alice" },
    )
    |> ignore
  })
  @expect.expect(candidates).to_equal([
    "/home/alice/.config/acme/acme.toml", "/home/alice/.acme/acme.toml",
  ])
}

///|
test "Not-found global source lists candidates" {
  let config = discover_in("/w", [], platform=Linux, env_vars={
    "HOME": "/home/alice",
  })
  let report = global_report(config)
  @expect.expect((report.priority, report.status, report.candidates)).to_equal((
    200,
    NotFound,
    ["/home/alice/.config/acme/acme.toml", "/home/alice/.acme/acme.toml"],
  ))
}

///|
test "a global file loads below the project primary" {
  let config = discover_in(
    "/w",
    [("/home/alice/.acme/acme.toml", "a = 1\nb = 1"), ("/w/acme.toml", "a = 2")],
    platform=Linux,
    env_vars={ "HOME": "/home/alice" },
  )
  @expect.expect((
    @config.get_text(config, "a"),
    @config.get_text(config, "b"),
  )).to_equal(("2", "1"))
}

///|
test "isolated mode skips the system and global sources" {
  let config = discover_in(
    "/w",
    [("/etc/acme/acme.toml", "s = 1"), ("/home/alice/.acme/acme.toml", "g = 1")],
    options=@conventions.DiscoveryOptions::new(isolated=true),
    platform=Linux,
    env_vars={ "HOME": "/home/alice" },
  )
  @expect.expect((system_report(config).status, global_report(config).status)).to_equal((
    Skipped, Skipped,
  ))
  @expect.expect(config.warnings()).to_equal([])
}

///|
test "Windows absolute XDG check" {
  let config = discover_in("C:/w", [], platform=Windows, env_vars={
    "APPDATA": "D:\\Profiles\\Alice",
  })
  @expect.expect(global_report(config).candidates).to_equal([
    "D:/Profiles/Alice/acme/acme.toml",
  ])
}

///|
test "a UNC directory variable is absolute on Windows" {
  let config = discover_in("C:/w", [], platform=Windows, env_vars={
    "APPDATA": "\\\\server\\share\\Alice",
  })
  @expect.expect(global_report(config).candidates).to_equal([
    "//server/share/Alice/acme/acme.toml",
  ])
}

///|
test "app_dirs without the system part" {
  let config = discover_in(
    "/w",
    [("/etc/acme/acme.toml", "s = 1")],
    conventions=@conventions.app_dirs("acme") |> @conventions.without(SystemDir),
    platform=Linux,
    env_vars={},
  )
  @expect.expect(report_of(config, System)).to_equal(None)
  @expect.expect(report_of(config, Global) is Some(_)).to_equal(true)
}

///|
test "a base set with single parts" {
  let config = discover_in(
    "/w",
    [],
    conventions=@conventions.base("acme") |> @conventions.app_home,
    platform=Linux,
    env_vars={ "HOME": "/home/alice" },
  )
  @expect.expect(config.reports().map(report => report.kind)).to_equal([
    File(Global),
    File(Workspace),
  ])
  @expect.expect(global_report(config).candidates).to_equal([
    "/home/alice/.acme/acme.toml",
  ])
}

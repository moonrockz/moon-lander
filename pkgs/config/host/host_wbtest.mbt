///|
/// A provider that records the context it gets and adds no source.
fn recorder(seen : Ref[@config.LoadContext?]) -> @config.SourceProvider {
  {
    name: "recorder",
    expand: context => {
      seen.val = Some(context)
      Done({ sources: [], warnings: [] })
    },
  }
}

///|
/// The process variables without those that tests set. Async tests in this
/// package run at the same time and set and unset variables, so a test that
/// compares the full variable map leaves them out. A test that sets a variable
/// must give it a `LANDER_HOST_` or `APP_` prefix.
fn without_test_vars(vars : Map[String, String]) -> Map[String, String] {
  let kept : Map[String, String] = Map([])
  for name, value in vars {
    if !name.has_prefix("LANDER_HOST_") && !name.has_prefix("APP_") {
      kept[name] = value
    }
  }
  kept
}

///|
async test "Host adapter fills the inputs" {
  @env.set_env_var("LANDER_HOST_INPUT_A", "1")
  defer @env.unset_env_var("LANDER_HOST_INPUT_A")
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/app.toml", "project.name = \"disk\"")
  let seen = Ref(None)
  let config = @config.builder()
    |> @config.format(@toml.format())
    |> @config.file("\{dir}/app.toml")
    |> @config.env(prefix="LANDER_HOST_INPUT")
    |> @config.provider(recorder(seen))
    |> load
  @expect.expect(@config.get_text(config, "project.name")).to_equal("disk")
  @expect.expect(@config.get_text(config, "a")).to_equal("1")
  guard seen.val is Some(context) else { fail("the provider did not run") }
  @expect.expect(context.env_vars.get("LANDER_HOST_INPUT_A")).to_equal(Some("1"))
  // Another async test can set a variable between the load and the read below.
  // Do the same here, so the compare must leave it out on every run.
  @env.set_env_var("LANDER_HOST_INPUT_LATE", "1")
  defer @env.unset_env_var("LANDER_HOST_INPUT_LATE")
  @expect.expect(without_test_vars(context.env_vars)).to_equal(
    without_test_vars(@env.get_env_vars()),
  )
  @expect.expect(context.working_dir).to_equal(
    @env.current_dir().map(dir => to_slash(dir, running_platform())),
  )
  @expect.expect(context.platform).to_equal(Some(running_platform()))
}

///|
async test "Adapter uses the given values" {
  @env.set_env_var("APP_B", "2")
  defer @env.unset_env_var("APP_B")
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/conf/app.toml", "a = 1")
  let seen = Ref(None)
  let config = @config.builder()
    |> @config.env_vars({ "APP_A": "1" })
    |> @config.working_dir(dir)
    |> @config.platform(Linux)
    |> @config.format(@toml.format())
    |> @config.file("conf/app.toml")
    |> @config.env(prefix="APP")
    |> @config.provider(recorder(seen))
    |> load
  @expect.expect(@config.get_text(config, "a")).to_equal("1")
  @expect.expect(config.get(@config.KeyPath::parse("b"))).to_equal(None)
  @expect.expect(config.reports()[0].path).to_equal(Some("\{dir}/conf/app.toml"))
  guard seen.val is Some(context) else { fail("the provider did not run") }
  @expect.expect(context.env_vars).to_equal({ "APP_A": "1" })
  @expect.expect(context.platform).to_equal(Some(Linux))
}

///|
async test "Windows path in a report" {
  // `moon test` runs in the module directory, which holds `moon.mod`.
  let mod_format : @config.Format = {
    name: "module",
    extensions: ["mod"],
    parse: (_, _) => @config.fields([]),
  }
  let config = @config.builder()
    |> @config.format(mod_format)
    |> @config.file("moon.mod")
    |> load
  guard config.reports()[0].path is Some(path) else {
    fail("the report has no path")
  }
  @expect.expect(path.contains("\\")).to_equal(false)
  @expect.expect(path).to_equal(
    to_slash(@env.current_dir().unwrap_or("."), running_platform()) +
    "/moon.mod",
  )
}

///|
async test "a missing explicit file raises file-not-found" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.file("\{dir}/missing/app.toml")
  try load(builder) catch {
    @config.FileNotFound(path~) =>
      @expect.expect(path).to_equal("\{dir}/missing/app.toml")
    error => fail("expected file-not-found, got \{error}")
  } noraise {
    _ => fail("expected file-not-found")
  }
}

///|
async test "discovery finds the project file on the disk" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/acme.toml", "project.name = \"walked\"")
  write("\{dir}/src/nested/main.mbt", "")
  let config = @config.builder()
    |> @config.working_dir("\{dir}/src/nested")
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.app_dirs("acme"))
    |> load
  @expect.expect(@config.get_text(config, "project.name")).to_equal("walked")
  @expect.expect(config.origins(@config.KeyPath::parse("project.name"))[0].location).to_equal(
    Some("\{dir}/acme.toml"),
  )
}

///|
test "paths convert only on Windows" {
  assert_eq(to_slash("C:\\w\\app.toml", Windows), "C:/w/app.toml")
  assert_eq(from_slash("C:/w/app.toml", Windows), "C:\\w\\app.toml")
  assert_eq(to_slash("/w/a\\b", Linux), "/w/a\\b")
  assert_eq(from_slash("/w/app.toml", MacOs), "/w/app.toml")
}

///|
async test "a file that cannot be read is an error, not a missing file" {
  // Windows ignores the POSIX mode of a new directory.
  if running_platform() is Windows {
    return
  }
  let dir = temp_dir()
  defer remove_dir(dir)
  mkdir("\{dir}/locked", permission=0)
  // Restore access before recursive fixture cleanup.
  defer chmod("\{dir}/locked", 0o755)
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.file("\{dir}/locked/app.toml")
  try load(builder) catch {
    @config.FileNotFound(..) => fail("a permission error became file-not-found")
    _ => ()
  } noraise {
    _ => fail("expected the permission error")
  }
}

///|
async test "discovery does not skip a file it cannot inspect" {
  // Windows ignores POSIX modes.
  if running_platform() is Windows {
    return
  }
  let dir = temp_dir()
  defer remove_dir(dir)
  write("\{dir}/acme.toml", "project.name = \"hidden\"")
  // Read but no search permission: the listing works, a stat of an entry fails.
  chmod(dir, 0o444)
  defer chmod(dir, 0o755)
  let builder = @config.builder()
    |> @config.working_dir(dir)
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.app_dirs("acme"))
  try load(builder) catch {
    _ => ()
  } noraise {
    config =>
      fail("discovery skipped an entry it could not inspect: \{config.reports().length()} reports")
  }
}

///|
async test "Host adapter fills the inputs with a discovered environment source" {
  @env.set_env_var("LANDER_HOST_FILL_A", "1")
  defer @env.unset_env_var("LANDER_HOST_FILL_A")
  let config = @config.builder()
    |> @config.env(prefix="LANDER_HOST_FILL")
    |> load
  @expect.expect(@config.get_text(config, "a")).to_equal("1")
  @expect.expect(config.reports()[0].status).to_equal(Loaded)
}

///|
async test "Adapter uses the given variable set for a discovered environment source" {
  @env.set_env_var("LANDER_HOST_GIVEN_B", "2")
  defer @env.unset_env_var("LANDER_HOST_GIVEN_B")
  let config = @config.builder()
    |> @config.env_vars({ "LANDER_HOST_GIVEN_A": "1" })
    |> @config.env(prefix="LANDER_HOST_GIVEN")
    |> load
  @expect.expect(config.value()).to_equal(
    @config.fields([("a", @config.int(1))]),
  )
}

///|
async test "a boundary at the temporary root keeps a parent file out" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/acme.toml", "a = 1")
  write("\{dir}/case/.config/acme/config.toml", "b = 2")
  write("\{dir}/case/src/main.mbt", "")
  let config = @config.builder()
    |> @config.working_dir("\{dir}/case/src")
    |> @config.format(@toml.format())
    |> @conventions.add(
      @conventions.app_dirs("acme") |> @conventions.boundary("\{dir}/case"),
    )
    |> load
  @expect.expect(config.value()).to_equal(
    @config.fields([("b", @config.int(2))]),
  )
  let project = config
    .reports()
    .iter()
    .find_first(report => report.kind == File(Workspace))
  @expect.expect(project.map(report => report.path)).to_equal(
    Some(Some("\{dir}/case/.config/acme/config.toml")),
  )
}

///|
async test "discovery reads the global file and the overrides on the disk" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/home/.acme/acme.toml", "a = \"global\"\nb = \"global\"")
  write("\{dir}/case/acme.toml", "a = \"project\"")
  write("\{dir}/case/acme.user.toml", "c = \"user\"")
  // The variable set of the run, never the process environment, gives the
  // user home, so the real home of the test runner stays out.
  let config = @config.builder()
    |> @config.working_dir("\{dir}/case")
    |> @config.env_vars({ "HOME": "\{dir}/home", "USERPROFILE": "\{dir}/home" })
    |> @config.format(@toml.format())
    |> @conventions.add(
      @conventions.app_dirs("acme")
      |> @conventions.without(SystemDir)
      |> @conventions.boundary("\{dir}/case"),
    )
    |> load
  @expect.expect(config.value()).to_equal(
    @config.fields([
      ("a", @config.string("project")),
      ("b", @config.string("global")),
      ("c", @config.string("user")),
    ]),
  )
  @expect.expect(
    config.reports().map(report => (report.kind.report_name(), report.status)),
  ).to_equal([
    ("global", Loaded),
    ("project", Loaded),
    ("local-override", NotFound),
    ("user-override", Loaded),
  ])
}

///|
async test "discovery passes over an entry it cannot inspect" {
  // Windows needs a privilege for a symbolic link. The injected tests in
  // inspect_wbtest.mbt give the same failure on every platform.
  if running_platform() is Windows {
    return
  }
  let dir = temp_dir()
  defer remove_dir(dir)
  write("\{dir}/acme.toml", "project.name = \"found\"")
  write("\{dir}/src/main.mbt", "")
  // A link to itself: the listing holds it, and a stat of it fails (ELOOP).
  symlink(target="loop", "\{dir}/loop")
  symlink(target="loop", "\{dir}/src/loop")
  let config = @config.builder()
    |> @config.working_dir("\{dir}/src")
    |> @config.env_vars({})
    |> @config.format(@toml.format())
    |> @conventions.add(
      @conventions.app_dirs("acme") |> @conventions.without(SystemDir),
    )
    |> load
  @expect.expect(@config.get_text(config, "project.name")).to_equal("found")
}

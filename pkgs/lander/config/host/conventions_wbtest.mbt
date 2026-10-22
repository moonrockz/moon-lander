// Discovery through the host adapter on the disk. These tests run on native
// and js, also on the windows-latest CI leg, so they check the scenarios
// "Native adapter reads files", "js adapter reads files" and "Windows report
// paths" of the configuration conventions.

///|
/// The report of the project primary, or `None`.
fn project_report(config : @config.Config) -> @config.SourceReport? {
  config.reports().iter().find_first(report => report.kind == File(Workspace))
}

///|
async test "the adapter reads the project file that discovery finds" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/acme.toml", "project.name = \"on-disk\"")
  let config = @config.builder()
    |> @config.working_dir(dir)
    // An empty variable set keeps the home of the test runner out.
    |> @config.env_vars({})
    |> @config.format(@toml.format())
    |> @conventions.add(
      @conventions.app_dirs("acme")
      |> @conventions.without(SystemDir)
      |> @conventions.boundary(dir),
    )
    |> load
  guard project_report(config) is Some(report) else {
    fail("expected a project report")
  }
  @expect.expect((report.status, report.path)).to_equal((
    Loaded,
    Some("\{dir}/acme.toml"),
  ))
  @expect.expect(@config.get_text(config, "project.name")).to_equal("on-disk")
  // On Windows the adapter gives `/` paths, so no report shows `\`.
  for each in config.reports() {
    @expect.expect(each.path.unwrap_or("").contains("\\")).to_equal(false)
    @expect.expect(each.candidates.iter().any(path => path.contains("\\"))).to_equal(
      false,
    )
  }
}

///|
async test "the adapter answers the workspace requests of discovery" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write(
    "\{dir}/acme.toml",
    "workspace.members = [\"packages/*\"]\nui.theme = \"workspace\"",
  )
  write("\{dir}/packages/billing/acme.toml", "ui.theme = \"member\"")
  write("\{dir}/packages/billing/src/main.mbt", "")
  write("\{dir}/packages/orders/acme.toml", "ui.theme = \"orders\"")
  let config = @config.builder()
    |> @config.working_dir("\{dir}/packages/billing/src")
    // An empty variable set keeps the home of the test runner out.
    |> @config.env_vars({})
    |> @config.format(@toml.format())
    |> @conventions.add(
      @conventions.app_dirs("acme")
      |> @conventions.without(SystemDir)
      |> @conventions.workspace
      |> @conventions.boundary(dir),
    )
    |> load
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("member")
  let selected = config
    .reports()
    .iter()
    .find_first(report => report.kind == File(Member))
  @expect.expect(selected.map(report => report.path)).to_equal(
    Some(Some("\{dir}/packages/billing/acme.toml")),
  )
}

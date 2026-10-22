///|
/// A builder for `acme` with TOML and the YAML stand-in, a fixed platform
/// and a fixed variable set, so that every target gets the same inputs.
fn fixed_inputs(working_dir : String) -> @config.ConfigBuilder {
  @config.builder()
  |> @config.working_dir(working_dir)
  |> @config.platform(Linux)
  |> @config.env_vars({ "HOME": "/home/alice", "ACME_UI__THEME": "dark" })
  |> @config.format(@toml.format())
  |> @config.format(yaml_only())
  |> @conventions.add(
    @conventions.app_dirs("acme")
    |> @conventions.workspace
    |> @conventions.boundary("/w"),
  )
  |> @config.env(prefix="ACME")
}

///|
test "Missing entries requested" {
  // The tree holds the listings of the start directory, but not the listing
  // of its parent.
  let tree = @config.FileTree::new()
    .with_listing("/w/src", [])
    .with_missing("/w/src/.acme")
    .with_missing("/w/src/.config/acme")
  let builder = @config.builder()
    |> @config.working_dir("/w/src")
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.app_dirs("acme"))
  guard @config.load(builder, tree) is Need(requests) else {
    fail("a partial tree needs the parent listing")
  }
  @expect.expect(requests).to_equal([
    ListDir("/w"),
    ListDir("/w/.acme"),
    ListDir("/w/.config/acme"),
  ])
}

///|
test "Complete tree" {
  // The tree is complete and holds no entry for the working directory.
  let builder = @config.builder()
    |> @config.working_dir("/w/src")
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.app_dirs("acme"))
  guard @config.load(builder, @config.FileTree::new(complete=true))
    is Done(config) else {
    fail("a complete tree never asks for files")
  }
  @expect.expect(project(config).status).to_equal(NotFound)
}

///|
test "wasm uses injected tree" {
  let tree = @config.FileTree::new(complete=true)
    .with_listing("/w", [{ name: "acme.toml", kind: File }])
    .with_file("/w/acme.toml", "project.name = \"injected\"")
  let builder = @config.builder()
    |> @config.working_dir("/w")
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.app_dirs("acme"))
  guard @config.load(builder, tree) is Done(config) else {
    fail("a complete tree never asks for files")
  }
  @expect.expect(project(config).path).to_equal(Some("/w/acme.toml"))
  @expect.expect(@config.get_text(config, "project.name")).to_equal("injected")
}

///|
test "Same result on all targets" {
  let files = [
    ("/home/alice/.config/acme/acme.yaml", "global: 1"),
    ("/w/acme.toml", "workspace.members = [\"packages/*\"]\nui.theme = \"w\""),
    ("/w/acme.user.toml", "ui.font = \"mono\""),
    ("/w/packages/billing/acme.toml", "ui.theme = \"b\""),
    ("/w/packages/billing/src/main.mbt", ""),
  ]
  let config = load_from(
    fixed_inputs("/w/packages/billing/src"),
    Map::from_array(files),
  )
  @expect.expect(
    config
    .reports()
    .map(report => {
      (
        report.kind.report_name(),
        report.priority,
        report.path,
        report.candidates.length(),
        report.status,
      )
    }),
  ).to_equal([
    ("system", 100, None, 2, NotFound),
    ("global", 200, Some("/home/alice/.config/acme/acme.yaml"), 4, Loaded),
    ("project", 300, Some("/w/acme.toml"), 6, Loaded),
    ("workspace-member", 350, Some("/w/packages/billing/acme.toml"), 6, Loaded),
    ("local-override", 390, None, 2, NotFound),
    ("local-override", 390, None, 2, NotFound),
    ("user-override", 400, Some("/w/acme.user.toml"), 2, Loaded),
    ("user-override", 400, None, 2, NotFound),
    ("environment", 600, None, 0, Loaded),
  ])
  @expect.expect(
    (
      @config.get_text(config, "ui.theme"),
      @config.get_text(config, "ui.font"),
    ),
  ).to_equal(("dark", "mono"))
  let error = try
    load_from(
      fixed_inputs("/w"),
      Map::from_array([("/w/acme.toml", ""), ("/w/acme.yaml", "")]),
    )
    |> ignore
  catch {
    error => error.message()
  } noraise {
    _ => ""
  }
  @expect.expect(error).to_equal(
    "Ambiguous acme configuration; found: /w/acme.toml, /w/acme.yaml",
  )
}

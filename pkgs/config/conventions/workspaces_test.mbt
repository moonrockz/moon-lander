///|
/// The standard set with workspaces on.
fn acme_workspace() -> @conventions.Conventions {
  @conventions.app_dirs("acme") |> @conventions.workspace
}

///|
/// The report of the selected member, or `None` when no member source loads.
fn member_report(config : @config.Config) -> @config.SourceReport? {
  config.reports().iter().find_first(report => report.kind == File(Member))
}

///|
/// The kind, priority, path and status of each project-tier report.
fn report_rows(
  config : @config.Config,
) -> Array[(@config.SourceKind, Int, String?, @config.SourceStatus)] {
  config
  .reports()
  .filter(report => !(report.kind is File(System | Global)))
  .map(report => (report.kind, report.priority, report.path, report.status))
}

///|
/// The messages of the `Note` warnings.
fn note_messages(config : @config.Config) -> Array[String] {
  config
  .warnings()
  .filter_map(warning => {
    guard warning is Note(message~, ..) else { None }
    Some(message)
  })
}

///|
fn workspace_in(
  start : String,
  files : Array[(String, String)],
  conventions? : @conventions.Conventions = acme_workspace(),
  options? : @conventions.DiscoveryOptions = @conventions.DiscoveryOptions::new(),
) -> @config.Config raise @config.ConfigError {
  discover_in(start, files, conventions~, options~)
}

///|
test "Member found from inside the member" {
  let config = workspace_in("/w/packages/billing/src", [
    ("/w/acme.toml", "workspace.members = [\"packages/*\"]"),
    ("/w/packages/billing/acme.toml", "project.name = \"billing\""),
    ("/w/packages/billing/src/main.mbt", ""),
  ])
  @expect.expect(report_rows(config)).to_equal([
    (File(Workspace), 300, Some("/w/acme.toml"), Loaded),
    (File(Member), 350, Some("/w/packages/billing/acme.toml"), Loaded),
    (File(LocalOverride), 390, None, NotFound),
    (File(LocalOverride), 390, None, NotFound),
    (File(UserOverride), 400, None, NotFound),
    (File(UserOverride), 400, None, NotFound),
  ])
}

///|
test "Ambiguous ancestor is passed over" {
  let config = discover_in(
    "/w/mid/proj",
    [
      ("/w/acme.toml", "workspace.members = [\"mid/proj\"]"),
      ("/w/mid/acme.toml", ""),
      ("/w/mid/acme.yaml", ""),
      ("/w/mid/proj/acme.toml", "a = 1"),
    ],
    conventions=acme_workspace(),
    formats=[@toml.format(), yaml_only()],
  )
  @expect.expect(primary_path(config)).to_equal(Some("/w/acme.toml"))
  @expect.expect(member_report(config).map(report => report.path)).to_equal(
    Some(Some("/w/mid/proj/acme.toml")),
  )
}

///|
test "an ancestor that does not parse is passed over" {
  let config = workspace_in("/w/a/proj", [
    ("/w/acme.toml", "workspace.members = [\"a/proj\"]"),
    ("/w/a/acme.toml", "this is not toml"),
    ("/w/a/proj/acme.toml", "a = 1"),
  ])
  @expect.expect(primary_path(config)).to_equal(Some("/w/acme.toml"))
}

///|
test "an ancestor that is not a workspace is passed over" {
  let config = workspace_in("/w/a/proj", [
    ("/w/acme.toml", "workspace.members = [\"a/proj\"]"),
    ("/w/a/acme.toml", "project.name = \"a\""),
    ("/w/a/proj/acme.toml", "a = 1"),
  ])
  @expect.expect(primary_path(config)).to_equal(Some("/w/acme.toml"))
}

///|
test "Excluded member stays standalone" {
  let config = workspace_in("/w/packages/legacy", [
    (
      "/w/acme.toml",
      "workspace.members = [\"packages/*\"]\nworkspace.exclude = [\"packages/legacy\"]",
    ),
    ("/w/packages/legacy/acme.toml", "a = 1"),
  ])
  @expect.expect(primary_path(config)).to_equal(
    Some("/w/packages/legacy/acme.toml"),
  )
  @expect.expect(member_report(config)).to_equal(None)
  @expect.expect(config.value()).to_equal(
    @config.fields([("a", @config.int(1))]),
  )
}

///|
test "the enclosing-workspace search obeys the boundary" {
  let config = workspace_in(
    "/w/case/proj",
    [
      ("/w/acme.toml", "workspace.members = [\"case/proj\"]"),
      ("/w/case/proj/acme.toml", "a = 1"),
    ],
    conventions=acme_workspace() |> @conventions.boundary("/w/case"),
  )
  @expect.expect(primary_path(config)).to_equal(Some("/w/case/proj/acme.toml"))
  @expect.expect(member_report(config)).to_equal(None)
}

///|
test "a wildcard member does not match a deeper directory" {
  let config = workspace_in("/w/packages/billing/core", [
    ("/w/acme.toml", "workspace.members = [\"packages/*\"]"),
    ("/w/packages/billing/acme.toml", "a = 1"),
    ("/w/packages/billing/core/acme.toml", "b = 1"),
  ])
  @expect.expect(primary_path(config)).to_equal(
    Some("/w/packages/billing/core/acme.toml"),
  )
  @expect.expect(member_report(config)).to_equal(None)
}

///|
test "a multi-segment wildcard member matches a deeper directory" {
  let config = workspace_in("/w/packages/billing/core", [
    ("/w/acme.toml", "workspace.members = [\"packages/**\"]"),
    ("/w/packages/billing/core/acme.toml", "b = 1"),
  ])
  @expect.expect(primary_path(config)).to_equal(Some("/w/acme.toml"))
  @expect.expect(member_report(config).map(report => report.path)).to_equal(
    Some(Some("/w/packages/billing/core/acme.toml")),
  )
}

///|
test "Listed member is missing" {
  let config = discover_in(
    "/w",
    [
      (
        "/w/acme.toml",
        "workspace.members = [\"members/alpha\"]\nworkspace.default_member = \"members/alpha\"",
      ),
    ],
    conventions=acme_workspace(),
    formats=[@toml.format(), yaml_only()],
  )
  guard member_report(config) is Some(report) else {
    fail("expected a member report")
  }
  @expect.expect((report.status, report.candidates)).to_equal((
    NotFound,
    [
      "/w/members/alpha/acme.toml", "/w/members/alpha/acme.yaml", "/w/members/alpha/.acme/acme.toml",
      "/w/members/alpha/.acme/acme.yaml", "/w/members/alpha/.config/acme/config.toml",
      "/w/members/alpha/.config/acme/config.yaml",
    ],
  ))
}

///|
test "Escaping entry skipped" {
  let config = workspace_in("/w", [
    ("/w/acme.toml", "workspace.members = [\"../outside\", \"packages/*\"]"),
    ("/w/packages/orders/acme.toml", "a = 1"),
    ("/outside/acme.toml", "b = 1"),
  ])
  @expect.expect(note_messages(config)).to_equal([
    no_platform, "discovery skips the workspace entry ../outside, because it is not in the workspace directory",
  ])
  @expect.expect(member_report(config).map(report => report.path)).to_equal(
    Some(Some("/w/packages/orders/acme.toml")),
  )
}

///|
test "an exclude entry outside the workspace is skipped" {
  let config = workspace_in("/w", [
    (
      "/w/acme.toml",
      "workspace.members = [\"packages/*\"]\nworkspace.exclude = [\"/packages/billing\"]",
    ),
    ("/w/packages/billing/acme.toml", "a = 1"),
  ])
  @expect.expect(note_messages(config)).to_equal([
    no_platform, "discovery skips the workspace entry /packages/billing, because it is not in the workspace directory",
  ])
  @expect.expect(member_report(config).map(report => report.path)).to_equal(
    Some(Some("/w/packages/billing/acme.toml")),
  )
}

///|
test "Backslash member entry rejected" {
  let config = discover_in(
    "/w",
    [
      ("/w/acme.toml", "workspace.members = [\"packages\\\\billing\"]"),
      ("/w/packages/billing/acme.toml", "a = 1"),
    ],
    conventions=acme_workspace(),
    platform=Linux,
  )
  @expect.expect(
    note_messages(config).contains(
      "discovery skips the workspace entry packages\\billing, because it is not in the workspace directory",
    ),
  ).to_equal(true)
  @expect.expect(member_report(config)).to_equal(None)
}

///|
test "Root is not its own member" {
  let alone = workspace_in("/w", [("/w/acme.toml", "workspace.members = [\"**\"]")])
  @expect.expect(member_report(alone)).to_equal(None)
  let config = workspace_in("/w", [
    ("/w/acme.toml", "workspace.members = [\"**\"]"),
    ("/w/packages/orders/acme.toml", "a = 1"),
  ])
  @expect.expect(member_report(config).map(report => report.path)).to_equal(
    Some(Some("/w/packages/orders/acme.toml")),
  )
}

///|
test "a wildcard never enters a hidden directory" {
  let config = workspace_in("/w", [
    ("/w/acme.toml", "workspace.members = [\"*\"]"),
    ("/w/.cache/acme.toml", "a = 1"),
  ])
  @expect.expect(member_report(config)).to_equal(None)
}

///|
test "Default member selected" {
  let config = workspace_in("/w", [
    (
      "/w/acme.toml",
      "workspace.members = [\"packages/*\"]\nworkspace.default_member = \"packages/billing\"",
    ),
    ("/w/packages/billing/acme.toml", "a = 1"),
    ("/w/packages/orders/acme.toml", "b = 1"),
  ])
  @expect.expect(member_report(config).map(report => report.path)).to_equal(
    Some(Some("/w/packages/billing/acme.toml")),
  )
}

///|
test "Single member selected" {
  let config = workspace_in("/w", [
    ("/w/acme.toml", "workspace.members = [\"packages/*\"]"),
    ("/w/packages/orders/acme.toml", "a = 1"),
    ("/w/packages/scratch/notes.txt", ""),
  ])
  @expect.expect(member_report(config).map(report => report.path)).to_equal(
    Some(Some("/w/packages/orders/acme.toml")),
  )
}

///|
test "Several members and no default" {
  let config = workspace_in("/w", [
    ("/w/acme.toml", "workspace.members = [\"packages/*\"]"),
    ("/w/packages/billing/acme.toml", "a = 1"),
    ("/w/packages/orders/acme.toml", "b = 1"),
  ])
  @expect.expect(member_report(config)).to_equal(None)
}

///|
test "Default member names the root" {
  let config = workspace_in("/w", [
    (
      "/w/acme.toml",
      "workspace.members = [\"packages/*\"]\nworkspace.default_member = \".\"",
    ),
    ("/w/packages/orders/acme.toml", "a = 1"),
  ])
  @expect.expect(member_report(config)).to_equal(None)
}

///|
test "a default member outside the workspace gives a warning and no member" {
  let config = workspace_in("/w", [
    (
      "/w/acme.toml",
      "workspace.members = [\"packages/*\"]\nworkspace.default_member = \"../other\"",
    ),
    ("/w/packages/orders/acme.toml", "a = 1"),
  ])
  @expect.expect(member_report(config)).to_equal(None)
  @expect.expect(note_messages(config)).to_equal([
    no_platform, "discovery skips the workspace entry ../other, because it is not in the workspace directory",
  ])
}

///|
test "a member that holds the start directory is selected first" {
  let config = workspace_in("/w/members/alpha/src", [
    (
      "/w/acme.toml",
      "workspace.members = [\"members/alpha\", \"members/beta\"]\nworkspace.default_member = \"members/beta\"",
    ),
    ("/w/members/alpha/src/main.mbt", ""),
    ("/w/members/beta/acme.toml", "a = 1"),
  ])
  guard member_report(config) is Some(report) else {
    fail("expected a member report")
  }
  @expect.expect((report.status, report.candidates[0])).to_equal((
    NotFound, "/w/members/alpha/acme.toml",
  ))
}

///|
test "the workspace keys come from the global file and the primary" {
  let config = discover_in(
    "/w",
    [
      ("/home/alice/.acme/acme.toml", "workspace.default_member = \"packages/orders\""),
      ("/w/acme.toml", "workspace.members = [\"packages/*\"]"),
      ("/w/packages/billing/acme.toml", "a = 1"),
      ("/w/packages/orders/acme.toml", "b = 1"),
    ],
    conventions=acme_workspace(),
    platform=Linux,
    env_vars={ "HOME": "/home/alice" },
  )
  @expect.expect(member_report(config).map(report => report.path)).to_equal(
    Some(Some("/w/packages/orders/acme.toml")),
  )
}

///|
test "the key paths of the workspace come from the application" {
  let conventions = @conventions.app_dirs("acme")
    |> @conventions.workspace(
      members="build.modules",
      default_member="build.main",
      exclude="build.skip",
      project_name="app.id",
    )
  let config = workspace_in(
    "/w",
    [
      ("/w/acme.toml", "build.modules = [\"mods/*\"]\nbuild.main = \"mods/b\""),
      ("/w/mods/a/acme.toml", "app.id = \"a\""),
      ("/w/mods/b/acme.toml", "app.id = \"b\""),
    ],
    conventions~,
  )
  @expect.expect(member_report(config).map(report => report.path)).to_equal(
    Some(Some("/w/mods/b/acme.toml")),
  )
  let named = workspace_in(
    "/w",
    [
      ("/w/acme.toml", "build.modules = [\"mods/*\"]"),
      ("/w/mods/a/acme.toml", "app.id = \"a\""),
      ("/w/mods/b/acme.toml", "app.id = \"b\""),
    ],
    conventions~,
    options=@conventions.DiscoveryOptions::new(project="a"),
  )
  @expect.expect(member_report(named).map(report => report.path)).to_equal(
    Some(Some("/w/mods/a/acme.toml")),
  )
}

///|
/// A workspace with two members that set the project names `billing` and
/// `orders`.
let two_members : Array[(String, String)] = [
  ("/w/acme.toml", "workspace.members = [\"packages/*\"]\nproject.name = \"root\""),
  ("/w/packages/billing/acme.toml", "project.name = \"billing\""),
  ("/w/packages/orders/acme.toml", "project.name = \"orders\""),
]

///|
fn select_project(
  selector : String,
  files? : Array[(String, String)] = two_members,
  start? : String = "/w",
) -> @config.Config raise @config.ConfigError {
  workspace_in(
    start,
    files,
    options=@conventions.DiscoveryOptions::new(project=selector),
  )
}

///|
test "Selection by path" {
  let config = select_project("packages/billing")
  @expect.expect(member_report(config).map(report => report.path)).to_equal(
    Some(Some("/w/packages/billing/acme.toml")),
  )
  let trailing = select_project("packages/billing/")
  @expect.expect(member_report(trailing).map(report => report.path)).to_equal(
    Some(Some("/w/packages/billing/acme.toml")),
  )
}

///|
test "selection by name" {
  let config = select_project("orders")
  @expect.expect(member_report(config).map(report => report.path)).to_equal(
    Some(Some("/w/packages/orders/acme.toml")),
  )
}

///|
test "the selector . and the root name select the root project" {
  for selector in [".", "root"] {
    let config = select_project(selector)
    @expect.expect(member_report(config)).to_equal(None)
    @expect.expect(primary_path(config)).to_equal(Some("/w/acme.toml"))
  }
}

///|
test "a selector wins over the enclosing member" {
  let config = select_project("orders", start="/w/packages/billing")
  @expect.expect(primary_path(config)).to_equal(Some("/w/acme.toml"))
  @expect.expect(member_report(config).map(report => report.path)).to_equal(
    Some(Some("/w/packages/orders/acme.toml")),
  )
}

///|
test "Ambiguous name" {
  let files = [
    ("/w/acme.toml", "workspace.members = [\"packages/*\"]"),
    ("/w/packages/a/acme.toml", "project.name = \"orders\""),
    ("/w/packages/b/acme.toml", "project.name = \"orders\""),
  ]
  try select_project("orders", files~) catch {
    AmbiguousProject(selector~, matches~) as error => {
      @expect.expect((selector, matches)).to_equal((
        "orders",
        ["packages/a", "packages/b"],
      ))
      @expect.expect(error.message()).to_equal(
        "More than one project matches orders: packages/a, packages/b; select a member by its path",
      )
    }
    error => fail("expected AmbiguousProject, got \{error.message()}")
  } noraise {
    _ => fail("expected AmbiguousProject")
  }
}

///|
test "Unknown project" {
  try select_project("missing") catch {
    UnknownProject(selector~, workspace~) =>
      @expect.expect((selector, workspace)).to_equal(("missing", "/w"))
    error => fail("expected UnknownProject, got \{error.message()}")
  } noraise {
    _ => fail("expected UnknownProject")
  }
}

///|
test "a selector with no project file is an unknown project" {
  try select_project("orders", files=[("/w/readme.txt", "")]) catch {
    UnknownProject(selector~, workspace~) =>
      @expect.expect((selector, workspace)).to_equal(("orders", "/w"))
    error => fail("expected UnknownProject, got \{error.message()}")
  } noraise {
    _ => fail("expected UnknownProject")
  }
}

///|
/// A workspace with the member `packages/billing` and the overrides that
/// `files` adds.
fn layered(
  extra : Array[(String, String)],
  conventions? : @conventions.Conventions = acme_workspace(),
) -> @config.Config raise @config.ConfigError {
  workspace_in(
    "/w/packages/billing",
    [
      (
        "/w/acme.toml",
        "workspace.members = [\"packages/*\"]\nui.theme = \"workspace\"",
      ),
      ("/w/packages/billing/acme.toml", "ui.theme = \"member\""),
      ..extra,
    ],
    conventions~,
  )
}

///|
test "Member user override wins last" {
  let config = layered([
    ("/w/acme.user.toml", "ui.theme = \"workspace-user\""),
    ("/w/packages/billing/acme.user.toml", "ui.theme = \"member-user\""),
  ])
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("member-user")
}

///|
test "Member local override order" {
  let locals = [
    ("/w/acme.local.toml", "ui.theme = \"workspace-local\""),
    ("/w/packages/billing/acme.local.toml", "ui.theme = \"member-local\""),
  ]
  let config = layered([
    ..locals,
    ("/w/acme.user.toml", "ui.theme = \"workspace-user\""),
  ])
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal(
    "workspace-user",
  )
  @expect.expect(@config.get_text(layered(locals), "ui.theme")).to_equal(
    "member-local",
  )
}

///|
test "Member primary wins over workspace primary" {
  let config = layered([])
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("member")
}

///|
test "the project tier loads in the documented order" {
  let config = layered(
    [
      ("/w/acme.Production.toml", "a = 1"),
      ("/w/packages/billing/acme.Production.toml", "b = 1"),
      ("/w/acme.local.toml", "c = 1"),
      ("/w/packages/billing/acme.local.toml", "d = 1"),
      ("/w/acme.user.toml", "e = 1"),
      ("/w/packages/billing/acme.user.toml", "f = 1"),
    ],
    conventions=acme_workspace() |> @conventions.environments(default="Production"),
  )
  @expect.expect(report_rows(config)).to_equal([
    (File(Workspace), 300, Some("/w/acme.toml"), Loaded),
    (File(Member), 350, Some("/w/packages/billing/acme.toml"), Loaded),
    (File(EnvironmentFile), 375, Some("/w/acme.Production.toml"), Loaded),
    (
      File(EnvironmentFile),
      375,
      Some("/w/packages/billing/acme.Production.toml"),
      Loaded,
    ),
    (File(LocalOverride), 390, Some("/w/acme.local.toml"), Loaded),
    (
      File(LocalOverride),
      390,
      Some("/w/packages/billing/acme.local.toml"),
      Loaded,
    ),
    (File(UserOverride), 400, Some("/w/acme.user.toml"), Loaded),
    (File(UserOverride), 400, Some("/w/packages/billing/acme.user.toml"), Loaded),
  ])
}

///|
test "Reports in merge order" {
  let config = @config.builder()
    |> @config.working_dir("/w")
    |> @config.env_vars({ "ACME_A": "1" })
    |> @config.format(@toml.format())
    |> @config.defaults({ "a": 0 })
    |> @conventions.add(@conventions.base("acme") |> @conventions.layouts)
    |> @config.env(prefix="ACME")
    |> @config.load(disk([("/w/acme.toml", "a = 2")]))
    |> done
  @expect.expect(
    config.reports().map(report => (report.kind, report.priority)),
  ).to_equal([(Defaults, 0), (File(Workspace), 300), (Environment, 600)])
}

///|
test "Member roles" {
  let config = layered([])
  @expect.expect(
    config
    .reports()
    .filter(report => report.kind is File(Workspace | Member))
    .map(report => (report.kind, report.priority)),
  ).to_equal([(File(Workspace), 300), (File(Member), 350)])
}

///|
test "an explicit file inside a member is the member primary" {
  let config = workspace_in(
    "/w",
    [
      ("/w/acme.toml", "workspace.members = [\"packages/*\"]"),
      ("/w/packages/billing/acme.toml", "a = 1"),
    ],
    options=@conventions.DiscoveryOptions::new(
      config=Explicit("packages/billing/acme.toml"),
    ),
  )
  @expect.expect(report_rows(config)[:2].to_owned()).to_equal([
    (File(Workspace), 300, Some("/w/acme.toml"), Loaded),
    (File(Member), 350, Some("/w/packages/billing/acme.toml"), Loaded),
  ])
}

///|
test "a legacy member primary has no overrides" {
  let conventions = acme_workspace()
    |> @conventions.legacy(
      "acme.json",
      format={
        name: "Legacy JSON",
        extensions: ["json"],
        parse: (text, _) => @config.fields([("text", @config.string(text))]),
      },
      decode=value => value,
    )
  let config = workspace_in(
    "/w",
    [
      ("/w/acme.toml", "workspace.members = [\"packages/old\"]"),
      ("/w/packages/old/acme.json", "{}"),
      ("/w/packages/old/acme.user.toml", "a = 1"),
    ],
    conventions~,
  )
  @expect.expect(report_rows(config)).to_equal([
    (File(Workspace), 300, Some("/w/acme.toml"), Loaded),
    (File(Member), 350, Some("/w/packages/old/acme.json"), Loaded),
    (File(LocalOverride), 390, None, NotFound),
    (File(UserOverride), 400, None, NotFound),
  ])
}

///|
test "workspace discovery asks for entries round by round" {
  let disk = {
    "/w/acme.toml": "workspace.members = [\"packages/*\"]\nui.theme = \"w\"",
    "/w/packages/billing/acme.toml": "ui.theme = \"b\"",
    "/w/packages/billing/src/main.mbt": "",
  }
  let config = load_from(
    @config.builder()
    |> @config.working_dir("/w/packages/billing/src")
    |> @config.format(@toml.format())
    |> @conventions.add(acme_workspace()),
    disk,
  )
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("b")
  @expect.expect(member_report(config).map(report => report.status)).to_equal(
    Some(Loaded),
  )
}

///|
test "Member cannot set a workspace key" {
  let conventions = acme_workspace()
    |> @conventions.member_scope_keys(["workspace.out_dir"])
  let config = workspace_in(
    "/w/packages/billing",
    [
      (
        "/w/acme.toml",
        "workspace.members = [\"packages/*\"]\nworkspace.out_dir = \"out\"",
      ),
      ("/w/packages/billing/acme.toml", "workspace.out_dir = \"mine\"\na = 1"),
    ],
    conventions~,
  )
  @expect.expect(@config.get_text(config, "workspace.out_dir")).to_equal("out")
  guard member_report(config) is Some(report) else {
    fail("expected a member report")
  }
  guard report.warnings is [KeyRemoved(key, origin)] else {
    fail("expected one KeyRemoved warning")
  }
  @expect.expect((key.to_string(), origin.kind, origin.location)).to_equal((
    "workspace.out_dir",
    File(Member),
    Some("/w/packages/billing/acme.toml"),
  ))
  @expect.expect(
    config
    .origins(@config.KeyPath::parse("workspace.out_dir"))
    .map(origin => origin.location),
  ).to_equal([Some("/w/acme.toml")])
}

///|
test "member-scope keys leave the workspace layers complete" {
  let conventions = acme_workspace()
    |> @conventions.member_scope_keys(["workspace.out_dir"])
  let config = workspace_in(
    "/w",
    [("/w/acme.toml", "workspace.out_dir = \"out\"")],
    conventions~,
  )
  @expect.expect(@config.get_text(config, "workspace.out_dir")).to_equal("out")
}

///|
fn inherited() -> @conventions.Conventions {
  acme_workspace() |> @conventions.inherited_filter(["project", "workspace"])
}

///|
test "Workspace project table not inherited" {
  let config = workspace_in(
    "/w/packages/billing",
    [
      (
        "/w/acme.toml",
        "workspace.members = [\"packages/*\"]\nproject.name = \"root\"",
      ),
      ("/w/packages/billing/acme.toml", "a = 1"),
    ],
    conventions=inherited(),
  )
  @expect.expect(config.get(@config.KeyPath::parse("project.name"))).to_equal(
    None,
  )
  @expect.expect(project(config).warnings).to_equal([])
}

///|
test "Shared table inherited" {
  let config = workspace_in(
    "/w/packages/billing",
    [
      ("/w/acme.toml", "workspace.members = [\"packages/*\"]\nui.theme = \"dark\""),
      ("/w/packages/billing/acme.toml", "project.name = \"billing\""),
    ],
    conventions=inherited(),
  )
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("dark")
  @expect.expect(@config.get_text(config, "project.name")).to_equal("billing")
}

///|
test "the inherited filter covers the machine and workspace override layers" {
  let config = discover_in(
    "/w/packages/billing",
    [
      ("/etc/acme/acme.toml", "project.kind = \"system\""),
      ("/w/acme.toml", "workspace.members = [\"packages/*\"]"),
      ("/w/acme.user.toml", "project.owner = \"me\"\nui.theme = \"dark\""),
      ("/w/packages/billing/acme.toml", "a = 1"),
    ],
    conventions=inherited(),
    platform=Linux,
  )
  @expect.expect(config.value()).to_equal(
    @config.fields([
      ("a", @config.int(1)),
      ("ui", @config.fields([("theme", @config.string("dark"))])),
    ]),
  )
}

///|
test "the inherited filter keeps the root project without a member" {
  let config = workspace_in(
    "/w",
    [("/w/acme.toml", "project.name = \"root\"")],
    conventions=inherited(),
  )
  @expect.expect(@config.get_text(config, "project.name")).to_equal("root")
}

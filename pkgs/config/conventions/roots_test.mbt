///|
fn workspace_first() -> @conventions.Conventions raise @config.ConfigError {
  acme_workspace() |> @conventions.root_policy(WorkspaceFirst(@config.KeyPath::parse("workspace")))
}

///|
test "workspace-first inspects the nearest file and stops at an empty workspace" {
  let config = workspace_in("/outer/inner/sub", [
    ("/outer/acme.toml", "broken=["),
    ("/outer/inner/acme.toml", "[workspace]"),
    ("/outer/inner/sub/acme.toml", "project.name='sub'"),
  ], conventions=workspace_first())
  assert_eq(primary_path(config), Some("/outer/inner/acme.toml"))
  assert_eq(member_report(config), None)
  let own = workspace_in("/outer/inner", [
    ("/outer/acme.toml", "workspace.members=['inner']\nouter=true"),
    ("/outer/inner/acme.toml", "[workspace]"),
  ], conventions=workspace_first())
  assert_eq(primary_path(own), Some("/outer/inner/acme.toml"))
}

///|
test "workspace-first retains nearest project fallback and honors the boundary" {
  let files = [("/w/acme.toml", "[workspace]"), ("/w/a/acme.toml", "project.name='a'"), ("/w/a/b/acme.toml", "project.name='b'")]
  let config = workspace_in("/w/a/b/src", files, conventions=workspace_first() |> @conventions.boundary("/w/a"))
  assert_eq(primary_path(config), Some("/w/a/b/acme.toml"))
  assert_eq(@config.get_text(config, "project.name"), "b")
  try {
    ignore(workspace_in("/elsewhere", files, conventions=workspace_first() |> @conventions.boundary("/w")))
    fail("outside boundary accepted")
  } catch { @config.OutsideBoundary(..) => (); error => raise error }
}

///|
test "nearest workspace remains selected when it excludes the project" {
  let config = workspace_in("/w/inner/member", [
    ("/w/acme.toml", "workspace.members=['inner/member']\nouter=true"),
    ("/w/inner/acme.toml", "workspace.members=['*']\nworkspace.exclude=['member']\ninner=true"),
    ("/w/inner/member/acme.toml", "project.name='excluded'"),
  ], conventions=workspace_first())
  assert_eq(primary_path(config), Some("/w/inner/acme.toml"))
  assert_eq(member_report(config), None)
}

///|
test "workspace-first loads a member normally and can leave all members to its caller" {
  let files = [("/w/acme.toml", "workspace.members=['a']\nbase=true"), ("/w/a/acme.toml", "project.name='a'")]
  let config = workspace_in("/w/a/src", files, conventions=workspace_first())
  assert_eq(primary_path(config), Some("/w/acme.toml"))
  assert_eq(member_report(config).map(report => report.path), Some(Some("/w/a/acme.toml")))
  let root = workspace_in("/w/a/src", files, conventions=workspace_first() |> @conventions.member_loading(ExplicitOnly))
  assert_eq(primary_path(root), Some("/w/acme.toml"))
  assert_eq(member_report(root), None)
  let explicit = workspace_in("/w", files, conventions=workspace_first() |> @conventions.member_loading(ExplicitOnly), options=@conventions.DiscoveryOptions::new(project="a"))
  assert_eq(member_report(explicit).map(report => report.path), Some(Some("/w/a/acme.toml")))
}

///|
test "workspace-first exposes examined parse and ambiguity errors" {
  try {
    ignore(workspace_in("/w/a", [("/w/acme.toml", "broken=["), ("/w/a/acme.toml", "project.name='a'")], conventions=workspace_first()))
    fail("parse failure hidden")
  } catch { @config.Parse(..) => (); error => raise error }
  let (location, paths) = ambiguity(() => ignore(discover_in("/w/a", [
    ("/w/acme.toml", "[workspace]"), ("/w/acme.yaml", "workspace: {}"), ("/w/a/acme.toml", "a=1"),
  ], conventions=workspace_first(), formats=[@toml.format(), yaml_only()])))
  assert_eq(location, "/w")
  assert_eq(paths.length(), 2)
}

///|
test "public root evidence requests missing entries and exposes parsed primary sources" {
  let conventions = workspace_first()
  let tree = disk([("/w/acme.toml", "[workspace]"), ("/w/a/acme.toml", "project.name='a'")])
  let context : @config.LoadContext = { tree, working_dir: Some(p("/w/a")), platform: Some(Linux), env_vars: Map([]), formats: [@toml.format()] }
  guard conventions.roots(context) is Done(evidence) else { fail("complete tree requested I/O") }
  assert_eq(evidence.workspace(), Some(p("/w")))
  assert_eq(evidence.nearest_project(), Some(p("/w/a")))
  let primary = @config.build(evidence.sources())
  assert_true(primary.get(@config.KeyPath::parse("workspace")) is Some(_))
  let sources = evidence.sources()
  sources.clear()
  assert_eq(evidence.sources().length(), 1)
  guard conventions.roots({ ..context, tree: @config.FileTree::new() }) is Need(requests) else { fail("missing tree entries ignored") }
  assert_true(!requests.is_empty())
  let listed = @config.FileTree::new().with_listing(p("/w/a"), files(["acme.toml"]))
    .with_missing(p("/w/a/.acme"))
    .with_missing(p("/w/a/.config"))
  guard conventions.roots({ ..context, tree: listed }) is Need([ReadFile(path)]) else { fail("expected only the nearest file content request") }
  assert_eq(path, p("/w/a/acme.toml"))
}

///|
test "complete and incremental workspace-first loads agree" {
  let entries = [("/w/acme.toml", "workspace.members=['a']\nbase=1"), ("/w/a/acme.toml", "project.name='a'")]
  let conventions = workspace_first()
  let builder = @config.builder()
    |> @config.working_dir("/w/a/src")
    |> @config.format(@toml.format())
    |> @conventions.add(conventions)
  let complete = @config.load(builder, disk(entries)) |> done
  let partial = load_from(builder, Map::from_array(entries))
  assert_eq(complete.value(), partial.value())
  assert_eq(report_rows(complete), report_rows(partial))
}

///|
test "automatic workspace-first selection uses the normalized working directory" {
  for (root, platform) in [("/w", @config.Platform::Linux), ("C:/w", @config.Platform::Windows)] {
    let tree = @config.FileTree::new(complete=true)
      .with_listing(p(root), [..files(["acme.toml"]), ..dirs(["a", "b"])])
      .with_listing(p(root + "/a"), files(["acme.toml"]))
      .with_listing(p(root + "/b"), files(["acme.toml"]))
      .with_file(p(root + "/acme.toml"), "workspace.members=['a','b']")
      .with_file(p(root + "/a/acme.toml"), "project.name='a'")
      .with_file(p(root + "/b/acme.toml"), "project.name='b'")
    let config = @config.builder()
      |> @config.working_dir(root + "/a/../b/src")
      |> @config.platform(platform)
      |> @config.format(@toml.format())
      |> @conventions.add(workspace_first())
      |> @config.load(tree)
      |> done
    assert_eq(@config.get_text(config, "project.name"), "b")
    assert_eq(member_report(config).map(report => report.path), Some(Some(root + "/b/acme.toml")))
  }
}

///|
test "a workspace section must be an object and explicit root evidence needs no working directory" {
  try {
    ignore(workspace_in("/w", [("/w/acme.toml", "workspace=42")], conventions=workspace_first()))
    fail("scalar workspace section accepted")
  } catch {
    @config.Decode(..) => ()
    error => raise error
  }
  let context : @config.LoadContext = { tree: disk([("/w/custom.toml", "value=1")]), working_dir: None, platform: Some(Linux), env_vars: Map([]), formats: [@toml.format()] }
  guard workspace_first().roots(context, options=@conventions.DiscoveryOptions::new(config=Explicit("/w/custom.toml"))) is Done(evidence) else { fail("explicit file requested I/O") }
  assert_eq(evidence.nearest_project(), Some(p("/w")))
  assert_true(evidence.sources()[0].kind() is File(Explicit))
}

// Discovery over listings that hold entries the host cannot inspect, as the
// native and js adapters give them for a locked file such as
// `D:/pagefile.sys`. These pure tests run on all four targets.

///|
/// A builder for `acme` with workspaces on, TOML, no boundary and no machine
/// sources, so the search walks up to the root.
fn unbounded(start : String) -> @config.ConfigBuilder {
  @config.builder()
  |> @config.working_dir(start)
  |> @config.platform(Windows)
  |> @config.env_vars({})
  |> @config.format(@toml.format())
  |> @conventions.add(
    @conventions.app_dirs("acme")
    |> @conventions.workspace
    |> @conventions.without(SystemDir),
  )
}

///|
fn locked(name : String) -> @config.DirEntry {
  { name, kind: Inaccessible }
}

///|
test "Unbounded search reaches a locked file at the drive root" {
  let tree = @config.FileTree::new(complete=true)
    .with_listing("D:/", [
      { name: "a", kind: Directory },
      locked("pagefile.sys"),
      locked("System Volume Information"),
    ])
    .with_listing("D:/a", [{ name: "proj", kind: Directory }])
    .with_listing("D:/a/proj", [
      { name: "acme.toml", kind: File },
      locked("busy.log"),
    ])
    .with_file("D:/a/proj/acme.toml", "project.name = \"proj\"")
  let config = unbounded("D:/a/proj") |> @config.load(tree) |> done
  @expect.expect(primary_path(config)).to_equal(Some("D:/a/proj/acme.toml"))
  @expect.expect(@config.get_text(config, "project.name")).to_equal("proj")
}

///|
test "a locked entry does not change workspace and member selection" {
  let tree = @config.FileTree::new(complete=true)
    .with_listing("D:/", [{ name: "w", kind: Directory }, locked("pagefile.sys")])
    .with_listing("D:/w", [
      { name: "acme.toml", kind: File },
      { name: "packages", kind: Directory },
      locked("DumpStack.log.tmp"),
    ])
    .with_listing("D:/w/packages", [{ name: "billing", kind: Directory }])
    .with_listing("D:/w/packages/billing", [
      { name: "acme.toml", kind: File },
      locked("busy.log"),
    ])
    .with_file(
      "D:/w/acme.toml",
      "workspace.members = [\"packages/*\"]\nui.theme = \"workspace\"",
    )
    .with_file("D:/w/packages/billing/acme.toml", "ui.font = \"member\"")
  let config = unbounded("D:/w/packages/billing") |> @config.load(tree) |> done
  @expect.expect(primary_path(config)).to_equal(Some("D:/w/acme.toml"))
  @expect.expect(member_report(config).map(report => report.path)).to_equal(
    Some(Some("D:/w/packages/billing/acme.toml")),
  )
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("workspace")
  @expect.expect(@config.get_text(config, "ui.font")).to_equal("member")
}

///|
test "Inaccessible candidate is an error" {
  // The tree is not complete, so the load asks the host for the file.
  let tree = @config.FileTree::new()
    .with_listing("/w", [locked("acme.toml")])
    .with_missing("/w/.acme")
    .with_missing("/w/.config/acme")
  let builder = @config.builder()
    |> @config.working_dir("/w")
    |> @config.format(@toml.format())
    |> @conventions.add(
      @conventions.app_dirs("acme") |> @conventions.boundary("/w"),
    )
  guard @config.load(builder, tree) is Need(requests) else {
    fail("an inaccessible candidate must be read")
  }
  @expect.expect(requests).to_equal([ReadFile("/w/acme.toml")])
}

///|
test "Inaccessible entry next to a candidate" {
  // The host is asked for the inaccessible candidate before discovery counts
  // the candidates, so its error passes out instead of an ambiguity error.
  let tree = @config.FileTree::new()
    .with_listing("/w", [{ name: "acme.toml", kind: File }, locked("acme.yaml")])
    .with_missing("/w/.acme")
    .with_missing("/w/.config/acme")
    .with_file("/w/acme.toml", "a = 1")
  let builder = @config.builder()
    |> @config.working_dir("/w")
    |> @config.format(@toml.format())
    |> @config.format(yaml_only())
    |> @conventions.add(
      @conventions.app_dirs("acme") |> @conventions.boundary("/w"),
    )
  guard @config.load(builder, tree) is Need(requests) else {
    fail("the inaccessible candidate must be read first")
  }
  @expect.expect(requests).to_equal([ReadFile("/w/acme.yaml")])
  // When the host can read it, both files exist, so discovery is ambiguous.
  let (_, candidates) = ambiguity(() => {
    @config.load(builder, tree.with_file("/w/acme.yaml", "b: 1"))
    |> done
    |> ignore
  })
  @expect.expect(candidates).to_equal(["/w/acme.toml", "/w/acme.yaml"])
}

///|
test "Inaccessible file next to a workspace file" {
  // The enclosing search must not pass over the workspace in `/w` as a
  // directory with several files before the host answers for `acme.yaml`.
  let tree = @config.FileTree::new()
    .with_listing("/w", [
      { name: "acme.toml", kind: File },
      locked("acme.yaml"),
      { name: "packages", kind: Directory },
    ])
    .with_missing("/w/.acme")
    .with_missing("/w/.config/acme")
    .with_file("/w/acme.toml", "workspace.members = [\"packages/*\"]")
    .with_listing("/w/packages", [{ name: "a", kind: Directory }])
    .with_missing("/w/packages/.acme")
    .with_missing("/w/packages/.config/acme")
    .with_listing("/w/packages/a", [{ name: "acme.toml", kind: File }])
    .with_missing("/w/packages/a/.acme")
    .with_missing("/w/packages/a/.config/acme")
    .with_file("/w/packages/a/acme.toml", "a = 1")
  let builder = @config.builder()
    |> @config.working_dir("/w/packages/a")
    |> @config.env_vars({})
    |> @config.format(@toml.format())
    |> @config.format(yaml_only())
    |> @conventions.add(
      @conventions.app_dirs("acme")
      |> @conventions.workspace
      |> @conventions.without(SystemDir)
      |> @conventions.boundary("/w"),
    )
  guard @config.load(builder, tree) is Need(requests) else {
    fail("the enclosing search passed over the workspace")
  }
  @expect.expect(requests).to_equal([ReadFile("/w/acme.yaml")])
}

///|
test "Inaccessible member directory is not dropped" {
  let tree = @config.FileTree::new()
    .with_listing("/w", [
      { name: "acme.toml", kind: File },
      { name: "packages", kind: Directory },
    ])
    .with_missing("/w/.acme")
    .with_missing("/w/.config/acme")
    .with_file("/w/acme.toml", "workspace.members = [\"packages/*\"]")
    .with_listing("/w/packages", [locked("billing")])
  let builder = @config.builder()
    |> @config.working_dir("/w")
    |> @config.env_vars({})
    |> @config.format(@toml.format())
    |> @conventions.add(
      @conventions.app_dirs("acme")
      |> @conventions.workspace
      |> @conventions.without(SystemDir)
      |> @conventions.boundary("/w"),
    )
  guard @config.load(builder, tree) is Need(requests) else {
    fail("an inaccessible member directory must be listed")
  }
  @expect.expect(requests.contains(ListDir("/w/packages/billing"))).to_equal(
    true,
  )
}

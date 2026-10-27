// The host adapters with an injected inspection that fails as a locked file
// does on Windows, such as `D:/pagefile.sys`. The fault does not depend on such
// a file, so these tests give the same result on every platform.

///|
/// A builder for `acme` with workspaces on, TOML, no boundary and no machine
/// sources, so the search walks up to the root of the real file system.
fn unbounded(start : String) -> @config.ConfigBuilder {
  @config.builder()
  |> @config.working_dir(start)
  |> @config.env_vars({})
  |> @config.format(@toml.format())
  |> @conventions.add(
    @conventions.app_dirs("acme")
    |> @conventions.workspace
    |> @conventions.without(SystemDir),
  )
}

///|
/// Fail unless `load` raises the error of the host for a file call.
async fn expect_host_error(load : async () -> @config.Config raise) -> Unit raise {
  try load() catch {
    error if is_host_error(error) => ()
    error => fail("expected the error of the locked entry, got \{error}")
  } noraise {
    _ => fail("expected the error of the locked entry")
  }
}

///|
async test "Locked entry next to a configuration file" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/acme.toml", "a = 1")
  write("\{dir}/gone.txt", "")
  write("\{dir}/pagefile.sys", "")
  write("\{dir}/src/main.mbt", "")
  let tree = faulty_answer(
    @config.FileTree::new(),
    ListDir(dir),
    locked=["\{dir}/pagefile.sys"],
    vanished=["\{dir}/gone.txt"],
  )
  guard tree.listing(dir) is Found(entries) else {
    fail("the adapter gave no listing")
  }
  // The native and js listings sort in a different order. MoonBit compares
  // strings by length first.
  entries.sort_by_key(entry => entry.name)
  @expect.expect(entries).to_equal([
    { name: "src", kind: Directory },
    { name: "acme.toml", kind: File },
    { name: "pagefile.sys", kind: Inaccessible },
  ])
  let config = @config.builder()
    |> @config.working_dir(dir)
    |> @config.env_vars({})
    |> @config.format(@toml.format())
    |> @conventions.add(
      @conventions.app_dirs("acme")
      |> @conventions.without(SystemDir)
      |> @conventions.boundary(dir),
    )
    |> faulty_load(locked=["\{dir}/pagefile.sys"], vanished=["\{dir}/gone.txt"])
  @expect.expect(@config.get_text(config, "a")).to_equal("1")
}

///|
async test "an inspection error that is not a system error passes out" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/acme.toml", "a = 1")
  write("\{dir}/odd.bin", "")
  try
    faulty_answer(
      @config.FileTree::new(),
      ListDir(dir),
      locked=[],
      broken=["\{dir}/odd.bin"],
    )
  catch {
    _ => ()
  } noraise {
    _ => fail("the adapter hid an inspection error that is not a system error")
  }
}

///|
async test "Unbounded search passes over a locked entry" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/acme.toml", "project.name = \"found\"")
  write("\{dir}/pagefile.sys", "")
  write("\{dir}/src/pagefile.sys", "")
  let config = unbounded("\{dir}/src")
    |> faulty_load(locked=["\{dir}/pagefile.sys", "\{dir}/src/pagefile.sys"])
  @expect.expect(@config.get_text(config, "project.name")).to_equal("found")
}

///|
async test "a locked entry keeps the workspace and member selection" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write(
    "\{dir}/acme.toml",
    "workspace.members = [\"packages/*\"]\nui.theme = \"workspace\"",
  )
  write("\{dir}/busy.log", "")
  write("\{dir}/packages/billing/acme.toml", "ui.font = \"member\"")
  write("\{dir}/packages/billing/busy.log", "")
  write("\{dir}/packages/billing/src/main.mbt", "")
  let config = unbounded("\{dir}/packages/billing/src")
    |> faulty_load(locked=[
      "\{dir}/busy.log",
      "\{dir}/packages/billing/busy.log",
    ])
  @expect.expect(@config.get_text(config, "ui.theme")).to_equal("workspace")
  @expect.expect(@config.get_text(config, "ui.font")).to_equal("member")
  let selected = config
    .reports()
    .iter()
    .find_first(report => report.kind == File(Member))
  @expect.expect(selected.map(report => report.path)).to_equal(
    Some(Some("\{dir}/packages/billing/acme.toml")),
  )
}

///|
async test "a locked candidate is an error" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/acme.toml", "a = 1")
  expect_host_error(() => {
    unbounded(dir) |> faulty_load(locked=["\{dir}/acme.toml"])
  })
}

///|
async test "a locked explicit file is an error" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/app.toml", "a = 1")
  expect_host_error(() => {
    @config.builder()
    |> @config.format(@toml.format())
    |> @config.file("\{dir}/app.toml")
    |> faulty_load(locked=["\{dir}/app.toml"])
  })
}

///|
async test "a locked member directory is an error" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/acme.toml", "workspace.members = [\"packages/*\"]")
  write("\{dir}/packages/billing/acme.toml", "a = 1")
  write("\{dir}/packages/orders/acme.toml", "b = 1")
  expect_host_error(() => {
    unbounded(dir) |> faulty_load(locked=["\{dir}/packages/orders"])
  })
}

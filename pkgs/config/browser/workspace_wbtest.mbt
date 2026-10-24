///|
/// Answer the pure loader from a finite mount namespace and record each request.
fn drive(
  builder : @config.ConfigBuilder,
  mount : Mount,
  texts : Map[String, String],
  requests : Array[String],
) -> @config.Config raise {
  let mut tree = @config.FileTree::new()
  for _ in 0..<100 {
    match @config.load(builder, tree) {
      Done(config) => return config
      Need(needs) =>
        for need in needs {
          let path = request_path(need)
          requests.push(path)
          guard contains(mount.root, path) else {
            raise OutsideMount(operation="load", path~)
          }
          match need {
            ListDir(_) =>
              tree = match mount.listings.get(path) {
                Some(entries) => tree.with_listing(path, entries)
                None => tree.with_missing(path)
              }
            ReadFile(_) =>
              tree = match texts.get(path) {
                Some(text) => tree.with_file(path, text)
                None => tree.with_missing(path)
              }
          }
        }
    }
  }
  fail("the loader did not finish")
}

///|
fn project() -> (Mount, Map[String, String]) raise {
  let mount = from_urls(
    "https://example.org/project/",
    {
      "version": 1,
      "files": ["acme.toml", "acme.local.toml", "acme.user.toml", "src/main.mbt"],
    },
    root="/workspace",
  )
  let texts = {
    "/workspace/acme.toml": "[server]\nhost = 'primary'\nport = 1\nname = 'p'\n",
    "/workspace/acme.local.toml": "[server]\nport = 2\nhost = 'local'\n",
    "/workspace/acme.user.toml": "[server]\nport = 3\n",
  }
  (mount, texts)
}

///|
fn builder(conventions : @conventions.Conventions) -> @config.ConfigBuilder {
  @config.builder()
  |> @config.format(@toml.format())
  |> @config.working_dir("/workspace/src")
  |> @config.platform(Linux)
  |> @config.env_vars({
    "HOME": "/home/user",
    "ACME_HOME": "/outside/home",
    "XDG_CONFIG_HOME": "/outside/xdg",
  })
  |> @conventions.add(conventions)
}

///|
test "workspace conventions stop at the mount root and keep overrides" {
  let (mount, texts) = project()
  let requests = []
  let config = drive(
    builder(workspace(@conventions.app_dirs("acme"), mount)),
    mount,
    texts,
    requests,
  )
  assert_true(requests.iter().all(path => contains("/workspace", path)))
  assert_eq(@config.get_text(config, "server.host"), "local")
  assert_eq(@config.get_text(config, "server.port"), "3")
  assert_eq(@config.get_text(config, "server.name"), "p")
  let origins = config.origins(@config.KeyPath::parse("server.port"))
  assert_eq(origins.map(origin => origin.location), [
    Some("/workspace/acme.user.toml"),
  ])
  let paths = config.reports().filter_map(report => report.path)
  assert_eq(paths, [
    "/workspace/acme.toml", "/workspace/acme.local.toml", "/workspace/acme.user.toml",
  ])
}

///|
test "standard conventions request machine directories outside the mount" {
  let (mount, texts) = project()
  let requests = []
  try
    drive(builder(@conventions.app_dirs("acme")), mount, texts, requests)
  catch {
    OutsideMount(..) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected an outside-mount request")
  }
  assert_true(requests.iter().any(path => !contains("/workspace", path)))
}

///|
test "a narrower caller boundary stops discovery below the mount root" {
  let (mount, texts) = project()
  let requests = []
  let conventions = workspace(@conventions.app_dirs("acme"), mount)
    |> @conventions.boundary("/workspace/src")
  let config = drive(builder(conventions), mount, texts, requests)
  assert_true(requests.iter().all(path => contains("/workspace/src", path)))
  try @config.get_text(config, "server.host") catch {
    @config.KeyNotFound(..) => ()
    _ => fail("unexpected error")
  } noraise {
    _ => fail("expected no discovered value")
  }
}

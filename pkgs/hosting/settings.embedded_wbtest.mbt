///|
test "omitted wasm and wasm-gc settings are empty and root" {
  let host : Host[Unit] = builder(@lander_core.AppName::parse("acme"), []) |> build(_ => ())
  let settings = resolve_settings(host)
  assert_eq(Map::from_iter(settings.variables.iter()), Map([]))
  assert_eq(settings.directory, @lander_core.AbsolutePath::root())
  let parsed = parse_arguments(host, env=settings.variables)
  assert_eq(resolve_environment(host, settings, parsed.discovery_options).content_root.to_string(), "/")
}

///|
test "omitted wasm settings feed root discovery through the shared injected load" {
  let tree = @config.FileTree::new(complete=true)
    .with_listing(p("/"), [{ name: "acme.toml", kind: File }])
    .with_file(p("/acme.toml"), "from_root = true")
  let loaded = builder(@lander_core.AppName::parse("acme"), [])
    |> configure(s => s |> @config.format(@toml.format()))
    |> app_dirs() |> files(tree)
    |> build(b => {
      assert_eq(b.env_vars.length(), 0)
      assert_eq(b.working_dir.to_string(), "/")
      assert_eq((@config.bind(b.config, "from_root") : Bool), true)
    }) |> injected_run
  assert_eq(loaded.context.env_vars.length(), 0)
  assert_eq(loaded.context.working_dir.to_string(), "/")
}

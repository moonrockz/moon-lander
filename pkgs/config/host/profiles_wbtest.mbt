///|
async test "profile discovery uses ordinary adapter requests over real temporary files" {
  let dir = temp_dir()
  defer remove_dir(from_slash(dir, running_platform()))
  write("\{dir}/acme.toml", "mode = \"base\"")
  write("\{dir}/acme.profile.metrics.toml", "mode = \"metrics\"")
  // An inactive malformed file must never be parsed.
  write("\{dir}/acme.profile.unused.toml", "not valid TOML = [")
  let metrics = @config.ProfileName::parse("metrics")
  let builder = @config.builder()
    |> @config.working_dir(dir) |> @config.env_vars({})
    |> @config.format(@toml.format())
    |> @conventions.add(@conventions.app_dirs("acme")
      |> @conventions.without(SystemDir) |> @conventions.boundary(dir)
      |> @conventions.profiles(@profiles.Policy::new()),
      options=@conventions.DiscoveryOptions::new(
        profiles=Selected(@config.ProfileNames::new([metrics]))))
  // The public pure entry cannot publish metadata from an incomplete tree.
  guard @config.load(builder, @config.FileTree::new()) is Need(requests) else {
    fail("an empty snapshot must request discovery inputs")
  }
  assert_true(!requests.is_empty())
  let loaded = load(builder)
  assert_eq(@config.get_text(loaded, "mode"), "metrics")
  assert_true(loaded.profiles().contains(metrics))
  let reports = loaded.reports().filter(report => report.kind is File(ProfileFile(_)))
  assert_eq(reports.length(), 1)
  assert_eq(reports[0].priority, 380)
  assert_eq(reports[0].path, Some("\{dir}/acme.profile.metrics.toml"))
  assert_eq(reports[0].status, Loaded)
}

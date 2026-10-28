///|
test "public profile controls and files agree across all supported serializations" {
  for (_, config) in configurations() {
    assert_eq(@config.get_text(config,"mode"),"metrics")
    assert_eq(config.get(@config.KeyPath::parse("profiles")),None)
    guard config.profiles() is Resolved(resolution) else { fail("enabled policy") }
    assert_eq(resolution.active().names().map(name => name.to_string()),["common","production","metrics"])
    assert_eq(config.reports().filter(report => report.kind is File(ProfileFile(_))).map(report => report.status),[NotFound,NotFound,Loaded])
    assert_eq(config.get(@config.KeyPath::parse("items")),Some(@config.list([@config.string("profile")])))
  }
}

///|
test "every serialization rejects invalid profile controls with the file and key" {
  for (extension, text) in [
    ("toml", "profiles.active=42"),
    ("yaml", "profiles:\n  active: 42\n"),
    ("json", "{\"profiles\":{\"active\":42}}"),
    ("json5", "{profiles:{active:42}}"),
    ("ion", "{profiles:{active:42}}"),
  ] {
    let filename="acme.\{extension}"
    let tree=@config.FileTree::new(complete=true)
      .with_listing(path("/workspace"),[{name:filename,kind:File}])
      .with_file(path("/workspace/\{filename}"),text)
    let mut builder=@config.builder() |> @config.working_dir("/workspace") |> @config.env_vars({})
    for format in @formats.formats() {builder=builder |> @config.format(format)}
    builder=builder |> @conventions.add(@conventions.base("acme") |> @conventions.layouts |> @conventions.profiles(@profiles.Policy::new()))
    try {ignore(@config.load(builder,tree)); fail("invalid literal controls")} catch {
      @config.Profile(failure~) => {
        assert_eq(failure.rule(),ExpectedList)
        guard failure.origin() is Control(origin,key) else {fail("typed control origin")}
        assert_eq(origin.location,Some("/workspace/\{filename}"))
        assert_eq(key.to_string(),"profiles.active")
      }
      error => raise error
    }
  }
}

///|
test "profile lists replace defaults null overlays retain values and later stages win" {
  let tree=@config.FileTree::new(complete=true)
    .with_listing(path("/workspace"),[
      {name:"acme.toml",kind:File},
      {name:"acme.profile.metrics.json",kind:File},
      {name:"acme.local.toml",kind:File},
      {name:"acme.user.toml",kind:File},
    ])
    .with_file(path("/workspace/acme.toml"),"mode='base'\nitems=['base']\n[profiles]\nactive=['metrics']")
    .with_file(path("/workspace/acme.profile.metrics.json"),"{\"mode\":null,\"items\":[\"profile\"],\"higher\":\"profile\"}")
    .with_file(path("/workspace/acme.local.toml"),"higher='local'")
    .with_file(path("/workspace/acme.user.toml"),"higher='user'")
  let mut builder=@config.builder() |> @config.working_dir("/workspace") |> @config.env_vars({"ACME_HIGHER":"variable"})
  for format in @formats.formats() {builder=builder |> @config.format(format)}
  builder=builder |> @conventions.add(@conventions.app_dirs("acme") |> @conventions.profiles(@profiles.Policy::new()))
    |> @config.env(prefix="ACME",reserved=["ACME_PROFILES"])
  guard @config.load(builder,tree) is Done(config) else {fail("complete")}
  assert_eq(@config.get_text(config,"mode"),"base")
  assert_eq(@config.get_text(config,"higher"),"variable")
  assert_eq(config.get(@config.KeyPath::parse("items")),Some(@config.list([@config.string("profile")])))
  guard @config.load(builder |> @config.overrides([("higher",@config.string("cli"))]),tree) is Done(config) else {fail("complete")}
  assert_eq(@config.get_text(config,"higher"),"cli")
}

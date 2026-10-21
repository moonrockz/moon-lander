///|
/// Identical explicit inputs for every compiler target and operating system.
pub fn load() -> @config.Config raise @config.ConfigError {
  let mut builder = @config.builder()
  for format in @formats.formats() {
    builder = @config.format(builder, format)
  }
  builder = builder
    |> @config.working_dir("/workspace")
    |> @config.env_vars({ "APP_SERVER__PORT": "9000", "APP_ENABLED": "true" })
    |> @config.defaults({
      "server": { "host": "localhost", "port": 80 },
      "plugins": ["base"],
      "unused": null,
    })
    |> @config.file("app.toml", name="project")
    |> @config.add(
      @config.ConfigSource::file("app.yaml", name="yaml", priority=310)
      .with_key_policy(@config.KeyPath::parse("plugins"), Append)
      .exclude([@config.KeyPath::parse("discard")], warn=true),
    )
    |> @config.file("app.json", name="json", priority=320)
    |> @config.file("app.json5", name="json5", priority=330)
    |> @config.file("app.ion", name="ion", priority=340)
    |> @config.add(
      @config.ConfigSource::candidates(
        ["missing.toml"],
        display="optional",
        priority=350,
      ),
    )
    |> @config.add(
      @config.ConfigSource::skipped(File(LocalOverride), name="skipped"),
    )
    |> @config.env(prefix="APP")
    |> @config.overrides([("server.host", @config.string("command"))])
  let tree = @config.FileTree::new(complete=true)
    .with_file(
      "/workspace/app.toml", "[server]\nhost = 'file'\nport = 8080\n[registry]\ntoken = {env = 'TOKEN'}",
    )
    .with_file("/workspace/app.yaml", "plugins: [yaml]\ndiscard: hidden\n")
    .with_file("/workspace/app.json", "{\"json\": 3}")
    .with_file("/workspace/app.json5", "{json5: 5, /* allowed */}")
    .with_file(
      "/workspace/app.ion", "{exact: 123456789012345678901234567890, price: 1.20}",
    )
  match @config.load(builder, tree) {
    Done(config) => config
    Need(_) => abort("a complete integration tree must not request files")
  }
}

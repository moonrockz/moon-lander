///|
test "Same result on all targets uses all formats and explicit inputs" {
  let config = @fixture.load()
  @expect.expect(@config.get_text(config, "server.host")).to_equal("command")
  @expect.expect(@config.get_text(config, "server.port")).to_equal("9000")
  @expect.expect(@config.get_text(config, "enabled")).to_equal("true")
  @expect.expect(@config.get_text(config, "exact")).to_equal(
    "123456789012345678901234567890",
  )
  @expect.expect(@config.get_text(config, "json")).to_equal("3")
  @expect.expect(@config.get_text(config, "json5")).to_equal("5")
  @expect.expect(config.get(@config.KeyPath::parse("plugins"))).to_equal(
    Some(@config.list([@config.string("base"), @config.string("yaml")])),
  )
  @expect.expect(config.get(@config.KeyPath::parse("discard"))).to_equal(None)
  @expect.expect(config.get(@config.KeyPath::parse("unused"))).to_equal(None)
  @expect.expect(config.origins(@config.KeyPath::parse("server.port"))).to_equal([
      {
        kind: Environment,
        source: "environment",
        priority: 600,
        location: Some("APP_SERVER__PORT"),
      },
    ],
  )
  @expect.expect(
    config
    .origins(@config.KeyPath::parse("plugins"))
    .map(origin => origin.source),
  ).to_equal(["defaults", "yaml"])
  @expect.expect(config.reports().map(report => (report.name, report.status))).to_equal([
      ("defaults", Loaded),
      ("project", Loaded),
      ("yaml", Loaded),
      ("json", Loaded),
      ("json5", Loaded),
      ("ion", Loaded),
      ("optional", NotFound),
      ("skipped", Skipped),
      ("environment", Loaded),
      ("overrides", Loaded),
    ],
  )
  @expect.expect(config.warnings().length()).to_equal(1)
  @expect.expect(@config.get_text(config, "registry.token")).to_equal(
    "<redacted>",
  )
}

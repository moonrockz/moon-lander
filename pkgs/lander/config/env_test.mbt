///|
fn env_config(
  vars : Map[String, String],
  reserved? : Array[String] = [],
) -> @config.Config raise @config.ConfigError {
  @config.build([
    @config.ConfigSource::env(
      prefix="MORPHIR",
      reserved~,
      selection=Explicit(vars),
    ),
  ])
}

///|
test "Double underscore nests" {
  let config = env_config({ "MORPHIR_CODEGEN__GO__PACKAGE": "foo" })
  @expect.expect(@config.get_text(config, "codegen.go.package")).to_equal("foo")
}

///|
test "Single underscore stays" {
  let config = env_config({ "MORPHIR_IR_FORMAT_VERSION": "3" })
  @expect.expect(config.get(key("ir_format_version"))).to_equal(
    Some(@config.int(3)),
  )
}

///|
test "Leading underscores after the prefix" {
  let config = env_config({ "MORPHIR__IR__STRICT_MODE": "TRUE" })
  @expect.expect(config.get(key("ir.strict_mode"))).to_equal(
    Some(@config.bool(true)),
  )
}

///|
test "Prefix in any case" {
  let config = env_config({ "morphir_ui__color": "false" })
  @expect.expect(config.get(key("ui.color"))).to_equal(Some(@config.bool(false)))
}

///|
test "Other variables stay out" {
  let config = env_config({ "PATH": "/bin", "MORPHIRX_A": "1" })
  @expect.expect(config.value()).to_equal(@config.fields([]))
  @expect.expect(config.reports()[0].status).to_equal(Loaded)
}

///|
test "Empty segment" {
  try env_config({ "MORPHIR_A____B": "1" }) catch {
    error =>
      @expect.expect(error).to_equal(InvalidEnvKey(variable="MORPHIR_A____B"))
  } noraise {
    _ => fail("expected an invalid environment key")
  }
  try env_config({ "MORPHIR_": "1" }) catch {
    error => @expect.expect(error).to_equal(InvalidEnvKey(variable="MORPHIR_"))
  } noraise {
    _ => fail("expected an invalid environment key for an empty key")
  }
}

///|
test "Reserved helper variables" {
  let config = env_config(
    {
      "MORPHIR_HOME": "/x",
      "morphir_log_dir": "/y",
      "MORPHIR_IR__LAYOUT": "tree",
    },
    reserved=["MORPHIR_HOME", "MORPHIR_LOG_DIR"],
  )
  @expect.expect(config.value()).to_equal(
    @config.fields([("ir", @config.fields([("layout", @config.string("tree"))]))]),
  )
}

///|
test "Typed values" {
  let config = env_config({
    "MORPHIR_IR__STRICT_MODE": "TRUE",
    "MORPHIR_IR__FORMAT_VERSION": "+003",
    "MORPHIR_CUSTOM__FLOAT": "1.5",
    "MORPHIR_CUSTOM__QUOTED": "\"text\"",
  })
  @expect.expect(config.get(key("ir.strict_mode"))).to_equal(
    Some(@config.bool(true)),
  )
  @expect.expect(config.get(key("ir.format_version"))).to_equal(
    Some(@config.int(3)),
  )
  @expect.expect(config.get(key("custom.float"))).to_equal(
    Some(@config.string("1.5")),
  )
  @expect.expect(config.get(key("custom.quoted"))).to_equal(
    Some(@config.string("\"text\"")),
  )
}

///|
test "JSON list value" {
  let config = env_config({ "MORPHIR_WORKSPACE__MEMBERS": "[\"a\",\"b\"]" })
  @expect.expect(config.get(key("workspace.members"))).to_equal(
    Some(@config.list([@config.string("a"), @config.string("b")])),
  )
}

///|
test "Invalid JSON stays text" {
  let config = env_config({ "MORPHIR_A": "[not json" })
  @expect.expect(config.get(key("a"))).to_equal(Some(@config.string("[not json")))
}

///|
test "Integer out of range" {
  let config = env_config({
    "MORPHIR_A": "99999999999999999999",
    "MORPHIR_B": "9223372036854775807",
    "MORPHIR_C": "-9223372036854775808",
    "MORPHIR_D": "9223372036854775808",
    "MORPHIR_E": "-",
  })
  @expect.expect(config.get(key("a"))).to_equal(
    Some(@config.string("99999999999999999999")),
  )
  @expect.expect(config.get(key("b"))).to_equal(
    Some(@config.int(9223372036854775807L)),
  )
  @expect.expect(config.get(key("c"))).to_equal(
    Some(@config.int(-9223372036854775808L)),
  )
  @expect.expect(config.get(key("d"))).to_equal(
    Some(@config.string("9223372036854775808")),
  )
  @expect.expect(config.get(key("e"))).to_equal(Some(@config.string("-")))
}

///|
test "Shorter struct merges over nested values" {
  let config = env_config({
    "MORPHIR_PROJECT": "{\"name\":\"Short\"}",
    "MORPHIR_PROJECT__SOURCE_DIRECTORY": "lib",
    "MORPHIR_PROJECT__NAME": "Overridden",
  })
  @expect.expect(@config.get_text(config, "project.name")).to_equal("Short")
  @expect.expect(@config.get_text(config, "project.source_directory")).to_equal(
    "lib",
  )
}

///|
test "Shorter scalar replaces nested values" {
  for vars in [
    [("MORPHIR_IR", "x"), ("MORPHIR_IR__STRICT_MODE", "true")],
    [("MORPHIR_IR__STRICT_MODE", "true"), ("MORPHIR_IR", "x")],
  ] {
    let config = env_config(Map::from_array(vars))
    @expect.expect(config.value()).to_equal(
      @config.fields([("ir", @config.string("x"))]),
    )
  }
}

///|
test "Environment origin names the variable" {
  let config = env_config({
    "MORPHIR_IR__LAYOUT": "tree",
    "MORPHIR_IR__STRICT_MODE": "true",
  })
  @expect.expect(config.origins(key("ir.layout"))).to_equal([
    {
      kind: Environment,
      source: "environment",
      priority: 600,
      location: Some("MORPHIR_IR__LAYOUT"),
    },
  ])
  @expect.expect(
    config.origins(key("ir.strict_mode")).map(origin => origin.location),
  ).to_equal([Some("MORPHIR_IR__STRICT_MODE")])
}

///|
test "Explicit environment variables" {
  let config = @config.builder()
    |> @config.env_vars({ "APP_B": "2" })
    |> @config.env(prefix="APP", selection=Explicit({ "APP_A": "1" }))
    |> @config.load(@config.FileTree::new(complete=true))
    |> done
  @expect.expect(config.value()).to_equal(
    @config.fields([("a", @config.int(1))]),
  )
}

///|
test "Discover environment with no host" {
  let config = @config.builder()
    |> @config.env(prefix="APP")
    |> @config.load(@config.FileTree::new(complete=true))
    |> done
  @expect.expect(config.value()).to_equal(@config.fields([]))
  @expect.expect(config.reports()[0].status).to_equal(NotFound)
}

///|
test "Discover environment reads the builder variable set" {
  let config = @config.builder()
    |> @config.env_vars({ "APP_SERVER__PORT": "9000", "OTHER": "x" })
    |> @config.env(prefix="APP")
    |> @config.load(@config.FileTree::new(complete=true))
    |> done
  @expect.expect(config.get(key("server.port"))).to_equal(Some(@config.int(9000)))
}

///|
test "Skip a source with the environment selection" {
  let config = @config.builder()
    |> @config.env_vars({ "APP_IR__LAYOUT": "tree" })
    |> @config.env(prefix="APP", selection=Skip)
    |> @config.load(@config.FileTree::new(complete=true))
    |> done
  @expect.expect(config.get(key("ir.layout"))).to_equal(None)
  @expect.expect(config.reports()[0].status).to_equal(Skipped)
}

///|
test "Overrides beat the environment" {
  let config = @config.builder()
    |> @config.env(prefix="APP", selection=Explicit({ "APP_IR__LAYOUT": "tree" }))
    |> @config.overrides([("ir.layout", @config.string("single-file"))])
    |> @config.load(@config.FileTree::new(complete=true))
    |> done
  @expect.expect(@config.get_text(config, "ir.layout")).to_equal("single-file")
  let origin = config.origins(key("ir.layout"))[0]
  @expect.expect((origin.kind, origin.kind.report_name(), origin.priority)).to_equal((
    Overrides, "overrides", 700,
  ))
}

///|
test "an excluded environment key names its variable" {
  let config = @config.build([
    @config.ConfigSource::env(
      prefix="APP",
      selection=Explicit({ "APP_WORKSPACE__OUT_DIR": "x", "APP_A": "1" }),
    ).exclude([key("workspace.out_dir")], warn=true),
  ])
  @expect.expect(config.warnings()).to_equal([
    KeyRemoved(key("workspace.out_dir"), {
      kind: Environment,
      source: "environment",
      priority: 600,
      location: Some("APP_WORKSPACE__OUT_DIR"),
    }),
  ])
}

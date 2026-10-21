///|
test "Redact nested keys" {
  let config = @config.build([
    named(
      {
        "registry": { "password": "hunter2", "username": "alice" },
        "toolchain": { "elm": { "env": { "NPM_TOKEN": "x" } } },
      },
      "base",
    ),
  ])
  @expect.expect(@config.get_text(config, "registry.password")).to_equal(
    "<redacted>",
  )
  @expect.expect(@config.get_text(config, "toolchain.elm.env.NPM_TOKEN")).to_equal(
    "<redacted>",
  )
  @expect.expect(@config.get_text(config, "registry.username")).to_equal("alice")
}

///|
test "Key name shapes" {
  let config = @config.build([
    named(
      {
        "apiKey": "1",
        "client-secret": "2",
        "aws_access_key_id": "3",
        "credentials": "4",
        "tokenizer_mode": "5",
      },
      "base",
    ),
  ])
  for name in [
      "apiKey",
      "client-secret",
      "aws_access_key_id",
      "credentials",
      "tokenizer_mode",
    ] {
    @expect.expect(@config.get_text(config, name)).to_equal("<redacted>")
  }
}

///|
test "Safe key names" {
  let config = @config.build([
    named(
      {
        "username": "a",
        "authors": ["b"],
        "key_bindings": "c",
        "entry_point": "d",
      },
      "base",
    ),
  ])
  @expect.expect(@config.get_text(config, "username")).to_equal("a")
  @expect.expect(@config.get_text(config, "authors")).to_equal("[\"b\"]")
  @expect.expect(@config.get_text(config, "key_bindings")).to_equal("c")
  @expect.expect(@config.get_text(config, "entry_point")).to_equal("d")
}

///|
test "Redaction does not change the configuration" {
  let config = @config.build([
    named({ "registry": { "token": "top-secret-token" } }, "base"),
  ])
  @config.redact(config.value()) |> ignore
  @expect.expect(config.get(key("registry.token"))).to_equal(
    Some(@config.string("top-secret-token")),
  )
}

///|
test "Get a string" {
  let config = @config.build([
    named({ "project": { "name": "acceptance-project" } }, "base"),
  ])
  @expect.expect(@config.get_text(config, "project.name")).to_equal(
    "acceptance-project",
  )
}

///|
test "Get as JSON" {
  let config = @config.build([
    named({ "ir": { "format_version": 4 } }, "base"),
  ])
  @expect.expect(@config.get_json(config, "ir.format_version")).to_equal({
    "key": "ir.format_version",
    "value": 4,
  })
}

///|
test "Get a sensitive key" {
  let config = @config.build([
    named({ "registry": { "token": "top-secret-token" } }, "base"),
  ])
  let text = @config.get_text(config, "registry.token")
  @expect.expect(text).to_equal("<redacted>")
  @expect.expect(text.contains("top-secret-token")).to_be_false()
}

///|
test "Get a missing key" {
  let config = @config.build([])
  try @config.get_text(config, "project.missing") catch {
    error =>
      @expect.expect(error.message()).to_equal(
        "Configuration key not found: project.missing",
      )
  } noraise {
    _ => fail("expected KeyNotFound")
  }
}

///|
test "Show as JSON" {
  let config = @config.build([
    named(
      {
        "registry": {
          "token": "top-secret-token",
          "endpoint": "https://registry.example.test",
        },
      },
      "base",
    ),
  ])
  let text = @config.show(config, Json)
  @expect.expect(text.contains("<redacted>")).to_equal(true)
  @expect.expect(text.contains("https://registry.example.test")).to_equal(true)
  @expect.expect(text.contains("top-secret-token")).to_be_false()
}

///|
test "Show as TOML" {
  let config = @config.build([
    named({ "ir": { "format_version": 3 } }, "base"),
  ])
  let text = @config.show(config, Toml)
  @expect.expect(text.contains("format_version = 3")).to_equal(true)
}

///|
test "Null in a list cannot render as TOML" {
  let config = @config.build([named({ "a": [1, null] }, "base")])
  try @config.show(config, Toml) catch {
    error => {
      guard error is Render(format~, key~, ..) else { fail("wrong error") }
      @expect.expect(format).to_equal("TOML")
      @expect.expect(key.to_string()).to_equal("a")
    }
  } noraise {
    _ => fail("expected Render")
  }
}

///|
test "Path as text" {
  let config = @config.build([
    @config.ConfigSource::defaults({ "a": 1 }),
    @config.ConfigSource::parsed_file(
      "/w/app.toml",
      @config.ConfigValue::from_json({ "b": 2 }),
      name="project",
    ),
  ])
  let text = @config.path_text(config.reports())
  @expect.expect(
    text.has_prefix("Configuration sources (in priority order):"),
  ).to_equal(true)
  @expect.expect(text.contains("[✓]")).to_equal(true)
  @expect.expect(text.contains("Path: /w/app.toml")).to_equal(true)
  @expect.expect(text.contains("Status: loaded")).to_equal(true)
  @expect.expect(text.contains("Priority:")).to_equal(true)
  // Highest priority (project) listed before defaults.
  @expect.expect(
    text.has_prefix(
      "Configuration sources (in priority order):\n\n[✓] project (project)",
    ),
  ).to_equal(true)
}

///|
test "Path as JSON" {
  let config = @config.build([
    @config.ConfigSource::defaults({ "a": 1 }),
    @config.ConfigSource::parsed_file(
      "/w/app.toml",
      @config.ConfigValue::from_json({ "b": 2 }),
      name="project",
    ),
  ])
  let json = @config.path_json(config.reports())
  guard json is Array(items) else { fail("expected array") }
  @expect.expect(items.length()).to_equal(2)
  guard items[0] is Object(first) else { fail("expected object") }
  guard items[1] is Object(second) else { fail("expected object") }
  @expect.expect(first.get("priority")).to_equal(Some(Json::number(0.0)))
  @expect.expect(second.get("priority")).to_equal(Some(Json::number(300.0)))
  @expect.expect(second.get("path")).to_equal(Some(Json::string("/w/app.toml")))
  @expect.expect(second.get("status")).to_equal(Some(Json::string("loaded")))
}

///|
test "Explain a leaf" {
  let config = @config.build([
    named({ "ir": { "format_version": 3 } }, "file"),
    @config.ConfigSource::env(
      prefix="MORPHIR",
      selection=Explicit({ "MORPHIR_IR__FORMAT_VERSION": "4" }),
    ),
  ])
  let explained = @config.explain(config, "ir.format_version")
  @expect.expect(explained.length()).to_equal(1)
  @expect.expect(explained[0].0.to_string()).to_equal("ir.format_version")
  @expect.expect(explained[0].1[0].kind).to_equal(Environment)
  @expect.expect(explained[0].1[0].location).to_equal(
    Some("MORPHIR_IR__FORMAT_VERSION"),
  )
}

///|
test "Explain a struct" {
  let config = @config.build([
    named({ "project": { "name": "A" } }, "base"),
    named({ "project": { "version": "1" } }, "user"),
  ])
  let explained = @config.explain(config, "project")
  @expect.expect(
    explained.map(entry =>
      (entry.0.to_string(), entry.1.map(origin => origin.source))
    ),
  ).to_equal([("project.name", ["base"]), ("project.version", ["user"])])
}

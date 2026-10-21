///|
struct ConfigWorld {
  mut snapshot : String
  pairs : Array[(String, @config.ConfigValue)]
  mut config : @config.Config?
  mut text : String
  mut json : Json?
}

///|
fn ConfigWorld::ConfigWorld() -> ConfigWorld {
  { snapshot: "", pairs: [], config: None, text: "", json: None }
}

///|
impl @moonspec.World for ConfigWorld with fn configure(self, setup) {
  setup.given1("the TOML snapshot:", (source : @moonspec.DocString) => {
    self.snapshot = source.content
  })
  setup.given2("the in-memory pair {string} with the string {string}", (
    key : String,
    value : String,
  ) => self.pairs.push((key, @config.string(value))))
  setup.given2("the in-memory pair {string} with the integer {int}", (
    key : String,
    value : Int,
  ) => self.pairs.push((key, @config.int(value.to_int64()))))
  setup.when0("the in-memory source is merged over the TOML snapshot", () => {
    self.config = Some(
      @config.build([
        @config.in_memory(
          @toml.parse(self.snapshot, origin="app.toml"),
          name="app.toml",
        ),
        @config.in_memory_pairs(self.pairs),
      ]),
    )
  })
  setup.when0("the in-memory configuration is built", () => {
    self.config = Some(@config.build([@config.in_memory_pairs(self.pairs)]))
  })
  setup.when0("the defaults and project file configuration is built", () => {
    self.config = Some(
      @config.build([
        @config.ConfigSource::defaults({ "project": { "name": "defaults" } }),
        @config.ConfigSource::parsed_file(
          "/w/app.toml",
          @config.ConfigValue::from_json({
            "project": { "name": "acceptance-project" },
            "registry": {
              "token": "top-secret-token",
              "endpoint": "https://registry.example.test",
            },
            "ir": { "format_version": 3 },
          }),
          name="project",
        ),
      ]),
    )
  })
  setup.when1("the caller gets {string}", (key : String) => {
    guard self.config is Some(config) else { fail("build the configuration first") }
    self.text = @config.get_text(config, key)
  })
  setup.when1("the caller gets {string} as JSON", (key : String) => {
    guard self.config is Some(config) else { fail("build the configuration first") }
    self.json = Some(@config.get_json(config, key))
  })
  setup.when0("the caller shows the configuration as JSON", () => {
    guard self.config is Some(config) else { fail("build the configuration first") }
    self.text = @config.show(config, Json)
  })
  setup.when0("the caller shows the configuration as TOML", () => {
    guard self.config is Some(config) else { fail("build the configuration first") }
    self.text = @config.show(config, Toml)
  })
  setup.when0("the caller renders the path text", () => {
    guard self.config is Some(config) else { fail("build the configuration first") }
    self.text = @config.path_text(config.reports())
  })
  setup.when0("the caller renders the path JSON", () => {
    guard self.config is Some(config) else { fail("build the configuration first") }
    self.json = Some(@config.path_json(config.reports()))
  })
  setup.then2("the text at {string} is {string}", (
    key : String,
    expected : String,
  ) => {
    guard self.config is Some(config) else { fail("build the configuration first") }
    @expect.expect(@config.get_text(config, key)).to_equal(expected)
  })
  setup.then1("the text output is {string}", (expected : String) => {
    @expect.expect(self.text).to_equal(expected)
  })
  setup.then1("the output holds {string}", (fragment : String) => {
    @expect.expect(self.text.contains(fragment)).to_equal(true)
  })
  setup.then1("the output does not hold {string}", (fragment : String) => {
    @expect.expect(self.text.contains(fragment)).to_be_false()
  })
  setup.then0("the JSON value is 4", () => {
    guard self.json is Some(Object(object)) else { fail("missing JSON") }
    @expect.expect(object.get("value")).to_equal(Some(Json::number(4.0)))
    @expect.expect(object.get("key")).to_equal(
      Some(Json::string("ir.format_version")),
    )
  })
  setup.then0("the path text lists the project source before the defaults source", () => {
    @expect.expect(
      self.text.has_prefix(
        "Configuration sources (in priority order):\n\n[✓] project (project)",
      ),
    ).to_equal(true)
    @expect.expect(self.text.contains("Path: /w/app.toml")).to_equal(true)
    @expect.expect(self.text.contains("Status: loaded")).to_equal(true)
  })
  setup.then0("the path JSON lists sources in ascending priority", () => {
    guard self.json is Some(Array(items)) else { fail("missing JSON array") }
    @expect.expect(items.length()).to_equal(2)
    guard items[0] is Object(first) else { fail("expected object") }
    guard items[1] is Object(second) else { fail("expected object") }
    @expect.expect(first.get("priority")).to_equal(Some(Json::number(0.0)))
    @expect.expect(second.get("priority")).to_equal(Some(Json::number(300.0)))
    @expect.expect(second.get("kind")).to_equal(Some(Json::string("project")))
  })
}

///|
let feature : String =
  #|Feature: Merge configuration sources
  #|  Scenario: An in-memory source overrides a TOML snapshot
  #|    Given the TOML snapshot:
  #|      """toml
  #|      [project]
  #|      name = "from-file"
  #|      version = "1.0.0"
  #|      """
  #|    And the in-memory pair "project.name" with the string "from-memory"
  #|    When the in-memory source is merged over the TOML snapshot
  #|    Then the text at "project.name" is "from-memory"
  #|    And the text at "project.version" is "1.0.0"
  #|
  #|Feature: Configuration helpers
  #|  Scenario: Get a string
  #|    Given the in-memory pair "project.name" with the string "acceptance-project"
  #|    When the in-memory configuration is built
  #|    And the caller gets "project.name"
  #|    Then the text output is "acceptance-project"
  #|
  #|  Scenario: Get as JSON
  #|    Given the in-memory pair "ir.format_version" with the integer 4
  #|    When the in-memory configuration is built
  #|    And the caller gets "ir.format_version" as JSON
  #|    Then the JSON value is 4
  #|
  #|  Scenario: Get a sensitive key
  #|    Given the in-memory pair "registry.token" with the string "top-secret-token"
  #|    When the in-memory configuration is built
  #|    And the caller gets "registry.token"
  #|    Then the output holds "<redacted>"
  #|    And the output does not hold "top-secret-token"
  #|
  #|  Scenario: Show as JSON
  #|    When the defaults and project file configuration is built
  #|    And the caller shows the configuration as JSON
  #|    Then the output holds "<redacted>"
  #|    And the output holds "https://registry.example.test"
  #|    And the output does not hold "top-secret-token"
  #|
  #|  Scenario: Show as TOML
  #|    When the defaults and project file configuration is built
  #|    And the caller shows the configuration as TOML
  #|    Then the output holds "format_version = 3"
  #|
  #|  Scenario: Path as text
  #|    When the defaults and project file configuration is built
  #|    And the caller renders the path text
  #|    Then the path text lists the project source before the defaults source
  #|
  #|  Scenario: Path as JSON
  #|    When the defaults and project file configuration is built
  #|    And the caller renders the path JSON
  #|    Then the path JSON lists sources in ascending priority

///|
/// Run each scenario of `text` with a fresh world and fail on the first scenario
/// that does not pass. `@moonspec.run_or_fail` is async, and wasm-gc has no
/// async test entry, so this suite drives the synchronous runner steps itself to
/// run on all four targets.
fn[W : @moonspec.World] run_scenarios(
  factory : () -> W,
  uri : String,
  text : String,
) -> Unit raise {
  let cache = @runner.FeatureCache::new()
  cache.load_text(uri, text)
  let pickles = @runner.compile_pickles(cache)
  @expect.expect(pickles.is_empty()).to_be_false()
  for pickle in pickles {
    let setup = @moonspec_core.Setup::new()
    @moonspec.World::configure(factory(), setup)
    let result = @runner.execute_scenario(
      setup.step_registry(),
      feature_name=uri,
      scenario_name=pickle.name,
      pickle_id=pickle.id,
      tags=[],
      steps=pickle.steps,
    )
    if result.status != Passed {
      let failures = result.steps
        .filter(step => !step.status.is_passed())
        .map(step => "\{step.keyword}\{step.text}: \{step.status.to_repr()}")
      fail("\{pickle.name} did not pass:\n\{failures.join("\n")}")
    }
  }
}

///|
test "configuration core acceptance scenarios" {
  run_scenarios(() => ConfigWorld::ConfigWorld(), "config.feature", feature)
}

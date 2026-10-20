///|
struct ConfigWorld {
  mut snapshot : String
  pairs : Array[(String, @config.ConfigValue)]
  mut config : @config.Config?
}

///|
fn ConfigWorld::ConfigWorld() -> ConfigWorld {
  { snapshot: "", pairs: [], config: None }
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
  setup.then2("the text at {string} is {string}", (
    key : String,
    expected : String,
  ) => {
    guard self.config is Some(config) else { fail("build the configuration first") }
    @expect.expect(@config.get_text(config, key)).to_equal(expected)
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

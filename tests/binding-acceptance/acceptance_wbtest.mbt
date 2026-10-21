///|
priv struct IrOptions {
  layout : String
  strict_mode : Bool
} derive(FromJson)

///|
priv struct Pipeline {
  target : String
} derive(FromJson)

///|
priv struct AppConfig {
  ir : IrOptions
  pipeline : Pipeline
} derive(FromJson)

///|
priv struct Target {
  level : Int
} derive(FromJson)

///|
/// The files of one scenario, the loaded configuration, and the outcome of the
/// last binding: a result text or an error.
priv struct BindingWorld {
  files : Array[(String, @config.FileRole, String)]
  mut result : String?
  mut error : @config.ConfigError?
}

///|
fn BindingWorld::BindingWorld() -> BindingWorld {
  { files: [], result: None, error: None }
}

///|
fn role(name : String) -> @config.FileRole {
  match name {
    "project" => Workspace
    "workspace-member" => Member
    "user-override" => UserOverride
    _ => abort("unknown role \{name}")
  }
}

///|
fn BindingWorld::config(self : BindingWorld) -> @config.Config raise {
  let mut builder = @config.builder() |> @config.format(@toml.format())
  let mut tree = @config.FileTree::new(complete=true)
  for file in self.files {
    builder = builder |> @config.file(file.0, role=file.1)
    tree = tree.with_file(file.0, file.2)
  }
  guard @config.load(builder, tree) is Done(config) else {
    fail("a complete tree never asks for files")
  }
  config
}

///|
/// Run `bind` and keep its result text or its configuration error.
fn BindingWorld::run(
  self : BindingWorld,
  bind : (@config.Config) -> String raise @config.ConfigError,
) -> Unit raise {
  let config = self.config()
  self.result = None
  self.error = None
  try bind(config) catch {
    error => self.error = Some(error)
  } noraise {
    text => self.result = Some(text)
  }
}

///|
fn BindingWorld::message(self : BindingWorld) -> String raise {
  guard self.error is Some(error) else { fail("binding did not fail") }
  error.message()
}

///|
impl @moonspec.World for BindingWorld with fn configure(self, setup) {
  setup.given3("the {string} file {string}:", (
    role_name : String,
    path : String,
    source : @moonspec.DocString,
  ) => self.files.push((path, role(role_name), source.content)))
  setup.when1("the application binds {string} to the IR record", (
    key : String,
  ) => self.run(config => {
    let ir : IrOptions = config |> @config.bind(key)
    "\{ir.layout} \{ir.strict_mode}"
  }))
  setup.when1("the application binds {string} to an optional IR record", (
    key : String,
  ) => self.run(config => {
    let ir : IrOptions? = config |> @config.bind(key)
    if ir is None {
      "none"
    } else {
      "some"
    }
  }))
  setup.when1("the application binds {string} to a list of targets", (
    key : String,
  ) => self.run(config => {
    let targets : Array[Target] = config |> @config.bind(key)
    targets.map(target => target.level.to_string()).join(",")
  }))
  setup.when0("the application binds the full configuration", () => self.run(config => {
    let app : AppConfig = config |> @config.bind_root()
    "\{app.ir.layout} \{app.pipeline.target}"
  }))
  setup.then1("the result is {string}", (expected : String) => {
    @expect.expect(self.result).to_equal(Some(expected))
  })
  setup.then0("binding fails with the key path error", () => {
    guard self.error is Some(InvalidKeyPath(..)) else {
      fail("expected the key path error")
    }
  })
  setup.then1("binding fails with a decode error at {string}", (
    path : String,
  ) => {
    guard self.error is Some(Decode(failure~)) else {
      fail("expected a decode error")
    }
    @expect.expect(failure.at.map(at => at.path.to_string())).to_equal([path])
  })
  setup.then1("the error text is {string}", (expected : String) => {
    @expect.expect(self.message()).to_equal(expected)
  })
  setup.then0("the error text has no backslash", () => {
    @expect.expect(self.message().contains("\\")).to_be_false()
  })
}

///|
let feature : String =
  #|Feature: Bind configuration to typed values
  #|  Scenario: Section decodes into a record
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      [ir]
  #|      layout = "single-file"
  #|      strict_mode = true
  #|      """
  #|    When the application binds "ir" to the IR record
  #|    Then the result is "single-file true"
  #|
  #|  Scenario: Empty key text is rejected
  #|    When the application binds "" to the IR record
  #|    Then binding fails with the key path error
  #|
  #|  Scenario: Root binding fills each top-level table
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      ir.layout = "tree"
  #|      ir.strict_mode = false
  #|      pipeline.target = "js"
  #|      """
  #|    When the application binds the full configuration
  #|    Then the result is "tree js"
  #|
  #|  Scenario: Root binding error names the full path
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      ir.layout = "tree"
  #|      ir.strict_mode = "yes"
  #|      pipeline.target = "js"
  #|      """
  #|    When the application binds the full configuration
  #|    Then binding fails with a decode error at "ir.strict_mode"
  #|
  #|  Scenario: Optional target with no section
  #|    When the application binds "telemetry" to an optional IR record
  #|    Then the result is "none"
  #|
  #|  Scenario: Required target with no section
  #|    When the application binds "ir" to the IR record
  #|    Then binding fails with a decode error at "ir"
  #|    And the error text is "ir: Expected object to deserialize IrOptions (not set by any source)"
  #|
  #|  Scenario: Wrong type in a file
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      ir.layout = "tree"
  #|      ir.strict_mode = "yes"
  #|      """
  #|    When the application binds "ir" to the IR record
  #|    Then binding fails with a decode error at "ir.strict_mode"
  #|    And the error text is "ir.strict_mode: Bool::from_json: expected boolean (set in project /repo/morphir.toml)"
  #|
  #|  Scenario: Failure inside a list
  #|    Given the "workspace-member" file "/repo/app/morphir.toml":
  #|      """toml
  #|      targets = [{ level = 1 }, { level = "high" }]
  #|      """
  #|    When the application binds "targets" to a list of targets
  #|    Then binding fails with a decode error at "targets[1].level"
  #|    And the error text is "targets[1].level: Int::from_json: expected number (set in workspace-member /repo/app/morphir.toml)"
  #|
  #|  Scenario: File role name in the error
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      ir.layout = "tree"
  #|      """
  #|    And the "user-override" file "/repo/morphir.user.toml":
  #|      """toml
  #|      ir.strict_mode = "yes"
  #|      """
  #|    When the application binds "ir" to the IR record
  #|    Then the error text is "ir.strict_mode: Bool::from_json: expected boolean (set in user-override /repo/morphir.user.toml)"
  #|
  #|  Scenario: Windows path uses forward slashes
  #|    Given the "project" file "C:/repo/morphir.toml":
  #|      """toml
  #|      ir.layout = "tree"
  #|      ir.strict_mode = "yes"
  #|      """
  #|    When the application binds "ir" to the IR record
  #|    Then the error text is "ir.strict_mode: Bool::from_json: expected boolean (set in project C:/repo/morphir.toml)"
  #|    And the error text has no backslash

///|
/// Run each scenario of `text` with a fresh world and fail on the first scenario
/// that does not pass. The synchronous runner steps run on all four targets.
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
test "configuration binding acceptance scenarios" {
  run_scenarios(() => BindingWorld::BindingWorld(), "binding.feature", feature)
}

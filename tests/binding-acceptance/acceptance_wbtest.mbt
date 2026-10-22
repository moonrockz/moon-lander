///|
priv struct IrOptions {
  layout : String
  strict_mode : Bool
} derive(FromJson, ToJson)

///|
priv struct PipelineOptions {
  components : Array[String]
} derive(FromJson, ToJson)

///|
/// A default whose JSON form does not decode: `level` is text.
priv struct Mode {
  level : Int
} derive(FromJson)

///|
impl ToJson for Mode with to_json(_) {
  { "level": "high" }
}

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
priv struct Service {
  url : String
  token : String
} derive(FromJson)

///|
priv struct ApiService {
  api_token : String
} derive(FromJson)

///|
priv struct PipelineRules {
  target : String
  validation : String
} derive(FromJson)

///|
impl @config.Validate for PipelineRules with validate(self) {
  let found = []
  if self.target == "" {
    found.push(@config.violation(["target"], "must not be empty"))
  }
  if !["strict", "lenient"].contains(self.validation) {
    found.push(@config.violation(["validation"], "must be strict or lenient"))
  }
  found
}

///|
/// The IR record with the rule that a split layout needs strict mode.
priv struct IrRules {
  layout : String
  strict_mode : Bool
} derive(FromJson)

///|
impl @config.Validate for IrRules with validate(self) {
  if self.layout == "split" && !self.strict_mode {
    [
      @config.violation(
        ["layout", "strict_mode"],
        "split layout needs strict_mode = true",
      ),
    ]
  } else {
    []
  }
}

///|
/// A record with no validation rules.
priv struct Telemetry {
  endpoint : String
} derive(FromJson)

///|
impl @config.Validate for Telemetry

///|
/// The files of one scenario, the loaded configuration, and the outcome of the
/// last binding: a result text or an error.
priv struct BindingWorld {
  files : Array[(String, @config.FileRole, String)]
  vars : Map[String, String]
  mut result : String?
  mut error : @config.ConfigError?
}

///|
fn BindingWorld::BindingWorld() -> BindingWorld {
  { files: [], vars: {}, result: None, error: None }
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
  if !self.vars.is_empty() {
    builder = builder
      |> @config.env(prefix="MORPHIR", selection=Explicit(self.vars))
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
  setup.given2("the environment variable {string} is {string}", (
    name : String,
    value : String,
  ) => self.vars[name] = value)
  setup.when1("the application binds {string} over the IR default", (
    key : String,
  ) => self.run(config => {
    let ir = config
      |> @config.bind_or(key, ({ layout: "single-file", strict_mode: false } : IrOptions))
    "\{ir.layout} \{ir.strict_mode}"
  }))
  setup.when2("the application binds {string} over the text default {string}", (
    key : String,
    default : String,
  ) => self.run(config => config |> @config.bind_or(key, default)))
  setup.when1("the application binds {string} over the component default", (
    key : String,
  ) => self.run(config => {
    let pipeline = config
      |> @config.bind_or(key, ({ components: ["parse", "typecheck"] } : PipelineOptions))
    pipeline.components.join(",")
  }))
  setup.when1("the application binds {string} to an integer", (key : String) => self.run(config => {
    let value : Int = config |> @config.bind(key)
    value.to_string()
  }))
  setup.when1("the application binds {string} over a default that does not decode", (
    key : String,
  ) => self.run(config => {
    let mode = config |> @config.bind_or(key, ({ level: 1 } : Mode))
    mode.level.to_string()
  }))
  setup.when1("the application binds {string} to the service record", (
    key : String,
  ) => self.run(config => {
    let service : Service = config |> @config.bind(key)
    "\{service.url} \{service.token}"
  }))
  setup.when1("the application binds {string} to the API record", (
    key : String,
  ) => self.run(config => {
    let service : ApiService = config |> @config.bind(key)
    service.api_token
  }))
  setup.when1("the application gets the options of {string} with pipeline rules", (
    key : String,
  ) => self.run(config => {
    let options : @config.Options[PipelineRules] = @config.options(config, key)
    options.value.target
  }))
  setup.when1("the application gets the options of {string} with IR rules", (
    key : String,
  ) => self.run(config => {
    let options : @config.Options[IrRules] = @config.options(config, key)
    "\{options.key} \{options.value.layout} \{options.value.strict_mode}"
  }))
  setup.when1("the application gets the options of {string} with no rules", (
    key : String,
  ) => self.run(config => {
    let options : @config.Options[Telemetry] = @config.options(config, key)
    options.value.endpoint
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
  setup.then1("binding fails with a validation error at {string}", (
    paths : String,
  ) => {
    guard self.error is Some(Validation(failures~)) else {
      fail("expected a validation error")
    }
    @expect.expect(
      failures
      .map(failure => failure.at.map(at => at.path.to_string()).join(" and "))
      .join(", "),
    ).to_equal(paths)
  })
  setup.then0("the application gets no options value", () => {
    @expect.expect(self.result).to_equal(None)
  })
  setup.then1("the error text does not contain {string}", (text : String) => {
    @expect.expect(self.message().contains(text)).to_be_false()
  })
  setup.then1("the system does not read {string}", (variable : String) => {
    // The variable is in the run, so a resolved secret would reach the text.
    guard self.vars.get(variable) is Some(secret) else {
      fail("the scenario does not set \{variable}")
    }
    @expect.expect(self.result).to_equal(None)
    @expect.expect(self.message().contains(secret)).to_be_false()
  })
  setup.then1("the error text is:", (expected : @moonspec.DocString) => {
    @expect.expect(self.message()).to_equal(expected.content)
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
  #|
  #|  Scenario: Value from an environment variable
  #|    Given the environment variable "MORPHIR_IR__STRICT_MODE" is "maybe"
  #|    And the environment variable "MORPHIR_IR__LAYOUT" is "tree"
  #|    When the application binds "ir" to the IR record
  #|    Then the error text is "ir.strict_mode: Bool::from_json: expected boolean (set in environment MORPHIR_IR__STRICT_MODE)"
  #|
  #|  Scenario: Unset keys keep default values
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      ir.strict_mode = true
  #|      """
  #|    When the application binds "ir" over the IR default
  #|    Then the result is "single-file true"
  #|
  #|  Scenario: Scalar default
  #|    When the application binds "mode" over the text default "safe"
  #|    Then the result is "safe"
  #|
  #|  Scenario: Scalar default with a configured value
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      mode = "fast"
  #|      """
  #|    When the application binds "mode" over the text default "safe"
  #|    Then the result is "fast"
  #|
  #|  Scenario: Configured list replaces default list
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      pipeline.components = ["parse"]
  #|      """
  #|    When the application binds "pipeline" over the component default
  #|    Then the result is "parse"
  #|
  #|  Scenario: No section uses the full default
  #|    When the application binds "ir" over the IR default
  #|    Then the result is "single-file false"
  #|
  #|  Scenario: Required field with no value
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      ir.strict_mode = true
  #|      """
  #|    When the application binds "ir" to the IR record
  #|    Then binding fails with a decode error at "ir"
  #|    And the error text is "ir: Missing field layout (table set in project /repo/morphir.toml)"
  #|
  #|  Scenario: Unset scalar key
  #|    When the application binds "server.port" to an integer
  #|    Then the error text is "server.port: Int::from_json: expected number (not set by any source)"
  #|
  #|  Scenario: Bad default value
  #|    When the application binds "mode" over a default that does not decode
  #|    Then the error text is "mode.level: Int::from_json: expected number (from the bind default)"
  #|
  #|  Scenario: Wrong type for a secret-like key
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      service.api_token = 42
  #|      """
  #|    When the application binds "service" to the API record
  #|    Then binding fails with a decode error at "service.api_token"
  #|    And the error text is "service.api_token: String::from_json: expected string (set in project /repo/morphir.toml)"
  #|    And the error text does not contain "42"
  #|
  #|  Scenario: Secret reference into a text field
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      service.url = "https://example.org"
  #|      service.token = { env = "SERVICE_TOKEN" }
  #|      """
  #|    And the environment variable "SERVICE_TOKEN" is "s3cret-value"
  #|    When the application binds "service" to the service record
  #|    Then binding fails with a decode error at "service.token"
  #|    And the error text is "service.token: is a secret reference; bind it as SecretRef with bind_with (set in project /repo/morphir.toml)"
  #|    And the system does not read "SERVICE_TOKEN"
  #|
  #|  Scenario: Two failures in one section
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      pipeline.target = ""
  #|      pipeline.validation = "loose"
  #|      """
  #|    When the application gets the options of "pipeline" with pipeline rules
  #|    Then binding fails with a validation error at "pipeline.target, pipeline.validation"
  #|    And the error text is:
  #|      """
  #|      pipeline.target: must not be empty (set in project /repo/morphir.toml)
  #|      pipeline.validation: must be strict or lenient (set in project /repo/morphir.toml)
  #|      """
  #|
  #|  Scenario: Cross-field failure
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      ir.layout = "split"
  #|      """
  #|    And the "user-override" file "/repo/morphir.user.toml":
  #|      """toml
  #|      ir.strict_mode = false
  #|      """
  #|    When the application gets the options of "ir" with IR rules
  #|    Then binding fails with a validation error at "ir.layout and ir.strict_mode"
  #|    And the error text is:
  #|      """
  #|      ir.layout: split layout needs strict_mode = true (set in project /repo/morphir.toml)
  #|      ir.strict_mode: split layout needs strict_mode = true (set in user-override /repo/morphir.user.toml)
  #|      """
  #|    And the application gets no options value
  #|
  #|  Scenario: Type without rules
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      telemetry.endpoint = ""
  #|      """
  #|    When the application gets the options of "telemetry" with no rules
  #|    Then the result is ""
  #|
  #|  Scenario: Options from a valid section
  #|    Given the "project" file "/repo/morphir.toml":
  #|      """toml
  #|      ir.layout = "split"
  #|      ir.strict_mode = true
  #|      """
  #|    When the application gets the options of "ir" with IR rules
  #|    Then the result is "ir split true"

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

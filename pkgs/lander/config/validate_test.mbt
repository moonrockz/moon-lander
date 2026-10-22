///|
struct PipelineRules {
  target : String
  validation : String
  ir : IrRules
} derive(FromJson, ToJson, Debug, Eq)

///|
struct IrRules {
  layout : String
  strict_mode : Bool
} derive(FromJson, ToJson, Debug, Eq)

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
impl @config.Validate for PipelineRules with validate(self) {
  let found = []
  if self.target == "" {
    found.push(@config.violation(["target"], "must not be empty"))
  }
  if !["strict", "lenient"].contains(self.validation) {
    found.push(@config.violation(["validation"], "must be strict or lenient"))
  }
  found.append(@config.nested("ir", @config.Validate::validate(self.ir)))
  found
}

///|
struct Port {
  port : Int
} derive(FromJson, Debug, Eq)

///|
impl @config.Validate for Port with validate(self) {
  if self.port > 0 {
    []
  } else {
    [@config.violation(["port"], "must be positive")]
  }
}

///|
/// A type with no rules: the default `validate` applies.
struct Plain {
  name : String
} derive(FromJson, Debug, Eq)

///|
impl @config.Validate for Plain

///|
/// A rule over the whole value, with no field.
struct Whole {
  name : String
} derive(FromJson, Debug, Eq)

///|
impl @config.Validate for Whole with validate(_) {
  [@config.violation([], "is not allowed here")]
}

///|
fn validation_failures(
  run : () -> Unit raise @config.ConfigError,
) -> (Array[@config.BindFailure], String) {
  try run() catch {
    Validation(failures~) as error => (failures, error.message())
    error => abort("expected a validation error, got \{error.message()}")
  } noraise {
    _ => abort("expected a validation error")
  }
}

///|
fn paths(failure : @config.BindFailure) -> Array[String] {
  failure.at.map(at => at.path.to_string())
}

///|
test "violation and nested build relative paths" {
  @expect.expect(@config.violation(["a", "b"], "bad")).to_equal({
    at: [[Field("a")], [Field("b")]],
    detail: "bad",
  })
  @expect.expect(@config.violation([], "bad").at).to_equal([])
  let found = @config.nested("ir", [
    @config.violation(["layout"], "bad"),
    @config.violation([], "whole"),
  ])
  @expect.expect(found.map(violation => violation.at)).to_equal([
    [[Field("ir"), Field("layout")]],
    [[Field("ir")]],
  ])
}

///|
test "maps, lists and options prefix the paths of their values" {
  let ports : Map[String, Port] = { "ts": { port: 1 }, "scala": { port: 0 } }
  @expect.expect(@config.Validate::validate(ports).map(v => v.at)).to_equal([
    [[Field("scala"), Field("port")]],
  ])
  let list : Array[Port] = [{ port: 1 }, { port: -1 }, { port: 0 }]
  @expect.expect(@config.Validate::validate(list).map(v => v.at)).to_equal([
    [[Index(1), Field("port")]],
    [[Index(2), Field("port")]],
  ])
  let some : Port? = Some({ port: 0 })
  let none : Port? = None
  @expect.expect(@config.Validate::validate(some).length()).to_equal(1)
  @expect.expect(@config.Validate::validate(none)).to_equal([])
}

///|
test "Type without rules" {
  let config = @config.build([
    @config.in_memory_pairs([("plain.name", @config.string("x"))]),
  ])
  let options : @config.Options[Plain] = @config.options(config, "plain")
  @expect.expect(options.value).to_equal({ name: "x" })
}

///|
test "Two failures in one section" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      (
        #|pipeline.target = ""
        #|pipeline.validation = "loose"
        #|pipeline.ir.layout = "tree"
        #|pipeline.ir.strict_mode = true
      ),
    ),
  ])
  let (failures, text) = validation_failures(() => {
    let _ : @config.Options[PipelineRules] = @config.options(config, "pipeline")
  })
  @expect.expect(failures.map(paths)).to_equal([
    ["pipeline.target"],
    ["pipeline.validation"],
  ])
  @expect.expect(text).to_equal(
    (
      #|pipeline.target: must not be empty (set in project /repo/morphir.toml)
      #|pipeline.validation: must be strict or lenient (set in project /repo/morphir.toml)
    ),
  )
}

///|
test "Cross-field failure" {
  let config = load_files([
    ("/repo/morphir.toml", Workspace, "ir.layout = \"split\""),
    ("/repo/morphir.user.toml", UserOverride, "ir.strict_mode = false"),
  ])
  let (failures, text) = validation_failures(() => {
    config
    |> @config.bind_or("ir", ({ layout: "tree", strict_mode: true } : IrRules))
    |> @config.validated(config, "ir")
    |> ignore
  })
  @expect.expect(failures.map(paths)).to_equal([
    ["ir.layout", "ir.strict_mode"],
  ])
  @expect.expect(text).to_equal(
    (
      #|ir.layout: split layout needs strict_mode = true (set in project /repo/morphir.toml)
      #|ir.strict_mode: split layout needs strict_mode = true (set in user-override /repo/morphir.user.toml)
    ),
  )
}

///|
test "a failure inside a list names the index and the list sources" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      "servers = [{ port = 80 }, { port = 0 }]",
    ),
  ])
  let (failures, text) = validation_failures(() => {
    let _ : @config.Options[Array[Port]] = @config.options(config, "servers")
  })
  @expect.expect(failures.map(paths)).to_equal([["servers[1].port"]])
  @expect.expect(text).to_equal(
    "servers[1].port: must be positive (set in project /repo/morphir.toml)",
  )
}

///|
test "a rule over the whole value names the section" {
  let config = load_files([
    ("/repo/morphir.toml", Workspace, "whole.name = \"x\""),
  ])
  let (failures, _) = validation_failures(() => {
    let _ : @config.Options[Whole] = @config.options(config, "whole")
  })
  @expect.expect(failures.map(paths)).to_equal([["whole"]])
  @expect.expect(failures[0].at[0].blame is Table(_)).to_be_true()
}

///|
test "Options from a valid section" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      "ir.layout = \"split\"\nir.strict_mode = true",
    ),
  ])
  let options = config
    |> @config.bind_or("ir", ({ layout: "tree", strict_mode: false } : IrRules))
    |> @config.validated(config, "ir", name="main")
  @expect.expect(options.value).to_equal({ layout: "split", strict_mode: true })
  @expect.expect(options.key.to_string()).to_equal("ir")
  @expect.expect(options.name).to_equal(Some("main"))
}

///|
test "No options value after a validation failure" {
  let config = load_files([
    ("/repo/morphir.toml", Workspace, "servers = [{ port = 0 }]"),
  ])
  let mut options : @config.Options[Array[Port]]? = None
  try {
    options = Some(@config.options(config, "servers"))
  } catch {
    Validation(..) => ()
    error => fail("expected a validation error, got \{error.message()}")
  }
  @expect.expect(options is None).to_be_true()
}

///|
test "a decode failure stops options before validation" {
  let config = load_files([
    ("/repo/morphir.toml", Workspace, "servers = [{ port = \"x\" }]"),
  ])
  try {
    let _ : @config.Options[Array[Port]] = @config.options(config, "servers")
  } catch {
    Decode(..) => ()
    error => fail("expected a decode error, got \{error.message()}")
  } noraise {
    _ => fail("expected a decode error")
  }
}

///|
struct Backend {
  out_dir : String
  level : Int
} derive(FromJson, ToJson, Debug, Eq)

///|
impl @config.Validate for Backend with validate(self) {
  if self.level > 0 {
    []
  } else {
    [@config.violation(["level"], "must be positive")]
  }
}

///|
fn backend_default() -> Backend {
  { out_dir: "out", level: 1 }
}

///|
fn bind_backend(
  config : @config.Config,
  key : String,
) -> @config.Options[Backend] raise @config.ConfigError {
  config
  |> @config.bind_or(key, backend_default())
  |> @config.validated(config, key)
}

///|
test "Each child is a named instance" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      (
        #|backends.ts.out_dir = "dist/ts"
        #|backends.scala.level = 2
      ),
    ),
  ])
  let backends = @config.named(config, "backends", bind_backend)
  @expect.expect(backends.names()).to_equal(["ts", "scala"])
  guard backends.get("ts") is Some(ts) else { fail("no ts instance") }
  @expect.expect(ts.name).to_equal(Some("ts"))
  @expect.expect(ts.key.to_string()).to_equal("backends.ts")
  @expect.expect(ts.value).to_equal({ out_dir: "dist/ts", level: 1 })
  guard backends.get("scala") is Some(scala) else { fail("no scala instance") }
  @expect.expect(scala.value).to_equal({ out_dir: "out", level: 2 })
  @expect.expect(backends.get("java") is None).to_be_true()
}

///|
test "Failures in two instances" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      (
        #|backends.ts.level = "high"
        #|backends.scala.level = 0
        #|backends.java.level = 3
      ),
    ),
  ])
  let (failures, text) = validation_failures(() => {
    @config.named(config, "backends", bind_backend) |> ignore
  })
  @expect.expect(failures.map(paths)).to_equal([
    ["backends.ts.level"],
    ["backends.scala.level"],
  ])
  @expect.expect(text).to_equal(
    (
      #|backends.ts.level: Int::from_json: expected number (set in project /repo/morphir.toml)
      #|backends.scala.level: must be positive (set in project /repo/morphir.toml)
    ),
  )
}

///|
test "an absent section gives no named instances" {
  let config = load_files([])
  let backends = @config.named(config, "backends", bind_backend)
  @expect.expect(backends.names()).to_equal([])
}

///|
test "a child name with a dot keeps its quotes in the key text" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      "backends.\"eu.west\".level = 4",
    ),
  ])
  let keys = []
  let backends = @config.named(config, "backends", (config, key) => {
    keys.push(key)
    bind_backend(config, key)
  })
  @expect.expect(keys).to_equal(["backends.\"eu.west\""])
  guard backends.get("eu.west") is Some(west) else { fail("no instance") }
  @expect.expect(west.key.names()).to_equal(["backends", "eu.west"])
  @expect.expect(west.value.level).to_equal(4)
}

///|
test "a section that is not a table fails to decode" {
  let config = load_files([
    ("/repo/morphir.toml", Workspace, "backends = [\"ts\"]"),
  ])
  let (failure, text) = decode_failure(() => {
    @config.named(config, "backends", bind_backend) |> ignore
  })
  @expect.expect(failure.at.map(at => at.path.to_string())).to_equal([
    "backends",
  ])
  @expect.expect(text).to_equal(
    "backends: must be a table of named instances (set in project /repo/morphir.toml)",
  )
}

///|
test "other errors of the binder pass through" {
  let config = load_files([
    ("/repo/morphir.toml", Workspace, "backends.ts.level = 1"),
  ])
  try {
    let _ : @config.NamedOptions[Backend] = @config.named(
      config,
      "backends",
      (_, _) => raise @config.KeyNotFound(key=@config.KeyPath::parse("x")),
    )
  } catch {
    KeyNotFound(..) => ()
    error => fail("expected KeyNotFound, got \{error.message()}")
  } noraise {
    _ => fail("expected an error")
  }
}

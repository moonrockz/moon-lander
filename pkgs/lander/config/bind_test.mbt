///|
struct IrOptions {
  layout : String
  strict_mode : Bool
} derive(FromJson, ToJson, Debug, Eq)

///|
struct Pipeline {
  target : String
} derive(FromJson, Debug, Eq)

///|
struct AppConfig {
  ir : IrOptions
  pipeline : Pipeline
} derive(FromJson, Debug, Eq)

///|
struct Target {
  name : String
  level : Int
} derive(FromJson, Debug, Eq)

///|
struct Server {
  port : Int
} derive(FromJson, Debug, Eq)

///|
/// Load TOML files over a complete tree. Each file is a path, a role, and text.
fn load_files(
  files : Array[(String, @config.FileRole, String)],
) -> @config.Config raise @config.ConfigError {
  let mut builder = @config.builder() |> @config.format(@toml.format())
  let mut tree = @config.FileTree::new(complete=true)
  for file in files {
    let (path, role, text) = file
    builder = builder |> @config.file(path, role~)
    tree = tree.with_file(path, text)
  }
  guard @config.load(builder, tree) is Done(config) else {
    abort("a complete tree never asks for files")
  }
  config
}

///|
fn decode_failure(
  run : () -> Unit raise @config.ConfigError,
) -> (@config.BindFailure, String) {
  try run() catch {
    Decode(failure~) as error => (failure, error.message())
    error => abort("expected a decode error, got \{error.message()}")
  } noraise {
    _ => abort("expected a decode error")
  }
}

///|
test "Section decodes into a record" {
  let config = @config.build([
    @config.in_memory_pairs([
      ("ir.layout", @config.string("single-file")),
      ("ir.strict_mode", @config.bool(true)),
    ]),
  ])
  let ir : IrOptions = config |> @config.bind("ir")
  @expect.expect(ir).to_equal({ layout: "single-file", strict_mode: true })
  let same : IrOptions = config.bind("ir")
  @expect.expect(same).to_equal(ir)
}

///|
test "Empty key text is rejected" {
  let config = @config.build([])
  try {
    let _ : IrOptions = config |> @config.bind("")
  } catch {
    InvalidKeyPath(text~, ..) => @expect.expect(text).to_equal("")
    error => fail("expected a key path error, got \{error.message()}")
  } noraise {
    _ => fail("expected a key path error")
  }
}

///|
test "Map type receives each child key" {
  let config = @config.build([
    @config.ConfigSource::defaults({
      "backends": { "ts": { "port": 1 }, "scala": { "port": 2 } },
    }),
  ])
  let backends : Map[String, Server] = config |> @config.bind("backends")
  @expect.expect(backends).to_equal({ "ts": { port: 1 }, "scala": { port: 2 } })
}

///|
test "Root binding fills each top-level table" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      (
        #|[ir]
        #|layout = "tree"
        #|strict_mode = false
        #|[pipeline]
        #|target = "js"
      ),
    ),
  ])
  let app : AppConfig = config |> @config.bind_root()
  @expect.expect(app).to_equal({
    ir: { layout: "tree", strict_mode: false },
    pipeline: { target: "js" },
  })
}

///|
test "Root binding error names the full path" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      (
        #|ir.layout = "tree"
        #|ir.strict_mode = "yes"
        #|pipeline.target = "js"
      ),
    ),
  ])
  let (failure, message) = decode_failure(() => {
    let _ : AppConfig = config |> @config.bind_root()
  })
  @expect.expect(failure.at[0].path.to_string()).to_equal("ir.strict_mode")
  @expect.expect(message).to_equal(
    "ir.strict_mode: Bool::from_json: expected boolean (set in project /repo/morphir.toml)",
  )
}

///|
test "Optional target with no section" {
  let config = @config.build([])
  let telemetry : Server? = config |> @config.bind("telemetry")
  @expect.expect(telemetry).to_equal(None)
}

///|
test "Required target with no section" {
  let config = @config.build([])
  let (failure, message) = decode_failure(() => {
    let _ : IrOptions = config |> @config.bind("ir")
  })
  @expect.expect(failure.at[0].blame).to_equal(Unset)
  @expect.expect(message).to_start_with("ir: ")
  @expect.expect(message).to_end_with("(not set by any source)")
}

///|
test "Wrong type in a file" {
  let config = load_files([
    ("/repo/morphir.toml", Workspace, "ir.layout = \"tree\"\nir.strict_mode = \"yes\""),
  ])
  let (failure, _) = decode_failure(() => {
    let _ : IrOptions = config |> @config.bind("ir")
  })
  @expect.expect(failure.at[0].path.to_string()).to_equal("ir.strict_mode")
  guard failure.at[0].blame is Set([origin]) else { fail("expected one origin") }
  @expect.expect(origin.location).to_equal(Some("/repo/morphir.toml"))
}

///|
test "Failure inside a list" {
  let config = load_files([
    ("/repo/base.toml", Workspace, "targets = [{ name = \"a\", level = 1 }]"),
    (
      "/repo/app/morphir.toml",
      Member,
      "targets = [{ name = \"a\", level = 1 }, { name = \"b\", level = \"high\" }]",
    ),
  ])
  let (failure, message) = decode_failure(() => {
    let _ : Array[Target] = config |> @config.bind("targets")
  })
  @expect.expect(failure.at[0].path.to_string()).to_equal("targets[1].level")
  @expect.expect(message).to_equal(
    "targets[1].level: Int::from_json: expected number (set in workspace-member /repo/app/morphir.toml)",
  )
}

///|
test "table blame lists its sources in merge order" {
  let config = load_files([
    ("/repo/morphir.toml", Workspace, "ir.strict_mode = true"),
    ("/repo/morphir.user.toml", UserOverride, "ir.strict_mode = false"),
    ("/repo/extra.toml", UserOverride, "ir.mode = \"x\""),
  ])
  let (failure, message) = decode_failure(() => {
    let _ : IrOptions = config |> @config.bind("ir")
  })
  @expect.expect(failure.at[0].path.to_string()).to_equal("ir")
  @expect.expect(message).to_equal(
    "ir: Missing field layout (table set in user-override /repo/morphir.user.toml, user-override /repo/extra.toml)",
  )
}

///|
test "Unset scalar key" {
  let config = @config.build([])
  let (_, message) = decode_failure(() => {
    let _ : Int = config |> @config.bind("server.port")
  })
  @expect.expect(message).to_equal(
    "server.port: Int::from_json: expected number (not set by any source)",
  )
}

///|
test "File role name in the error" {
  let config = load_files([
    ("/repo/morphir.toml", Workspace, "ir.layout = \"tree\""),
    ("/repo/morphir.user.toml", UserOverride, "ir.strict_mode = \"yes\""),
  ])
  let (_, message) = decode_failure(() => {
    let _ : IrOptions = config |> @config.bind("ir")
  })
  @expect.expect(message).to_equal(
    "ir.strict_mode: Bool::from_json: expected boolean (set in user-override /repo/morphir.user.toml)",
  )
}

///|
test "Windows path uses forward slashes" {
  let config = load_files([
    ("C:/repo/morphir.toml", Workspace, "ir.layout = \"tree\"\nir.strict_mode = \"yes\""),
  ])
  let (_, message) = decode_failure(() => {
    let _ : IrOptions = config |> @config.bind("ir")
  })
  @expect.expect(message).to_equal(
    "ir.strict_mode: Bool::from_json: expected boolean (set in project C:/repo/morphir.toml)",
  )
  @expect.expect(message.contains("\\")).to_equal(false)
}

///|
test "decode paths keep keys with slash, tilde, and dot" {
  let path = (json : Json) => {
    let config = @config.build([@config.ConfigSource::defaults(json)])
    let (failure, _) = decode_failure(() => {
      let _ : Map[String, Server] = config |> @config.bind("servers")
    })
    failure.at[0].path.to_string()
  }
  @expect.expect(path({ "servers": { "a/b": { "port": "x" } } })).to_equal(
    "servers.a/b.port",
  )
  @expect.expect(path({ "servers": { "t~x": { "port": "x" } } })).to_equal(
    "servers.t~x.port",
  )
  @expect.expect(path({ "servers": { "eu.west": { "port": "x" } } })).to_equal(
    "servers.\"eu.west\".port",
  )
}

///|
test "a root error in a list has no key" {
  let config = @config.build([
    @config.ConfigSource::defaults({ "a": 1 }),
  ])
  let (failure, _) = decode_failure(() => {
    let _ : Array[Int] = config |> @config.bind_root()
  })
  @expect.expect(failure.at[0].path.to_string()).to_equal("(root)")
  @expect.expect(failure.at[0].blame).to_equal(
    Table([{ kind: Defaults, source: "defaults", priority: 0, location: None }]),
  )
}

///|
test "binding does not change the configuration" {
  let config = @config.build([
    @config.in_memory_pairs([("ir.layout", @config.string("tree"))]),
  ])
  let before = config.value()
  let _ : Server? = (config |> @config.bind("ir.layout")) catch { _ => None }
  @expect.expect(config.value()).to_equal(before)
}

///|
test "Required field with no value" {
  let config = load_files([
    ("/repo/morphir.toml", Workspace, "ir.strict_mode = true"),
  ])
  let (failure, message) = decode_failure(() => {
    let _ : IrOptions = config |> @config.bind("ir")
  })
  @expect.expect(failure.at[0].path.to_string()).to_equal("ir")
  @expect.expect(message).to_equal(
    "ir: Missing field layout (table set in project /repo/morphir.toml)",
  )
}

///|
struct PipelineOptions {
  components : Array[String]
  timeout : Int?
} derive(FromJson, ToJson, Debug, Eq)

///|
test "Unset keys keep default values" {
  let config = @config.build([
    @config.in_memory_pairs([("ir.strict_mode", @config.bool(true))]),
  ])
  let default : IrOptions = { layout: "single-file", strict_mode: false }
  let ir = config |> @config.bind_or("ir", default)
  @expect.expect(ir).to_equal({ layout: "single-file", strict_mode: true })
  @expect.expect(default).to_equal({ layout: "single-file", strict_mode: false })
}

///|
test "Scalar default" {
  let empty = @config.build([])
  @expect.expect(empty |> @config.bind_or("mode", "safe")).to_equal("safe")
  let set = @config.build([
    @config.in_memory_pairs([("mode", @config.string("fast"))]),
  ])
  @expect.expect(set.bind_or("mode", "safe")).to_equal("fast")
}

///|
test "Configured list replaces default list" {
  let config = @config.build([
    @config.in_memory_pairs([
      ("pipeline.components", @config.list([@config.string("parse")])),
    ]),
  ])
  let pipeline = config
    |> @config.bind_or("pipeline", {
      components: ["parse", "typecheck"],
      timeout: Some(30),
    })
  @expect.expect(pipeline).to_equal({ components: ["parse"], timeout: Some(30) })
}

///|
test "List default" {
  let config = @config.build([])
  @expect.expect(config |> @config.bind_or("targets", ["js"])).to_equal(["js"])
}

///|
test "No section uses the full default" {
  let config = @config.build([])
  let default : IrOptions = { layout: "tree", strict_mode: true }
  @expect.expect(config |> @config.bind_or("ir", default)).to_equal(default)
}

///|
test "a null overlay keeps the default" {
  let config = @config.build([
    @config.ConfigSource::defaults({ "ir": { "layout": null } }),
  ])
  let default : IrOptions = { layout: "tree", strict_mode: true }
  @expect.expect(config |> @config.bind_or("ir", default)).to_equal(default)
}

///|
test "a None field of the default takes the configured value" {
  let config = @config.build([
    @config.in_memory_pairs([("pipeline.timeout", @config.int(5))]),
  ])
  let pipeline = config
    |> @config.bind_or("pipeline", { components: [], timeout: None })
  @expect.expect(pipeline.timeout).to_equal(Some(5))
}

///|
struct Mode {
  level : Int
} derive(FromJson, Debug)

///|
/// A default whose JSON form does not decode as `Mode`.
struct BadMode {
  level : String
} derive(ToJson)

///|
impl ToJson for Mode with to_json(_) {
  ToJson::to_json(BadMode::{ level: "high" })
}

///|
test "Bad default value" {
  let config = @config.build([])
  let (failure, message) = decode_failure(() => {
    config |> @config.bind_or("mode", ({ level: 1 } : Mode)) |> ignore
  })
  @expect.expect(failure.at[0].blame).to_equal(Default)
  @expect.expect(message).to_equal(
    "mode.level: Int::from_json: expected number (from the bind default)",
  )
}

///|
test "a configured value over a default keeps the source blame" {
  let config = load_files([
    ("/repo/morphir.toml", Workspace, "ir.strict_mode = \"yes\""),
  ])
  let (failure, message) = decode_failure(() => {
    config
    |> @config.bind_or("ir", { layout: "tree", strict_mode: false })
    |> ignore
  })
  @expect.expect(failure.at[0].path.to_string()).to_equal("ir.strict_mode")
  @expect.expect(message).to_end_with("(set in project /repo/morphir.toml)")
}

///|
test "table blame keeps an environment source before a later source" {
  let config = @config.builder()
    |> @config.env(prefix="APP", selection=Explicit({ "APP_IR__MODE": "x" }))
    |> @config.overrides([("ir.strict_mode", @config.bool(true))])
    |> @config.load(@config.FileTree::new(complete=true))
    |> done
  let (_, message) = decode_failure(() => {
    let _ : IrOptions = config |> @config.bind("ir")
  })
  @expect.expect(message).to_equal(
    "ir: Missing field layout (table set in environment APP_IR__MODE, overrides)",
  )
}

///|
struct Tagged {
  name : String
  tag : String?
  labels : Map[String, Int]
} derive(FromJson, ToJson, Debug, Eq)

///|
fn tagged_default() -> Tagged {
  { name: "app", tag: None, labels: {} }
}

///|
/// A server whose decoder accepts `port` as an alias of `endpoint`, but whose
/// encoder writes only `endpoint`. A configured alias wins over the default.
struct Endpoint {
  endpoint : Int
} derive(ToJson, Debug, Eq)

///|
impl FromJson for Endpoint with from_json(json, path) {
  guard json is Object(fields) else {
    raise @json.JsonDecodeError((path, "Expected object"))
  }
  let value = match (fields.get("port"), fields.get("endpoint")) {
    (Some(value), _) | (None, Some(value)) => value
    (None, None) => raise @json.JsonDecodeError((path, "Missing field endpoint"))
  }
  { endpoint: @json.from_json(value) }
}

///|
fn unknown_key_failures(
  run : () -> Unit raise @config.ConfigError,
) -> (Array[@config.BindFailure], String) {
  validation_failures(run)
}

///|
test "Unknown key ignored by default" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      "ir.layout = \"tree\"\nir.strict_mod = true",
    ),
  ])
  let ir = config
    |> @config.bind_or("ir", ({ layout: "single-file", strict_mode: false } : IrOptions))
  @expect.expect(ir).to_equal({ layout: "tree", strict_mode: false })
}

///|
test "Unknown key rejected" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      "ir.layout = \"tree\"\nir.strict_mod = true",
    ),
  ])
  let (failures, text) = unknown_key_failures(() => {
    config
    |> @config.bind_or(
      "ir",
      ({ layout: "single-file", strict_mode: false } : IrOptions),
      unknown=Reject,
    )
    |> ignore
  })
  @expect.expect(failures.map(paths)).to_equal([["ir.strict_mod"]])
  @expect.expect(text).to_equal(
    "ir.strict_mod: is an unknown key (set in project /repo/morphir.toml)",
  )
}

///|
test "all unknown keys go into one error, a table once" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      (
        #|ir.layut = "tree"
        #|ir.extra.a = 1
        #|ir.extra.b = 2
      ),
    ),
  ])
  let (failures, text) = unknown_key_failures(() => {
    config.bind_or(
      "ir",
      ({ layout: "single-file", strict_mode: false } : IrOptions),
      unknown=Reject,
    )
    |> ignore
  })
  @expect.expect(failures.map(paths)).to_equal([["ir.layut"], ["ir.extra"]])
  @expect.expect(text).to_equal(
    (
      #|ir.layut: is an unknown key (set in project /repo/morphir.toml)
      #|ir.extra: is an unknown key (table set in project /repo/morphir.toml)
    ),
  )
}

///|
test "a None field and map keys are known" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      (
        #|svc.tag = "blue"
        #|svc.labels.team = 1
        #|svc.labels."eu.west" = 2
      ),
    ),
  ])
  let svc = config |> @config.bind_or("svc", tagged_default(), unknown=Reject)
  @expect.expect(svc.tag).to_equal(Some("blue"))
  @expect.expect(svc.labels).to_equal({ "team": 1, "eu.west": 2 })
  // The default leaves `tag` as `None`, which `ToJson` does not write; an
  // unset `tag` is not a configured key, so the check has nothing to report.
  let plain = load_files([("/repo/morphir.toml", Workspace, "svc.name = \"x\"")])
  @expect.expect(
    plain.bind_or("svc", tagged_default(), unknown=Reject).tag,
  ).to_equal(None)
}

///|
test "Accepted alias listed" {
  let config = load_files([
    ("/repo/morphir.toml", Workspace, "server.port = 8080"),
  ])
  let (failures, _) = unknown_key_failures(() => {
    config
    |> @config.bind_or("server", ({ endpoint: 80 } : Endpoint), unknown=Reject)
    |> ignore
  })
  @expect.expect(failures.map(paths)).to_equal([["server.port"]])
  let server = config
    |> @config.bind_or(
      "server",
      ({ endpoint: 80 } : Endpoint),
      unknown=RejectExcept(["port"]),
    )
  @expect.expect(server).to_equal({ endpoint: 8080 })
}

///|
test "a listed key accepts the keys below it" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      "ir.layout = \"tree\"\nir.legacy.mode = \"x\"\nir.legacy.flag = true",
    ),
  ])
  let ir = config
    |> @config.bind_or(
      "ir",
      ({ layout: "single-file", strict_mode: false } : IrOptions),
      unknown=RejectExcept(["legacy"]),
    )
  @expect.expect(ir.layout).to_equal("tree")
}

///|
test "a listed nested key works when the encoder leaves out its table" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      (
        #|ir.layout = "tree"
        #|ir.legacy.port = 1
        #|ir.legacy.host = "x"
        #|ir.old = [1]
      ),
    ),
  ])
  let (failures, _) = unknown_key_failures(() => {
    config
    |> @config.bind_or(
      "ir",
      ({ layout: "single-file", strict_mode: false } : IrOptions),
      unknown=RejectExcept(["legacy.port", "old.value"]),
    )
    |> ignore
  })
  @expect.expect(failures.map(paths)).to_equal([
    ["ir.legacy.host"],
    ["ir.old"],
  ])
}

///|
test "the check goes into list items" {
  let config = load_files([
    (
      "/repo/app/morphir.toml",
      Member,
      "targets = [{ name = \"a\", level = 1 }, { name = \"b\", levl = 2, level = 3 }]",
    ),
  ])
  let default : Array[Item] = []
  let (failures, text) = unknown_key_failures(() => {
    config |> @config.bind_or("targets", default, unknown=Reject) |> ignore
  })
  @expect.expect(failures.map(paths)).to_equal([["targets[1].levl"]])
  @expect.expect(text).to_equal(
    "targets[1].levl: is an unknown key (set in workspace-member /repo/app/morphir.toml)",
  )
  let targets = config
    |> @config.bind_or("targets", default, unknown=RejectExcept(["levl"]))
  @expect.expect(targets.length()).to_equal(2)
}

///|
struct Item {
  name : String
  level : Int
} derive(FromJson, ToJson, Debug, Eq)

///|
test "an absent section and a scalar section pass the check" {
  let config = load_files([("/repo/morphir.toml", Workspace, "mode = \"fast\"")])
  @expect.expect(config.bind_or("mode", "safe", unknown=Reject)).to_equal("fast")
  @expect.expect(config.bind_or("other", "safe", unknown=Reject)).to_equal(
    "safe",
  )
}

///|
test "a listed key path that does not parse raises the key path error" {
  let config = load_files([("/repo/morphir.toml", Workspace, "ir.layout = \"x\"")])
  try {
    config
    |> @config.bind_or(
      "ir",
      ({ layout: "single-file", strict_mode: false } : IrOptions),
      unknown=RejectExcept([""]),
    )
    |> ignore
  } catch {
    InvalidKeyPath(..) => ()
    error => fail("expected InvalidKeyPath, got \{error.message()}")
  } noraise {
    _ => fail("expected an error")
  }
}

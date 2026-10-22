///|
/// Load Ion text sources over a complete tree.
fn load_ion(
  files : Array[(String, @config.FileRole, String)],
) -> @config.Config raise @config.ConfigError {
  let mut builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.format(@ion_format.format())
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
/// A hand-written exact decoder with a `FromJson` part.
struct Billing {
  rate : @ion.Decimal
  starts : @ion.Timestamp
  max_items : Int64
  lock : @config.Sourced[String]
  layout : IrOptions
}

///|
impl @config.FromConfig for Billing with from_config(node) {
  {
    rate: node.get("rate"),
    starts: node.get("starts"),
    max_items: node.get("max_items"),
    lock: node.get("lock"),
    layout: node.child("layout").json(),
  }
}

///|
fn exact_failure(
  run : () -> Unit raise @config.ConfigError,
) -> (String, String) {
  let (failure, text) = decode_failure(run)
  (failure.at.map(at => at.path.to_string()).join(" "), text)
}

///|
test "bind a hand-written FromConfig record" {
  let config = load_ion([
    (
      "/repo/morphir.ion",
      Workspace,
      (
        #|{ billing: {
        #|  rate: 1.50d0,
        #|  starts: 2026-10-19T08:30:00.125+02:00,
        #|  max_items: 9007199254740993,
        #|  lock: "deps.lock",
        #|  layout: { layout: "split", strict_mode: true },
        #|} }
      ),
    ),
  ])
  let billing : Billing = config |> @config.bind_with("billing")
  @expect.expect(billing.rate.coefficient().to_string()).to_equal("150")
  @expect.expect(billing.rate.exponent()).to_equal(-2)
  @expect.expect(billing.starts.offset()).to_equal(Some(Known(120)))
  @expect.expect(billing.starts.precision()).to_equal(Second)
  guard billing.starts.fraction() is Some(fraction) else { fail("no fraction") }
  @expect.expect(fraction.exponent()).to_equal(-3)
  @expect.expect(billing.max_items).to_equal(9007199254740993L)
  @expect.expect(billing.lock.value).to_equal("deps.lock")
  guard billing.lock.blame is Set([origin]) else { fail("expected one origin") }
  @expect.expect(origin.location).to_equal(Some("/repo/morphir.ion"))
  @expect.expect(billing.layout).to_equal({ layout: "split", strict_mode: true })
}

///|
test "a FromJson part reports the full decode path" {
  let config = load_ion([
    (
      "/repo/morphir.ion",
      Workspace,
      (
        #|{ billing: {
        #|  rate: 1.5,
        #|  starts: 2026-10-19T,
        #|  max_items: 1,
        #|  lock: "x",
        #|  layout: { layout: "split", strict_mode: "yes" },
        #|} }
      ),
    ),
  ])
  let (path, text) = exact_failure(() => {
    let _ : Billing = config |> @config.bind_with("billing")
  })
  @expect.expect(path).to_equal("billing.layout.strict_mode")
  @expect.expect(text).to_equal(
    "billing.layout.strict_mode: Bool::from_json: expected boolean (set in project /repo/morphir.ion)",
  )
}

///|
test "Int rejects a fraction and Int64 keeps a large integer" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      "server.port = 80.5\nlimits.max = 9007199254740993\nlimits.big = 3000000000",
    ),
  ])
  let (path, text) = exact_failure(() => {
    let _ : Int = config |> @config.bind_with("server.port")
  })
  @expect.expect(path).to_equal("server.port")
  @expect.expect(text).to_equal(
    "server.port: expected int, found float (set in project /repo/morphir.toml)",
  )
  let max : Int64 = config |> @config.bind_with("limits.max")
  @expect.expect(max).to_equal(9007199254740993L)
  let (_, text) = exact_failure(() => {
    let _ : Int = config |> @config.bind_with("limits.big")
  })
  @expect.expect(text).to_equal(
    "limits.big: the integer is out of range for Int (set in project /repo/morphir.toml)",
  )
  let big : UInt64 = config |> @config.bind_with("limits.big")
  @expect.expect(big).to_equal(3000000000UL)
  let wide : @bigint.BigInt = config |> @config.bind_with("limits.max")
  @expect.expect(wide.to_string()).to_equal("9007199254740993")
}

///|
test "scalar impls read their Ion types" {
  let config = load_ion([
    (
      "/repo/morphir.ion",
      Workspace,
      (
        #|{ name: "app",
        #|mode: fast,
        #|on: true,
        #|ratio: 0.25e0,
        #|count: 3,
        #|exact: 2.5,
        #|negative: -1 }
      ),
    ),
  ])
  let name : String = config |> @config.bind_with("name")
  let mode : String = config |> @config.bind_with("mode")
  let on : Bool = config |> @config.bind_with("on")
  let ratio : Double = config |> @config.bind_with("ratio")
  let count : Double = config |> @config.bind_with("count")
  let exact : Double = config |> @config.bind_with("exact")
  let decimal : @ion.Decimal = config |> @config.bind_with("count")
  @expect.expect((name, mode, on)).to_equal(("app", "fast", true))
  @expect.expect((ratio, count, exact)).to_equal((0.25, 3.0, 2.5))
  @expect.expect(decimal.exponent()).to_equal(0)
  let (_, text) = exact_failure(() => {
    let _ : UInt64 = config |> @config.bind_with("negative")
  })
  @expect.expect(text).to_equal(
    "negative: the integer is out of range for UInt64 (set in project /repo/morphir.ion)",
  )
  let (_, text) = exact_failure(() => {
    let _ : @ion.Decimal = config |> @config.bind_with("ratio")
  })
  @expect.expect(text).to_equal(
    "ratio: expected decimal, found float (set in project /repo/morphir.ion)",
  )
  let (_, text) = exact_failure(() => {
    let _ : Bool = config |> @config.bind_with("name")
  })
  @expect.expect(text).to_equal(
    "name: expected bool, found string (set in project /repo/morphir.ion)",
  )
}

///|
test "options, lists and maps decode their parts" {
  let config = load_files([
    (
      "/repo/app/morphir.toml",
      Member,
      (
        #|ports = [80, 443, "x"]
        #|labels.team = 1
        #|labels."eu.west" = 2
      ),
    ),
  ])
  let missing : Int? = config |> @config.bind_with("timeout")
  @expect.expect(missing).to_equal(None)
  let labels : Map[String, Int] = config |> @config.bind_with("labels")
  @expect.expect(labels).to_equal({ "team": 1, "eu.west": 2 })
  let (path, text) = exact_failure(() => {
    let _ : Array[Int] = config |> @config.bind_with("ports")
  })
  @expect.expect(path).to_equal("ports[2]")
  @expect.expect(text).to_equal(
    "ports[2]: expected int, found string (set in workspace-member /repo/app/morphir.toml)",
  )
  let (_, text) = exact_failure(() => {
    let _ : Array[Int] = config |> @config.bind_with("labels")
  })
  @expect.expect(text).to_equal(
    "labels: expected list, found struct (table set in workspace-member /repo/app/morphir.toml)",
  )
  let (_, text) = exact_failure(() => {
    let _ : Int = config |> @config.bind_with("server.port")
  })
  @expect.expect(text).to_equal("server.port: no value (not set by any source)")
}

///|
/// A record that lists what its node shows: item and child paths.
struct Probe {
  lines : Array[String]
}

///|
impl @config.FromConfig for Probe with from_config(node) {
  let lines = []
  for item in node.items() {
    let name : String = item.get("name")
    lines.push("\{item.path()} \{name} \{item.child("name").path()}")
  }
  for child in node.children() {
    let (name, child) = child
    lines.push("\{name} at \{child.path()}")
  }
  { lines, }
}

///|
test "nodes give paths, children and items" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      "targets = [{ name = \"a\" }, { name = \"b\" }]\nir.layout = \"x\"",
    ),
  ])
  let targets : Probe = config |> @config.bind_with("targets")
  @expect.expect(targets.lines).to_equal([
    "targets[0] a targets[0].name", "targets[1] b targets[1].name",
  ])
  let ir : Probe = config |> @config.bind_with("ir")
  @expect.expect(ir.lines).to_equal(["layout at ir.layout"])
  let none : Probe = config |> @config.bind_with("absent")
  @expect.expect(none.lines).to_equal([])
}

///|
struct Service {
  url : String
  token : @config.SecretRef
}

///|
impl @config.FromConfig for Service with from_config(node) {
  { url: node.get("url"), token: node.get("token") }
}

///|
test "a secret reference decodes only into SecretRef" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      "service.url = \"https://example.org\"\nservice.token = { env = \"SERVICE_TOKEN\" }",
    ),
  ])
  let service : Service = config |> @config.bind_with("service")
  @expect.expect(service.url).to_equal("https://example.org")
  @expect.expect(service.token).to_equal(Env("SERVICE_TOKEN"))
  let expected = "service.token: is a secret reference; bind it as SecretRef with bind_with (set in project /repo/morphir.toml)"
  let (_, text) = exact_failure(() => {
    let _ : String = config |> @config.bind_with("service.token")
  })
  @expect.expect(text).to_equal(expected)
  let (_, text) = exact_failure(() => {
    let _ : Map[String, String] = config |> @config.bind_with("service.token")
  })
  @expect.expect(text).to_equal(expected)
  let (_, text) = exact_failure(() => {
    let _ : @config.SecretRef = config |> @config.bind_with("service.url")
  })
  @expect.expect(text).to_equal(
    "service.url: expected a secret reference, found string (set in project /repo/morphir.toml)",
  )
}

///|
/// A record that decodes its whole node with `FromJson`.
struct JsonPart {
  part : Json
}

///|
impl @config.FromConfig for JsonPart with from_config(node) {
  { part: node.json() }
}

///|
test "a FromJson part stops at a secret reference" {
  let config = load_files([
    (
      "/repo/morphir.toml",
      Workspace,
      "service.url = \"https://example.org\"\nservice.token = { env = \"SERVICE_TOKEN\" }",
    ),
  ])
  let (path, text) = exact_failure(() => {
    let _ : JsonPart = config |> @config.bind_with("service")
  })
  @expect.expect(path).to_equal("service.token")
  @expect.expect(text).to_equal(
    "service.token: is a secret reference; bind it as SecretRef with bind_with (set in project /repo/morphir.toml)",
  )
  let url : JsonPart = config |> @config.bind_with("service.url")
  @expect.expect(url.part).to_equal("https://example.org")
}

///|
#external
priv type Adapter

///|
let fixture : Adapter = browser_adapter()

///|
extern "js" fn Adapter::register(self : Adapter, run : (String) -> @js_async.Promise[String], probe : (String) -> @js_async.Promise[String]) -> Unit =
  #|(fixture, run, probe) => fixture.register(run, probe)

///|
extern "js" fn Adapter::origin(self : Adapter) -> String =
  #|fixture => fixture.origin()

///|
extern "js" fn Adapter::signal(self : Adapter) -> @browser.AbortSignal =
  #|fixture => fixture.signal()

///|
struct Server { host : String; port : Int } derive(FromJson)

///|
fn field(value : Json, name : String, fallback : Json) -> Json {
  match value { Object(fields) => fields.get(name).unwrap_or(fallback); _ => fallback }
}

///|
fn text(value : Json) -> String {
  match value { String(text) => text; _ => abort("test input must be text") }
}

///|
fn items(value : Json) -> Array[Json] {
  match value { Array(items) => items; _ => abort("test input must be an array") }
}

///|
fn integer(value : Json) -> Int {
  match value { Number(value, ..) => value.to_int(); _ => abort("test input must be a number") }
}

///|
fn optional_position(value : Int?) -> Json {
  match value { Some(value) => Json(value); None => null }
}

///|
async fn execute(input : Json) -> Json {
  let mounts = items(field(input, "mounts", [])).map(mount =>
    @browser.from_urls(text(field(mount, "base", "")), field(mount, "manifest", null), root=text(field(mount, "root", "/workspace"))),
  )
  let mode = text(field(input, "mode", "load"))
  if mode == "construct" { return { "root": Json(mounts[0].root()) } }
  if mode == "parse-reference" {
    ignore(@toml.parse("[broken\n", origin="/workspace/bad.toml"))
    return { "error": "UnexpectedParseSuccess" }
  }
  let format : @config.Format = if mode == "positioned-parse" {
    { name: "positioned", extensions: ["toml"], parse: (_, origin) => raise @config.Parse(format="positioned", origin~, message="position fixture", line=Some(7), column=Some(3)) }
  } else { @toml.format() }
  let mut builder = @config.builder() |> @config.format(format)
  if field(input, "cwd", null) is String(cwd) { builder = builder |> @config.working_dir(cwd) }
  if field(input, "vars", null) is Object(vars) {
    builder = builder |> @config.env_vars(vars.map((_, value) => text(value)))
  }
  if field(input, "platform", null) is String(platform) {
    builder = builder |> @config.platform(match platform { "Windows" => Windows; "MacOs" => MacOs; _ => Linux })
  }
  if mode == "context" {
    builder = builder |> @config.provider({ name: "context", expand: context => Done({ sources: [@config.in_memory_pairs([
      ("cwd", @config.string(context.working_dir.unwrap_or("none"))),
      ("platform", @config.string(match context.platform { Some(Windows) => "Windows"; Some(MacOs) => "MacOs"; Some(Linux) => "Linux"; None => "none" })),
    ])], warnings: [] }) })
    builder = builder |> @config.env(prefix="APP")
  }
  let path = text(field(input, "path", "/workspace/acme.toml"))
  if mode == "repeat" || mode == "empty-need" {
    builder = builder |> @config.provider({ name: "faulty", expand: _ => Need(if mode == "empty-need" { [] } else { [ReadFile(path)] }) })
  }
  if mode == "listing" || mode == "missing-descendant" {
    builder = builder |> @config.provider({ name: "listing", expand: context => {
      match context.tree.listing(path) {
        Unknown => Need([ListDir(path)])
        Found(entries) => Done({ sources: [@config.in_memory_pairs([("listing", @config.string(entries.map(entry => entry.name).join(",")))])], warnings: [] })
        Missing => Done({ sources: [@config.in_memory_pairs([("listing", @config.string(if context.tree.file(path + "/child.toml") is Missing { "missing-descendant" } else { "unknown" }))])], warnings: [] })
      }
    } })
  }
  for source in items(field(input, "sources", [])) { builder = builder |> @config.file(text(source)) }
  if field(input, "overrides", null) is Object(_) {
    builder = builder |> @config.add(@config.ConfigSource::overrides_value(@config.ConfigValue::from_json(field(input, "overrides", {}))))
  }
  let bounds = field(input, "limits", {})
  let limits = @browser.limits(
    entries=integer(field(bounds, "entries", 4096)), bytes=integer(field(bounds, "bytes", 8388608)), requests=integer(field(bounds, "requests", 8192)),
  )
  let config = @browser.load(builder, mounts, limits~, signal=fixture.signal())
  let values : Map[String, Json] = Map([])
  for key in items(field(input, "keys", [])) {
    let key = text(key)
    values[key] = Json(@config.get_text(config, key))
  }
  let origins : Map[String, Json] = Map([])
  for key in items(field(input, "keys", [])) {
    let key = text(key)
    origins[key] = Json(config.origins(@config.KeyPath::parse(key)).map(origin => origin.location.unwrap_or("none")))
  }
  let reports = config.reports().map(report => report.path.unwrap_or("none"))
  let result : Map[String, Json] = { "values": Json(values), "origins": Json(origins), "reports": Json(reports) }
  if field(input, "bind", false) == true {
    let server : Server = @config.bind(config, "server")
    result["bound"] = { "host": Json(server.host), "port": Json(server.port) }
  }
  if mode == "fresh" {
    let second = @browser.load(builder, mounts)
    result["first_after"] = Json(@config.get_text(config, "server.host"))
    result["second"] = Json(@config.get_text(second, "server.host"))
  }
  Json(result)
}

///|
async fn run(request : String) -> String {
  let result = try execute(@json.parse(request)) catch {
    @browser.InvalidMount(operation~, path~, reason~) => { "error": "InvalidMount", "operation": Json(operation), "path": Json(path), "reason": Json(reason) }
    @browser.InvalidPath(operation~, reason~) => { "error": "InvalidPath", "operation": Json(operation), "reason": Json(reason) }
    @browser.OutsideMount(operation~, path~) => { "error": "OutsideMount", "operation": Json(operation), "path": Json(path) }
    @browser.LimitExceeded(operation~, path~, limit~) => { "error": "LimitExceeded", "operation": Json(operation), "path": Json(path), "limit": Json(limit) }
    @browser.Protocol(operation~, path~) => { "error": "Protocol", "operation": Json(operation), "path": Json(path) }
    @browser.Aborted(operation~, path~) => { "error": "Aborted", "operation": Json(operation), "path": Json(path) }
    @browser.Http(operation~, path~, status~) => { "error": "Http", "operation": Json(operation), "path": Json(path), "status": Json(status) }
    @browser.Io(operation~, path~) => { "error": "Io", "operation": Json(operation), "path": Json(path) }
    @browser.Unsupported(operation~, path~) => { "error": "Unsupported", "operation": Json(operation), "path": Json(path) }
    @config.Parse(origin~, line~, column~, ..) => { "error": "Parse", "path": Json(origin), "line": optional_position(line), "column": optional_position(column) }
    @config.KeyNotFound(key~) => { "error": "KeyNotFound", "path": Json(key.to_string()) }
    @config.FileNotFound(path~) => { "error": "FileNotFound", "path": Json(path) }
    @config.Decode(failure~) => { "error": "Decode", "path": Json(failure.at[0].path.to_string()), "message": Json(@config.ConfigError::Decode(failure~).message()) }
    error => { "error": "Unexpected", "message": Json(error.to_string()) }
  }
  result.stringify()
}

///|
async fn probe(url : String) -> String {
  let base = fixture.origin()
  let mount = @browser.from_urls(base + "/", { "version": 1, "files": [Json(url[1:].to_owned())] }, root="/workspace")
  let builder = @config.builder() |> @config.format(@toml.format()) |> @config.file("/workspace" + url) |> @config.overrides([("server.port", @config.int(9000))])
  let config = @browser.load(builder, [mount]) catch {
    @config.Parse(origin~, ..) => fail("Parse at \{origin}")
    @browser.Http(status~, ..) => fail("HTTP \{status}")
    @config.FileNotFound(path~) => fail("HTTP 404 at \{path}")
    error => raise error
  }
  let server : Server = @config.bind(config, "server") catch { error => fail(error.message()) }
  let origin = config.origins(@config.KeyPath::parse("server.host"))[0].location.unwrap()
  "\{server.host}:\{server.port} from \{origin}"
}

///|
fn main {
  fixture.register(request => @js_async.Promise::from_async(() => run(request)), url => @js_async.Promise::from_async(() => probe(url)))
}

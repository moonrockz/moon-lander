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
extern "js" fn Adapter::file_count(self : Adapter, selector : String) -> Int =
  #|(fixture, selector) => fixture.fileCount(selector)

///|
extern "js" fn Adapter::file_at(self : Adapter, selector : String, index : Int) -> @browser.File =
  #|(fixture, selector, index) => fixture.fileAt(selector, index)

///|
extern "js" fn Adapter::handle(self : Adapter, name : String) -> @browser.DirectoryHandle =
  #|(fixture, name) => fixture.handle(name)

///|
extern "js" fn Adapter::between(self : Adapter) -> @js_async.Promise[Bool] =
  #|fixture => fixture.between()

///|
struct Server { host : String; port : Int } derive(FromJson)

///|
/// Map the files of a test page input to explicit relative paths. Each pair is
/// [webkitRelativePath or name, mounted path]; a file without a pair is skipped.
fn selected_files(mount : Json) -> Array[(String, @browser.File)] {
  let selector = text(field(mount, "selector", "#files"))
  let files = []
  for pair in items(field(mount, "paths", [])) {
    let (key, path) = match pair { [String(key), String(path)] => (key, path); _ => abort("paths are pairs") }
    for i = 0; i < fixture.file_count(selector); i = i + 1 {
      let file = fixture.file_at(selector, i)
      let selected = if file.webkit_relative_path() != "" { file.webkit_relative_path() } else { file.name() }
      if selected == key { files.push((path, file)) }
    }
  }
  files
}

///|
fn mounted(mount : Json) -> @browser.Mount raise {
  let root = text(field(mount, "root", "/workspace"))
  if field(mount, "kind", "urls") == "directory" {
    return @browser.from_directory(fixture.handle(text(field(mount, "handle", "project"))), root~)
  }
  if field(mount, "kind", "urls") == "files" { return @browser.from_files(selected_files(mount), root~) }
  @browser.from_urls(text(field(mount, "base", "")), field(mount, "manifest", null), root~)
}

///|
fn status(report : @config.SourceReport) -> String {
  match report.status { Loaded => "Loaded"; NotFound => "NotFound"; Skipped => "Skipped" }
}

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
  let mounts = items(field(input, "mounts", [])).map(mounted)
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
  for source in items(field(input, "sources", [])) {
    match source {
      String(path) => builder = builder |> @config.file(path)
      // { conventions, workspace?: mount index, boundary?, isolated? }
      _ => {
        let mut conventions = @conventions.app_dirs(text(field(source, "conventions", "acme")))
        if field(source, "workspace", null) is Number(index, ..) { conventions = @browser.workspace(conventions, mounts[index.to_int()]) }
        if field(source, "boundary", null) is String(dir) { conventions = conventions |> @conventions.boundary(dir) }
        let options = @conventions.DiscoveryOptions::new(isolated=field(source, "isolated", false) == true)
        builder = builder |> @conventions.add(conventions, options~)
      }
    }
  }
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
  if field(input, "statuses", false) == true {
    result["statuses"] = Json(config.reports().map(report => "\{report.path.unwrap_or("none")} \{status(report)}"))
  }
  if field(input, "bind", false) == true {
    let server : Server = @config.bind(config, "server")
    result["bound"] = { "host": Json(server.host), "port": Json(server.port) }
  }
  if field(input, "between", false) == true {
    ignore(@js_async.run_promise(_ => fixture.between()))
    let second = @browser.load(builder, mounts, limits~, signal=fixture.signal())
    let first_after : Map[String, Json] = Map([])
    let second_values : Map[String, Json] = Map([])
    for key in items(field(input, "keys", [])) {
      let key = text(key)
      first_after[key] = Json(@config.get_text(config, key))
      second_values[key] = Json(@config.get_text(second, key))
    }
    result["first_after"] = Json(first_after)
    result["second"] = Json(second_values)
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
    @browser.PermissionDenied(operation~, path~) => { "error": "PermissionDenied", "operation": Json(operation), "path": Json(path) }
    @config.Ambiguous(location~, candidates~, ..) => { "error": "Ambiguous", "path": Json(location), "candidates": Json(candidates) }
    @config.OutsideBoundary(start~, boundary~) => { "error": "OutsideBoundary", "path": Json(start), "boundary": Json(boundary) }
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

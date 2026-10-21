///|
/// Headless hosted-configuration example. The caller supplies its authorized
/// directory base. No fetch, UI, or ambient configuration runs at module import.
struct Server { host : String; port : Int } derive(FromJson)

///|
async fn hosted(base : String) -> String {
  let mount = @browser.from_urls(base, { "version": 1, "files": ["acme.toml"] }, root="/workspace")
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.file("acme.toml")
    |> @config.overrides([("server.port", @config.int(9000))])
  let controller = @browser.AbortController::new()
  let config = @browser.load(builder, [mount], signal=controller.signal())
  let server : Server = @config.bind(config, "server")
  "\{server.host}:\{server.port}"
}

///|
extern "js" fn expose(load : (String) -> @js_async.Promise[String]) -> Unit =
  #|load => { globalThis.loadHostedServer = load; }

///|
fn main {
  expose(base => @js_async.Promise::from_async(() => hosted(base)))
}

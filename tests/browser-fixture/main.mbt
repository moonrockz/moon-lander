///|
#external
priv type Adapter

///|
#external
priv type Reply

///|
extern "js" fn Adapter::fetch_text(
  self : Adapter,
  url : String,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[Reply] =
  #|(adapter, url, signal) => adapter.fetchText(url, signal)

///|
extern "js" fn Reply::kind(self : Reply) -> String =
  #|reply => reply.kind

///|
extern "js" fn Reply::text(self : Reply) -> String =
  #|reply => reply.text

///|
extern "js" fn Reply::status(self : Reply) -> Int =
  #|reply => reply.status

///|
extern "js" fn install(probe : (String) -> @js_async.Promise[String]) -> Unit =
  #|probe => { globalThis.landerProbe = probe; }

///|
struct Server {
  host : String
  port : Int
} derive(FromJson)

///|
let adapter : Adapter = browser_adapter()

///|
async fn probe(url : String) -> String {
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.file("/workspace/acme.toml")
    |> @config.overrides([("server.port", @config.int(9000))])
  let mut tree = @config.FileTree::new()
  for round = 0; round < 4; round = round + 1 {
    // This fixture exports text to JavaScript. Render core errors explicitly at
    // that presentation boundary; Promise::from_async otherwise uses Error text.
    let step = @config.load(builder, tree) catch { error => fail(error.message()) }
    match step {
      Need(requests) =>
        for request in requests {
          guard request is ReadFile("/workspace/acme.toml") else {
            fail("Unexpected spike request")
          }
          let reply = @js_async.run_promise(signal =>
            adapter.fetch_text(url, signal),
          )
          match reply.kind() {
            "file" => tree = tree.with_file("/workspace/acme.toml", reply.text())
            "http" => fail("HTTP \{reply.status()} at /workspace/acme.toml")
            _ => fail("I/O failure at /workspace/acme.toml")
          }
        }
      Done(config) => {
        let server : Server = @config.bind(config, "server") catch {
          error => fail(error.message())
        }
        let origins = config.origins(@config.KeyPath::parse("server.host"))
        let port_origins = config.origins(@config.KeyPath::parse("server.port"))
        assert_eq(origins.length(), 1)
        assert_eq(port_origins.length(), 1)
        assert_eq(origins[0].location, Some("/workspace/acme.toml"))
        assert_true(port_origins[0].kind is Overrides)
        return "\{server.host}:\{server.port} from \{origins[0].location.unwrap()}"
      }
    }
  }
  fail("Spike request loop did not converge")
}

///|
fn main {
  install(url => @js_async.Promise::from_async(() => probe(url)))
}

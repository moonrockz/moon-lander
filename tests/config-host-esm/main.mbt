///|
/// Exercise the linked bundle in an ESM application, in addition to Moon's
/// CommonJS test harness. The task runs this from the workspace root.
async fn main {
  let format : @config.Format = {
    name: "module",
    extensions: ["mod"],
    parse: (text, _) => @config.fields([("text", @config.string(text))]),
  }
  let config = @config.builder()
    |> @config.working_dir("pkgs/lander")
    |> @config.format(format)
    |> @config.file("moon.mod")
    |> @host.load
  assert_true(
    @config.get_text(config, "text").contains("moonrockz/moon-lander"),
  )
  println("ESM host adapter read the module manifest")
}

///|
/// The test program of the console acceptance tests. The native tests in
/// `tests/console-signal-acceptance` start its js build under Node.js and Bun.
/// Its native build is the hosting consumer that `mise run build:cross` links
/// for Linux with the console signal stub.
async fn main {
  let text = @env.get_env_var("LANDER_CONSOLE_SCENARIO").unwrap_or("")
  guard @scenarios.Scenario::parse(text) is Some(scenario) else {
    fail("Unknown LANDER_CONSOLE_SCENARIO: \{text}")
  }
  @scenarios.run(scenario)
}

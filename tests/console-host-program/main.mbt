///|
/// The js test program of the console acceptance tests. The native tests in
/// `tests/console-signal-acceptance` start it under Node.js and Bun.
async fn main {
  let text = @env.get_env_var("LANDER_CONSOLE_SCENARIO").unwrap_or("")
  guard @scenarios.Scenario::parse(text) is Some(scenario) else {
    fail("Unknown LANDER_CONSOLE_SCENARIO: \{text}")
  }
  @scenarios.run(scenario)
}

///|
/// The test program of the logging sink acceptance tests. The native tests in
/// `tests/logging-sinks-acceptance` start its js build under Node.js and Bun.
async fn main {
  let text = @env.get_env_var("LANDER_LOGGING_SCENARIO").unwrap_or("")
  guard @scenarios.Scenario::parse(text) is Some(scenario) else {
    fail("Unknown LANDER_LOGGING_SCENARIO: \{text}")
  }
  let dir = @env.get_env_var("LANDER_LOGGING_DIR").unwrap_or("")
  @scenarios.run(scenario, dir)
}

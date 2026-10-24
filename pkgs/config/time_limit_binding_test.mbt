///|
/// Load one TOML file `/w/app.toml` with the text `toml`.
fn load_app_toml(toml : String) -> @config.Config raise @config.ConfigError {
  load_ion([("/w/app.toml", Workspace, toml)])
}

///|
test "bind a time limit from text" {
  let config = load_app_toml("[http]\ntimeout = \"1m 30s\"")
  let limit : @lander_core.TimeLimit = config |> @config.bind_with("http.timeout")
  assert_eq(limit.to_millis(), 90000)
}

///|
test "an integer is not a time limit" {
  let config = load_app_toml("[http]\ntimeout = 5000")
  let (failure, text) = decode_failure(() => {
    let _ : @lander_core.TimeLimit = config |> @config.bind_with("http.timeout")
  })
  assert_eq(failure.at.map(at => at.path.to_string()), ["http.timeout"])
  assert_true(
    text.contains("expected time limit text with a unit, such as \"30s\", found int"),
    msg=text,
  )
}

///|
test "bad text names the rule and blames the source" {
  let config = load_app_toml("[http]\ntimeout = \"30d\"")
  let (failure, text) = decode_failure(() => {
    let _ : @lander_core.TimeLimit = config |> @config.bind_with("http.timeout")
  })
  assert_eq(failure.at.map(at => at.path.to_string()), ["http.timeout"])
  assert_true(text.contains("the unit \"d\" is not known"), msg=text)
  guard failure.at[0].blame is Set([origin]) else { fail("one origin") }
  assert_eq(origin.location, Some("/w/app.toml"))
}

///|
test "bind a time limit from an Ion symbol" {
  let config = load_ion([
    ("/w/app.ion", Workspace, "{ http: { timeout: '30s' } }"),
  ])
  let limit : @lander_core.TimeLimit = config |> @config.bind_with("http.timeout")
  assert_eq(limit.to_millis(), 30000)
}

///|
test "an unset optional time limit is None" {
  let config = load_app_toml("[http]\nretries = 3")
  let limit : @lander_core.TimeLimit? = config
    |> @config.bind_with("http.timeout")
  assert_true(limit is None)
}

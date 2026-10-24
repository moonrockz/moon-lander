///|
test "@lander.AppName is the core application name" {
  let name : @lander_core.AppName = @lander.AppName::parse("acme")
  assert_eq(name, @lander_core.AppName::parse("acme"))
}

///|
test "@lander re-exports the application name error and its rule" {
  let rule = try {
    ignore(@lander.AppName::parse(""))
    None
  } catch {
    @lander.AppNameError::InvalidAppName(rule~, ..) => Some(rule)
  }
  assert_true(rule is Some(@lander.AppNameRule::Empty))
}

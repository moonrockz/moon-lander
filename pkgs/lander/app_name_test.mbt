///|
test "@lander.AppName is the core application name" {
  let name : @lander_core.AppName = @lander.AppName::parse("acme")
  assert_eq(name, @lander_core.AppName::parse("acme"))
}

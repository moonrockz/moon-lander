///|
test "minimal selection returns immutable roots and membership" {
  let metrics = @config.ProfileName::parse("metrics")
  let names = @config.ProfileNames::new([metrics])
  let result = @profiles.resolve(@profiles.Policy::new(), Selected(names))
  assert_true(result.contains(metrics))
  assert_eq(result.active(), names)
  assert_eq(result.roots(), names)
  assert_eq(result.selector(), Discovery)
  let off = @profiles.resolve(@profiles.Policy::new(), Disabled)
  assert_true(off.disabled())
  assert_false(off.contains(metrics))
  assert_eq(@profiles.resolve(@profiles.Policy::new(), Unspecified).active().names(), [])
}

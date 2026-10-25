///|
test "levels compare from Trace to Critical" {
  assert_true(@logging.Level::Debug < Warning)
  assert_true(@logging.Level::Critical > Error)
  let levels : Array[@logging.Level] = [
    Trace, Debug, Information, Warning, Error, Critical,
  ]
  for i in 1..<levels.length() {
    assert_true(levels[i - 1] < levels[i])
  }
  inspect(@logging.Level::Information, content="Information")
}

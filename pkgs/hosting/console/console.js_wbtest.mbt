///|
test "the listeners record no signal before a signal and can be removed" {
  assert_true(has_node_process())
  let listeners = node_adapter().install_signals()
  assert_true(kind_of_code(listeners.kind()) is None)
  listeners.remove()
}

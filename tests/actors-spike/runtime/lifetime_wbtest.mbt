///|
/// Saved handles of a scope that has returned.
priv struct Leftovers {
  scope : Scope
  waiting : Actor[Int, Unit]
  scanning : Actor[Int, Unit]
}

///|
async test "LIFE-1: no actor, name or waiter remains after the scope returns" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let leftovers = scope(scope => {
    let waiting = scope.start(
      0,
      (state, _ : Int) => {
        gate.get()
        Continue(state)
      },
      name=@policy.ActorName::parse("waiting"),
    )
    let scanning = scope.spawn((inbox : Inbox[Int]) => {
      ignore(inbox.scan(message => if message > 100 { Some(message) } else { None }))
    })
    waiting.send(1)
    scanning.send(1)
    // Two asks wait: one behind the blocked handler, one on a queued message.
    (scope.spawn_task)(() => ignore(waiting.ask((_ : Reply[Int]) => 2)))
    (scope.spawn_task)(() => ignore(waiting.ask((_ : Reply[Int]) => 3)))
    @aio.pause()
    @aio.pause()
    assert_eq(waiting.target.life.watchers.length(), 2)
    assert_true(scanning.target.mailbox.receiving)
    { scope, waiting, scanning }
  })
  for life in [leftovers.waiting.target.life, leftovers.scanning.target.life] {
    assert_true(life.outcome is Some(Cancelled))
    assert_eq(life.watchers.length(), 0)
  }
  assert_false(leftovers.scanning.target.mailbox.receiving)
  assert_false(leftovers.scanning.target.mailbox.open)
  assert_eq(leftovers.waiting.target.mailbox.queue.length(), 0)
  assert_eq(leftovers.scope.names.length(), 0)
  assert_false(leftovers.scope.open)
  let restart = try {
    ignore(leftovers.scope.start(0, (state, _ : Int) => Continue(state)))
    "started"
  } catch {
    ScopeClosed => "scope closed"
    _ => "other"
  }
  assert_eq(restart, "scope closed")
}

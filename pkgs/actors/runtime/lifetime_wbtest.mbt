///|
/// Saved handles of a scope that has returned.
priv struct Leftovers {
  scope : Scope
  waiting : Actor[Int, Unit]
  selecting : Actor[Int, Int]
  children : Scope
}

///|
async test "LIFE-1: no actor, child, watcher or waiter remains after the scope returns" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let children : Ref[Scope?] = Ref(None)
  let leftovers = scope(scope => {
    let waiting = scope.start(0, (state, _ : Int) => {
      gate.get()
      Continue(state)
    })
    let selecting = scope.spawn(context => {
      children.val = Some(context.scope())
      ignore(context.scope().start((), (_, _ : String) => Continue(())))
      select(message => if message > 100 { Some(message) } else { None })
    })
    waiting.send(1)
    selecting.send(1)
    // Two asks wait: one behind the blocked handler, one queued.
    (scope.spawn_task)(() => ignore(waiting.ask((_ : Reply[Int]) => 2))) |> ignore
    (scope.spawn_task)(() => ignore(waiting.ask((_ : Reply[Int]) => 3))) |> ignore
    while waiting.target.life.watchers.length() < 2 || children.val is None {
      @aio.pause()
    }
    { scope, waiting, selecting, children: children.val.unwrap() }
  })
  for life in [leftovers.waiting.target.life, leftovers.selecting.target.life] {
    assert_true(life.outcome is Some(Cancelled))
    assert_eq(life.watchers.length(), 0)
  }
  assert_false(leftovers.selecting.target.mailbox.admitting)
  assert_eq(leftovers.selecting.target.mailbox.queue.length(), 0)
  assert_eq(leftovers.waiting.target.mailbox.queue.length(), 0)
  assert_eq(leftovers.waiting.target.mailbox.waiting_producers, 0)
  assert_false(leftovers.scope.open)
  assert_false(leftovers.children.open)
  let restart = try {
    ignore(leftovers.scope.start(0, (state, _ : Int) => Continue(state)))
    "started"
  } catch {
    ScopeClosed => "scope closed"
    _ => "other"
  }
  assert_eq(restart, "scope closed")
}

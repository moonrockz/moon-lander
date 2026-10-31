///|
async test "Wait for Ended: a test observes the end event instead of polling status" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let worker = scope.start((), (_, message : Int) => {
      if message == 0 {
        Stop
      } else {
        Continue(())
      }
    })
    ignore(probe.get())
    worker.send(1)
    worker.send(0)
    match probe.get() {
      Ended(address, Completed) => {
        assert_eq(address, worker.address())
        assert_true(worker.status() is Ended(Completed))
      }
      other => fail("expected Ended(Completed), got \{other.to_string()}")
    }
  })
}

///|
async test "Opt-in channel: two scopes share one RuntimeEvents value" {
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  let events = @actors.RuntimeEvents::new()
  @actors.scope(events~, first => {
    ignore(events.subscribe(first, @actors.Subject::from_queue(probe)))
    let a = first.start((), (_, _ : Int) => Stop)
    @actors.scope(events~, second => {
      let b = second.start((), (_, _ : Int) => Stop)
      match probe.get() {
        Started(address) => assert_eq(address, a.address())
        other => fail("expected first Started, got \{other.to_string()}")
      }
      match probe.get() {
        Started(address) => {
          assert_eq(address, b.address())
          assert_true(a.address() != b.address())
        }
        other => fail("expected second Started, got \{other.to_string()}")
      }
      assert_eq(a.try_send(0), Accepted)
      assert_eq(b.try_send(0), Accepted)
      a.join()
      b.join()
    })
  })
}

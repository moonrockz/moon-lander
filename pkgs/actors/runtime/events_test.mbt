///|
/// Record each runtime event as a short label for acknowledgement-based tests.
fn event_log(log : Array[String]) -> @actors.Subject[@actors.ActorEvent] {
  @actors.Subject::new(
    send=event => {
      log.push(label_event(event))
      Admitted
    },
    try_send=event => {
      log.push(label_event(event))
      Accepted
    },
  )
}

///|
fn label_event(event : @actors.ActorEvent) -> String {
  match event {
    Started(address) => "started \{address.to_string()}"
    Ended(address, end) =>
      match end {
        Completed => "ended \{address.to_string()} completed"
        MailboxClosed => "ended \{address.to_string()} mailbox-closed"
        Failed(_) => "ended \{address.to_string()} failed"
        Cancelled => "ended \{address.to_string()} cancelled"
      }
    Undelivered(address, reason, ..) => {
      let why = match reason {
        Full => "full"
        Closed => "closed"
        Discarded => "discarded"
      }
      "undelivered \{address.to_string()} \{why}"
    }
  }
}

///|
async test "EVT: subscribe ends at unsubscribe and scope exit" {
  let log : Array[String] = []
  let events = @actors.RuntimeEvents::new()
  @actors.scope(events~, scope => {
    let sub = events.subscribe(scope, event_log(log))
    assert_eq(events.subscriber_count(), 1)
    let actor = scope.start((), (_, _ : Int) => Stop)
    actor.send(0)
    actor.join()
    sub.unsubscribe()
    assert_eq(events.subscriber_count(), 0)
    let other = scope.start((), (_, _ : Int) => Stop)
    other.send(0)
    other.join()
  })
  assert_eq(log.length(), 2)
  assert_true(log[0].has_prefix("started "))
  assert_true(log[1].has_prefix("ended "))
  assert_true(log[1].has_suffix(" completed"))
  let late : Array[String] = []
  let channel = @actors.RuntimeEvents::new()
  @actors.scope(events=channel, outer => {
    ignore(channel.subscribe(outer, event_log(late)))
    @actors.scope(events=channel, inner => {
      ignore(channel.subscribe(inner, event_log(late)))
    })
    assert_eq(channel.subscriber_count(), 1)
    let actor = outer.start((), (_, _ : Int) => Stop)
    actor.send(0)
    actor.join()
  })
  // Outer subscription still gets start+end; the inner one ended with its scope.
  assert_eq(late.length(), 2)
}

///|
async test "EVT: subscribe after close raises TopicClosed" {
  let events = @actors.RuntimeEvents::new()
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, event_log([])))
    events.close()
    assert_eq(events.subscriber_count(), 0)
    let outcome = try {
      ignore(events.subscribe(scope, event_log([])))
      "subscribed"
    } catch {
      @actors.TopicClosed => "closed"
      _ => "other"
    }
    assert_eq(outcome, "closed")
  })
}

///|
// Application code cannot publish a runtime event: `RuntimeEvents` has no
// public publish operation. `events.publish(...)` does not compile.
async test "EVT: no public application publish" {
  let events = @actors.RuntimeEvents::new()
  assert_eq(events.subscriber_count(), 0)
  events.close()
  assert_eq(events.subscriber_count(), 0)
}

///|
async test "EVT: lifecycle order for a normal actor" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let actor = scope.start(0, (state, message : Int) => {
      if message == 0 {
        Stop
      } else {
        Continue(state + message)
      }
    })
    match probe.get() {
      Started(address) => assert_eq(address, actor.address())
      other => fail("expected Started, got \{label_event(other)}")
    }
    actor.send(1)
    actor.send(0)
    actor.join()
    match probe.get() {
      Ended(address, Completed) => assert_eq(address, actor.address())
      other => fail("expected Ended(Completed), got \{label_event(other)}")
    }
  })
}

///|
async test "EVT: failed actor end value matches status" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  let outcome = try {
    @actors.scope(events~, scope => {
      ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
      let actor = scope.start((), (_, _ : Int) => raise Broken("boom"))
      match probe.get() {
        Started(_) => ()
        other => fail("expected Started, got \{label_event(other)}")
      }
      actor.send(0)
      actor.join()
    })
    "joined"
  } catch {
    Broken(text) => "failed: \{text}"
    _ => "other"
  }
  assert_eq(outcome, "failed: boom")
  match probe.get() {
    Ended(_, Failed(error)) =>
      match error {
        Broken(text) => assert_eq(text, "boom")
        _ => fail("expected Broken cause, got \{error}")
      }
    other => fail("expected Ended(Failed), got \{label_event(other)}")
  }
}

///|
async test "EVT: failed initializer publishes neither event" {
  let log : Array[String] = []
  let events = @actors.RuntimeEvents::new()
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, event_log(log)))
    let outcome = try {
      ignore(
        scope.start_with(
          _ => raise Broken("init"),
          (state : Int, _ : Int) => Continue(state),
        ),
      )
      "started"
    } catch {
      Broken(text) => "failed: \{text}"
      _ => "other"
    }
    assert_eq(outcome, "failed: init")
  })
  assert_eq(log, [])
}

///|
async test "EVT: child actor events use the parent channel" {
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  let events = @actors.RuntimeEvents::new()
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let parent = scope.spawn((context : @actors.ActorContext[Int]) => {
      let child = context.scope().start((), (_, _ : Int) => Stop)
      // End the child while the parent is still live so its events are not
      // cancelled by parent teardown. `make` is sync, so use try_send.
      assert_eq(child.try_send(0), Accepted)
      @actors.receive().map(_ => ())
    })
    match probe.get() {
      Started(parent_address) => assert_eq(parent_address, parent.address())
      other => fail("expected parent Started, got \{label_event(other)}")
    }
    match probe.get() {
      Started(_) => ()
      other => fail("expected child Started, got \{label_event(other)}")
    }
    match probe.get() {
      Ended(_, Completed) => ()
      other => fail("expected child Ended, got \{label_event(other)}")
    }
    parent.send(0)
    parent.join()
    match probe.get() {
      Ended(parent_address, Completed) =>
        assert_eq(parent_address, parent.address())
      other => fail("expected parent Ended, got \{label_event(other)}")
    }
  })
}

///|
async test "EVT: a separate top-level scope without a channel publishes nothing there" {
  let outer_log : Array[String] = []
  let events = @actors.RuntimeEvents::new()
  @actors.scope(events~, outer => {
    ignore(events.subscribe(outer, event_log(outer_log)))
    let parent = outer.start((), (_, _ : Int) => {
      // A new top-level scope call with no channel: its actor is invisible
      // to the outer channel.
      @actors.scope(inner => {
        let nested = inner.start((), (_, _ : Int) => Stop)
        nested.send(0)
        nested.join()
      })
      Stop
    })
    parent.send(0)
    parent.join()
  })
  // Only the parent actor: start + end. The nested top-level actor is absent.
  assert_eq(outer_log.length(), 2)
  assert_true(outer_log[0].has_prefix("started "))
  assert_true(outer_log[1].has_suffix(" completed"))
}

///|
async test "EVT: one channel for two scopes" {
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  let events = @actors.RuntimeEvents::new()
  @actors.scope(events~, first => {
    ignore(events.subscribe(first, @actors.Subject::from_queue(probe)))
    let a = first.start((), (_, _ : Int) => Stop)
    @actors.scope(events~, second => {
      let b = second.start((), (_, _ : Int) => Stop)
      match probe.get() {
        Started(address) => assert_eq(address, a.address())
        other => fail("expected first Started, got \{label_event(other)}")
      }
      match probe.get() {
        Started(address) => {
          assert_eq(address, b.address())
          assert_true(a.address() != b.address())
        }
        other => fail("expected second Started, got \{label_event(other)}")
      }
      a.send(0)
      b.send(0)
      a.join()
      b.join()
    })
  })
}

///|
async test "EVT: scope without a channel publishes nothing" {
  let log : Array[String] = []
  @actors.scope(scope => {
    let actor = scope.start((), (_, _ : Int) => Stop)
    actor.send(0)
    actor.join()
    assert_true(actor.status() is Ended(Completed))
    assert_eq(log.length(), 0)
  })
}

///|
async test "EVT: slow subscriber drops and counts; second subscriber gets both" {
  let events = @actors.RuntimeEvents::new()
  let one = @actors.MailboxCapacity::from_int(1)
  let second : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  let ready : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    // Observe Starts before the capacity-one actor subscribes, so it does not
    // receive its own Started into the mailbox under test.
    ignore(events.subscribe(scope, @actors.Subject::from_queue(second)))
    let slow = scope.start(
      (),
      mailbox=Bounded(one),
      (_, _ : @actors.ActorEvent) => {
        ready.put(())
        gate.get()
        Continue(())
      },
    )
    match second.get() {
      Started(address) => assert_eq(address, slow.address())
      other => fail("expected Started(slow), got \{label_event(other)}")
    }
    let sub_slow = events.subscribe(scope, slow.to_ref().to_subject())
    let a = scope.start((), (_, _ : Int) => Stop)
    match second.get() {
      Started(address) => assert_eq(address, a.address())
      other => fail("expected Started(A), got \{label_event(other)}")
    }
    ready.get()
    assert_eq(slow.queued_count(), 0)
    assert_eq(a.try_send(0), Accepted)
    match second.get() {
      Ended(address, Completed) => assert_eq(address, a.address())
      other => fail("expected Ended(A), got \{label_event(other)}")
    }
    assert_eq(slow.queued_count(), 1)
    assert_eq(sub_slow.dropped_count(), 0)
    let b = scope.start((), (_, _ : Int) => Stop)
    match second.get() {
      Started(address) => assert_eq(address, b.address())
      other => fail("expected Started(B), got \{label_event(other)}")
    }
    assert_eq(b.try_send(0), Accepted)
    match second.get() {
      Ended(address, Completed) => assert_eq(address, b.address())
      other => fail("expected Ended(B), got \{label_event(other)}")
    }
    assert_eq(sub_slow.dropped_count(), 2)
    a.join()
    b.join()
    gate.put(())
    gate.put(())
  })
}

///|
async test "EVT: ended subscriber is skipped without failing others" {
  let live_log : Array[String] = []
  let events = @actors.RuntimeEvents::new()
  @actors.scope(events~, scope => {
    let closed : @actors.Subject[@actors.ActorEvent] = @actors.Subject::new(
      send=_ => Rejected,
      try_send=_ => Closed,
    )
    ignore(events.subscribe(scope, closed))
    ignore(events.subscribe(scope, event_log(live_log)))
    assert_eq(events.subscriber_count(), 2)
    let actor = scope.start((), (_, _ : Int) => Stop)
    actor.send(0)
    actor.join()
    assert_eq(events.subscriber_count(), 1)
  })
  assert_true(live_log.length() >= 2)
}

///|
async test "EVT: an ended subscriber actor is skipped with no event and no failure" {
  let log : Array[String] = []
  let events = @actors.RuntimeEvents::new()
  @actors.scope(events~, scope => {
    // The watcher ends at its first event while its subscription is active.
    let watcher = scope.start((), (_, _ : @actors.ActorEvent) => Stop)
    ignore(events.subscribe(scope, watcher.to_ref().to_subject()))
    ignore(events.subscribe(scope, event_log(log)))
    let worker = scope.start((), (_, _ : Int) => Stop)
    watcher.join()
    // The watcher's own end found its mailbox closed and removed it.
    assert_eq(events.subscriber_count(), 1)
    worker.send(0)
    worker.join()
  })
  assert_eq(log.length(), 3)
  assert_true(log[0].has_prefix("started "))
  assert_true(log[1].has_suffix(" completed"))
  assert_true(log[2].has_suffix(" completed"))
}

///|
async test "EVT: dropping an event publishes no feedback event" {
  let log : Array[String] = []
  let events = @actors.RuntimeEvents::new()
  let one = @actors.MailboxCapacity::from_int(1)
  let hold : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let ready : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    let slow = scope.start(
      (),
      mailbox=Bounded(one),
      (_, _ : @actors.ActorEvent) => {
        ready.put(())
        hold.get()
        Continue(())
      },
    )
    let sub = events.subscribe(scope, slow.to_ref().to_subject())
    ignore(events.subscribe(scope, event_log(log)))
    let a = scope.start((), (_, _ : Int) => Stop)
    ready.get()
    a.send(0)
    a.join()
    let b = scope.start((), (_, _ : Int) => Stop)
    b.send(0)
    b.join()
    assert_true(sub.dropped_count() >= 1)
    hold.put(())
    hold.put(())
  })
  for entry in log {
    assert_true(entry.has_prefix("started ") || entry.has_suffix(" completed"))
  }
}

///|
async test "EVT: wait for Ended instead of polling status" {
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
      other => fail("expected Ended(Completed), got \{label_event(other)}")
    }
  })
}

///|
suberror Crash {
  Crash
} derive(Debug)

///|
async test "Close with work in flight: close gives B and C, A replies, join waits for cleanup" {
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  @actors.scope(scope => {
    let actor = scope.start(
      (),
      (_, message : (String, @actors.Reply[String]?)) => {
        let (name, reply) = message
        if name == "A" {
          started.put(())
          gate.get()
        }
        if reply is Some(reply) {
          ignore(reply.send(name))
        }
        Continue(())
      },
      on_stop=() => log.push("cleanup"),
    )
    @aio.with_task_group(group => {
      let a = group.spawn(() => actor.ask(reply => ("A", Some(reply))))
      started.get()
      actor.send(("B", None))
      actor.send(("C", None))
      guard actor.close() is Some(pending) else { fail("no snapshot") }
      assert_eq(pending.messages().map(message => message.0), ["B", "C"])
      assert_eq(actor.try_send(("D", None)), Closed)
      gate.put(())
      assert_eq(a.wait(), "A")
    })
    actor.join()
    log.push("joined")
  })
  assert_eq(log, ["cleanup", "joined"])
}

///|
async test "Repeated close: one snapshot and one cleanup" {
  let cleanups = Ref(0)
  @actors.scope(scope => {
    let actor = scope.start((), (_, _ : Int) => Continue(()), on_stop=() => {
      cleanups.val += 1
    })
    let first = actor.close()
    let second = actor.close()
    assert_true(first is Some(_))
    assert_true(second is None)
    actor.join()
  })
  assert_eq(cleanups.val, 1)
}

///|
async test "Drain processes admitted work, then later sends fail closed" {
  let log = []
  @actors.scope(scope => {
    let actor = scope.start((), (_, name : String) => {
      @aio.pause()
      log.push(name)
      Continue(())
    })
    actor.send("A")
    actor.send("B")
    actor.drain()
    assert_eq(actor.try_send("C"), Closed)
  })
  assert_eq(log, ["A", "B"])
}

///|
async test "Cancel during a wait: queued work does not run and pending asks wake" {
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let never : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  @actors.scope(scope => {
    let actor = scope.start((), (_, message : (String, @actors.Reply[Int]?)) => {
      log.push(message.0)
      started.put(())
      never.get()
      Continue(())
    })
    actor.send(("first", None))
    started.get()
    let outcome = @aio.with_task_group(group => {
      let waiting = group.spawn(() => {
        try {
          ignore(actor.ask(reply => ("queued", Some(reply))))
          "answered"
        } catch {
          @actors.Closed(_) => "closed"
          _ => "other"
        }
      })
      while actor.queued_count() == 0 {
        @aio.pause()
      }
      actor.cancel()
      waiting.wait()
    })
    assert_eq(outcome, "closed")
    assert_true(actor.status() is Ended(Cancelled))
  })
  assert_eq(log, ["first"])
}

///|
async test "Idle actor on normal scope exit: the scope returns after its cleanup" {
  let log = []
  @actors.scope(scope => {
    ignore(
      scope.start((), (_, _ : Int) => Continue(()), on_stop=() => {
        log.push("cleanup")
      }),
    )
  })
  log.push("returned")
  assert_eq(log, ["cleanup", "returned"])
}

///|
async test "Parent completes normally: its child ends before the parent join" {
  let log = []
  @actors.scope(scope => {
    let parent = scope.spawn((context : @actors.ActorContext[Int]) => {
      ignore(
        context
        .scope()
        .start((), (_, _ : Int) => Continue(()), on_stop=() => {
          log.push("child cleanup")
        }),
      )
      @actors.done(1)
    })
    assert_eq(parent.join(), 1)
    log.push("parent joined")
  })
  assert_eq(log, ["child cleanup", "parent joined"])
}

///|
async test "Failure cancels siblings: the scope reports the error after cleanup" {
  let log = []
  let outcome = try {
    @actors.scope(scope => {
      ignore(
        scope.start((), (_, _ : Int) => Continue(()), on_stop=() => {
          log.push("sibling cleanup")
        }),
      )
      let failing = scope.start((), (_, _ : Int) => raise Crash)
      failing.send(1)
      failing.join()
    })
    "returned"
  } catch {
    Crash => "crash"
    _ => "other"
  }
  assert_eq((outcome, log), ("crash", ["sibling cleanup"]))
}

///|
async test "Recovered receive: the scope stays live and another message is processed" {
  let result = @actors.scope(scope => {
    let actor = scope.spawn(_ => {
      let failing : @actors.Receive[Int, Int] = @actors.receive().bind(_ => {
        raise Crash
      })
      failing.recover(_ => @actors.receive())
    })
    actor.send(1)
    actor.send(2)
    actor.join()
  })
  assert_eq(result, 2)
}

///|
async test "Escaped scope handle: a later start gets a typed closed-scope error" {
  let saved = @actors.scope(scope => scope)
  let outcome = try {
    ignore(saved.start((), (_, _ : Int) => Continue(())))
    "started"
  } catch {
    @actors.ScopeClosed => "scope closed"
    _ => "other"
  }
  assert_eq(outcome, "scope closed")
}

///|
async test "Initialization failure: the cause is reported and the resource is released once" {
  let released = Ref(0)
  @actors.scope(scope => {
    let outcome = try {
      let _ : @actors.Actor[Int, Unit] = scope.start_with(
        setup => {
          setup.on_stop(() => released.val += 1)
          raise Crash
        },
        (state : Int, _) => Continue(state),
      )
      "started"
    } catch {
      Crash => "crash"
      _ => "other"
    }
    assert_eq(outcome, "crash")
  })
  assert_eq(released.val, 1)
}

///|
async test "Cleanup exceeds its budget: the scope reports a typed cleanup timeout" {
  let limit = @lander_core.TimeLimit::millis(10)
  let outcome = try {
    @actors.scope(scope => {
      ignore(
        scope.start(
          (),
          (_, _ : Int) => Continue(()),
          on_stop=() => @aio.sleep(10000),
          cleanup_limit=limit,
        ),
      )
    })
    "returned"
  } catch {
    @actors.CleanupTimedOut(primary=None, ..) => "cleanup timed out"
    _ => "other"
  }
  assert_eq(outcome, "cleanup timed out")
}

///|
async test "Independent joiners: a cancelled joiner does not stop the other" {
  let result = @actors.scope(scope => {
    let actor = scope.spawn(_ => @actors.receive())
    @aio.with_task_group(group => {
      let cancelled = group.spawn(() => actor.join())
      let kept = group.spawn(() => actor.join())
      @aio.pause()
      cancelled.cancel()
      actor.send("result")
      kept.wait()
    })
  })
  assert_eq(result, "result")
}

///|
/// A protocol for lifecycle tests.
enum Task {
  /// Wait at the gate, then log the name.
  Gated(String)
  /// Log the name.
  Quick(String)
}

///|
/// Start a worker that logs each task. `started` gets an acknowledgement when
/// a gated task starts. `cleanups` counts the runs of its cleanup.
fn start_logger(
  scope : @actors.Scope,
  log : Array[String],
  started : @aio.Queue[Unit],
  gate : @aio.Queue[Unit],
  cleanups : Ref[Int],
) -> @actors.Actor[Task, Unit] raise @actors.ActorError {
  scope.start(
    (),
    (_, task) => {
      match task {
        Gated(name) => {
          started.put(())
          gate.get()
          log.push(name)
        }
        Quick(name) => log.push(name)
      }
      Continue(())
    },
    on_stop=() => {
      @aio.pause()
      cleanups.val += 1
    },
  )
}

///|
fn task_name(task : Task) -> String {
  match task {
    Gated(name) | Quick(name) => name
  }
}

///|
async test "LIFE-1: close gives the queued messages once, lets the in-flight one finish, and cleanup runs once" {
  let log = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let cleanups = Ref(0)
  @actors.scope(scope => {
    let worker = start_logger(scope, log, started, gate, cleanups)
    worker.send(Gated("A"))
    started.get()
    worker.send(Quick("B"))
    worker.send(Quick("C"))
    guard worker.close() is Some(pending) else { fail("no snapshot") }
    assert_eq(pending.messages().map(task_name), ["B", "C"])
    assert_true(worker.close() is None)
    assert_true(worker.status() is Closing)
    assert_eq(worker.try_send(Quick("D")), Closed)
    gate.put(())
    worker.join()
    assert_true(worker.status() is Ended(Completed))
    assert_true(worker.close() is None)
  })
  assert_eq(log, ["A"])
  assert_eq(cleanups.val, 1)
}

///|
async test "LIFE-1: drain processes the admitted work, rejects new messages and returns after cleanup" {
  let log = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let cleanups = Ref(0)
  @actors.scope(scope => {
    let worker = start_logger(scope, log, started, gate, cleanups)
    worker.send(Gated("A"))
    started.get()
    worker.send(Quick("B"))
    @aio.with_task_group(group => {
      let draining = group.spawn(() => worker.drain())
      @aio.pause()
      assert_eq(worker.try_send(Quick("late")), Closed)
      gate.put(())
      draining.wait()
    })
    assert_eq(cleanups.val, 1)
    assert_true(worker.status() is Ended(Completed))
  })
  assert_eq(log, ["A", "B"])
}

///|
async test "LIFE-1: a cancelled drain waiter does not open the mailbox again" {
  let log = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let cleanups = Ref(0)
  @actors.scope(scope => {
    let worker = start_logger(scope, log, started, gate, cleanups)
    worker.send(Gated("A"))
    started.get()
    @aio.with_task_group(group => {
      let draining = group.spawn(() => worker.drain())
      @aio.pause()
      draining.cancel()
    })
    assert_eq(worker.try_send(Quick("late")), Closed)
    gate.put(())
    worker.join()
  })
  assert_eq(log, ["A"])
}

///|
async test "LIFE-1: cancel stops a waiting handler, drops queued work and wakes asks" {
  let log : Array[String] = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let cleanups = Ref(0)
  let outcomes = []
  @actors.scope(scope => {
    let desk = scope.start(
      (),
      (_, message : @actors.Reply[Int]) => {
        started.put(())
        gate.get()
        ignore(message.send(1))
        Continue(())
      },
      on_stop=() => cleanups.val += 1,
    )
    @aio.with_task_group(group => {
      for _ in 0..<2 {
        group.spawn_bg(() => {
          let outcome = try {
            ignore(desk.ask(reply => reply))
            "reply"
          } catch {
            @actors.Closed(_) => "closed"
            _ => "other"
          }
          outcomes.push(outcome)
        })
      }
      started.get()
      while desk.queued_count() == 0 {
        @aio.pause()
      }
      desk.cancel()
    })
    let joined = try {
      desk.join()
      "result"
    } catch {
      @actors.ActorCancelled(_) => "cancelled"
      _ => "other"
    }
    assert_eq(joined, "cancelled")
    assert_true(desk.status() is Ended(Cancelled))
  })
  assert_eq(outcomes, ["closed", "closed"])
  assert_eq(log, [])
  assert_eq(cleanups.val, 1)
}

///|
async test "RECV-1: a receive on a closed mailbox ends the actor as closed, or continues with on_closed" {
  @actors.scope(scope => {
    let bare : @actors.Actor[Int, Int] = scope.spawn(_ => @actors.receive())
    ignore(bare.close())
    let joined = try {
      ignore(bare.join())
      "result"
    } catch {
      @actors.Closed(address) if address == bare.address() => "closed"
      _ => "other"
    }
    assert_eq(joined, "closed")
    assert_true(bare.status() is Ended(MailboxClosed))
    let handled : @actors.Actor[Int, Int] = scope.spawn(_ => {
      @actors.receive().on_closed(() => @actors.done(-1))
    })
    ignore(handled.close())
    assert_eq(handled.join(), -1)
    // A state loop ends normally on close.
    let counter = scope.start(0, (count, _ : Int) => Continue(count + 1))
    ignore(counter.close())
    counter.join()
  })
}

///|
suberror Broken {
  Broken(String)
} derive(Debug)

///|
async test "LIFE-1: a failed initializer releases its resource once and start_with reports the cause" {
  let released = Ref(0)
  let log = []
  @actors.scope(scope => {
    let outcome = try {
      ignore(
        scope.start_with(
          setup => {
            log.push("acquire")
            setup.on_stop(() => released.val += 1)
            raise Broken("init")
          },
          (state : Int, _ : Int) => Continue(state),
        ),
      )
      "started"
    } catch {
      Broken(text) => "failed: \{text}"
      _ => "other"
    }
    assert_eq(outcome, "failed: init")
    assert_eq(released.val, 1)
    // The scope is still live: another start works.
    let counter = scope.start_with(
      setup => {
        setup.on_stop(() => released.val += 1)
        @aio.pause()
        40
      },
      (state, message : Int) => Continue(state + message),
    )
    counter.send(2)
    ignore(counter.close())
    counter.join()
  })
  assert_eq(log, ["acquire"])
  assert_eq(released.val, 2)
}

///|
async test "LIFE-1: start_with returns only after the initializer ends" {
  let log = []
  @actors.scope(scope => {
    let actor = scope.start_with(
      _ => {
        @aio.pause()
        log.push("initialized")
        1
      },
      (state, _ : Int) => Continue(state),
    )
    log.push("returned")
    assert_true(actor.status() is Running)
  })
  assert_eq(log, ["initialized", "returned"])
}

///|
async test "LIFE-1: a cleanup that passes its time limit fails the scope with a typed timeout" {
  let ten_ms = @lander_core.TimeLimit::millis(10)
  let outcome = try {
    @actors.scope(scope => {
      let actor = scope.start(
        (),
        (_, _ : Int) => Continue(()),
        on_stop=() => @aio.sleep(10000),
        cleanup_limit=ten_ms,
      )
      ignore(actor.close())
      actor.join()
    })
    "returned"
  } catch {
    @actors.CleanupTimedOut(primary=None, limit~) if limit == ten_ms =>
      "cleanup timed out"
    _ => "other"
  }
  assert_eq(outcome, "cleanup timed out")
}

///|
async test "LIFE-1: a cleanup error keeps the primary failure" {
  let never : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let outcome = try {
    @actors.scope(scope => {
      let actor = scope.start(
        (),
        (_, _ : Int) => raise Broken("handler"),
        on_stop=() => raise Broken("cleanup"),
      )
      actor.send(1)
      // The body waits; the actor's combined failure cancels it.
      never.get()
    })
    "returned"
  } catch {
    @actors.CleanupFailed(primary=Some(Broken(first)), cleanup=Broken(second)) =>
      "\{first} then \{second}"
    _ => "other"
  }
  assert_eq(outcome, "handler then cleanup")
}

///|
async test "LIFE-1: a cleanup error fails the scope also after cancellation" {
  let outcome = try {
    @actors.scope(scope => {
      ignore(
        scope.start(
          (),
          (_, _ : Int) => Continue(()),
          on_stop=() => raise Broken("cleanup"),
        ),
      )
    })
    "returned"
  } catch {
    @actors.CleanupFailed(primary=None, cleanup=Broken(text)) => text
    _ => "other"
  }
  assert_eq(outcome, "cleanup")
}

///|
async test "LIFE-1: scope exit runs the cleanup of an idle actor before it returns" {
  let log = []
  @actors.scope(scope => {
    ignore(
      scope.start((), (_, _ : Int) => Continue(()), on_stop=() => {
        @aio.pause()
        log.push("cleanup")
      }),
    )
    log.push("body returns")
  })
  log.push("scope returned")
  assert_eq(log, ["body returns", "cleanup", "scope returned"])
}

///|
async test "LIFE-1: an actor failure cancels a waiting sibling and the scope reports it after cleanup" {
  let log = []
  let outcome = try {
    @actors.scope(scope => {
      ignore(
        scope.start((), (_, _ : Int) => Continue(()), on_stop=() => {
          log.push("sibling cleanup")
        }),
      )
      let failing = scope.start((), (_, _ : Int) => raise Broken("boom"))
      failing.send(1)
      failing.join()
    })
    "returned"
  } catch {
    Broken(text) => "failed: \{text}"
    _ => "other"
  }
  assert_eq(outcome, "failed: boom")
  assert_eq(log, ["sibling cleanup"])
}

///|
async test "LIFE-1: a nested scope is a failure boundary for an actor" {
  let result = @actors.scope(scope => {
    let parent = scope.spawn(_ => {
      let first : @actors.Receive[Int, String] = @actors.done("")
      first.bind(_ => {
        let inner = try {
          @actors.scope(inner => {
            let child = inner.start((), (_, _ : Int) => raise Broken("child"))
            child.send(1)
            child.join()
          })
          "inner returned"
        } catch {
          Broken(text) => "contained \{text}"
          _ => "other"
        }
        @actors.receive().map(value => "\{inner}, then \{value}")
      })
    })
    parent.send(7)
    parent.join()
  })
  assert_eq(result, "contained child, then 7")
}

///|
async test "LIFE-1: a saved context scope rejects starts after its actor ends" {
  let saved : Ref[@actors.Scope?] = Ref(None)
  @actors.scope(scope => {
    let parent = scope.spawn((context : @actors.ActorContext[Int]) => {
      saved.val = Some(context.scope())
      @actors.done(1)
    })
    assert_eq(parent.join(), 1)
  })
  let outcome = try {
    ignore(saved.val.unwrap().start((), (_, _ : Int) => Continue(())))
    "started"
  } catch {
    @actors.ScopeClosed => "scope closed"
    _ => "other"
  }
  assert_eq(outcome, "scope closed")
}

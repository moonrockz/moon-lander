///|
/// A protocol whose request never gets a reply from the handler.
enum Job {
  Wait(@actors.Reply[Int])
  Fail(@actors.Reply[Int])
}

///|
/// How `join` of an ended actor ends.
async fn[M, R] joined(actor : @actors.Actor[M, R]) -> String {
  try {
    ignore(actor.join())
    "result"
  } catch {
    @actors.ActorCancelled(address) if address == actor.address() => "cancelled"
    @actors.Closed(_) => "closed"
    _ => "other"
  }
}

///|
async test "LIFE-1: scope exit cancels idle actors instead of waiting for a message" {
  let log = []
  let (idle, receiver) = @actors.scope(scope => {
    let idle = scope.start(0, (state, _ : Int) => Continue(state))
    let receiver : @actors.Actor[String, String] = scope.spawn(_ => {
      @actors.receive()
    })
    log.push("body returns")
    (idle, receiver)
  })
  log.push("scope returned")
  assert_eq(log, ["body returns", "scope returned"])
  assert_eq(joined(idle), "cancelled")
  assert_eq(joined(receiver), "cancelled")
  assert_eq(idle.try_send(1), Closed)
}

///|
async test "LIFE-1: a parent that completes cancels and joins its child first" {
  let child_cell : Ref[@actors.Actor[String, Unit]?] = Ref(None)
  let log = []
  let result = @actors.scope(scope => {
    let parent = scope.spawn(context => {
      let first : @actors.Receive[Int, Unit] = @actors.done(())
      first.bind(_ => {
        let child = context.scope().start((), (_, _ : String) => Continue(()))
        child_cell.val = Some(child)
        log.push("parent returns")
        @actors.done(42)
      })
    })
    let result = parent.join()
    // The child has ended before the parent's join returned.
    let child = child_cell.val.unwrap()
    log.push(if child.try_send("late") is Closed { "child closed" } else { "child open" })
    log.push(joined(child))
    result
  })
  assert_eq(result, 42)
  assert_eq(log, ["parent returns", "child closed", "cancelled"])
}

///|
async test "LIFE-1: a stop without a reply wakes the in-flight and queued asks" {
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let outcomes = []
  @actors.scope(scope => {
    let worker = scope.start((), (_, job : Job) => {
      match job {
        Wait(reply) => {
          ignore(reply)
          started.put(())
          gate.get()
          Stop
        }
        Fail(_) => Continue(())
      }
    })
    @aio.with_task_group(group => {
      for _ in 0..<2 {
        group.spawn_bg(() => {
          let outcome = try {
            ignore(worker.ask(reply => Wait(reply)))
            "reply"
          } catch {
            @actors.Closed(_) => "closed"
            _ => "other"
          }
          outcomes.push(outcome)
        })
      }
      started.get()
      while worker.to_ref().queued_count() < 1 {
        @aio.pause()
      }
      gate.put(())
    })
  })
  assert_eq(outcomes, ["closed", "closed"])
}

///|
async test "LIFE-1: an actor failure wakes an ask with the original cause" {
  let ready : @aio.Queue[@actors.ActorRef[Job]] = @aio.Queue(kind=Unbounded)
  let outcome = @aio.with_task_group(group => {
    group.spawn_bg(allow_failure=true, () => @actors.scope(scope => {
      let worker = scope.start((), (_, job : Job) => {
        match job {
          Fail(reply) => {
            ignore(reply)
            raise Boom
          }
          Wait(_) => Continue(())
        }
      })
      ready.put(worker.to_ref())
      worker.join()
    }))
    let worker = ready.get()
    try {
      ignore(worker.ask(reply => Fail(reply)))
      "reply"
    } catch {
      @actors.ActorFailed(address, Boom) if address == worker.address() => "failed: Boom"
      _ => "other"
    }
  })
  assert_eq(outcome, "failed: Boom")
}

///|
async test "LIFE-1: scope exit with an actor that asks a blocked sibling returns normally" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  for _ in 0..<4 {
    @actors.scope(scope => {
      let blocked = scope.start((), (_, job : Job) => {
        match job {
          Wait(reply) | Fail(reply) => ignore(reply)
        }
        started.put(())
        gate.get()
        Continue(())
      })
      let asker = scope.start((), (_, _ : Int) => {
        ignore(blocked.ask(reply => Wait(reply)))
        Continue(())
      })
      asker.send(1)
      started.get()
    })
  }
}

///|
/// A protocol where only `Request` carries a reply destination.
enum Load {
  Block
  Filler
  Request(@actors.Reply[Int])
}

///|
async test "ASK-1: an ask blocked on a full mailbox gets the actor's failure" {
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let ready : @aio.Queue[@actors.ActorRef[Load]] = @aio.Queue(kind=Unbounded)
  let log = []
  let outcome = @aio.with_task_group(group => {
    // The failing scope runs in its own task, outside the caller.
    group.spawn_bg(allow_failure=true, () => @actors.scope(scope => {
      let one = @actors.MailboxCapacity::from_int(1)
      let worker = scope.start((), mailbox=Bounded(one), (_, load : Load) => {
        match load {
          Block => {
            started.put(())
            gate.get()
            raise Boom
          }
          Filler => Continue(())
          Request(reply) => {
            ignore(reply.send(1))
            Continue(())
          }
        }
      })
      ready.put(worker.to_ref())
      worker.join()
    }))
    let worker = ready.get()
    assert_eq(worker.try_send(Block), Accepted)
    started.get()
    // The handler waits at the gate. One queued message fills the mailbox.
    assert_eq(worker.try_send(Filler), Accepted)
    assert_eq(worker.try_send(Filler), Full)
    let asked = group.spawn(() => {
      try {
        ignore(
          worker.ask(reply => {
            // `build` runs just before admission, with no suspension between.
            log.push("built")
            Request(reply)
          }),
        )
        "reply"
      } catch {
        @actors.ActorFailed(address, Boom) if address == worker.address() =>
          "failed: Boom"
        @actors.Closed(_) => "closed"
        _ => "other"
      }
    })
    while log.is_empty() {
      @aio.pause()
    }
    // The ask now waits for admission. Let the handler fail.
    gate.put(())
    asked.wait()
  })
  assert_eq(log, ["built"])
  assert_eq(outcome, "failed: Boom")
}

///|
async test "ASK-1: an ask to an actor that already failed gets the failure" {
  let ready : @aio.Queue[@actors.ActorRef[Load]] = @aio.Queue(kind=Unbounded)
  let outcome = @aio.with_task_group(group => {
    group.spawn_bg(allow_failure=true, () => @actors.scope(scope => {
      let worker = scope.start((), (_, load : Load) => {
        match load {
          Block => raise Boom
          Filler | Request(_) => Continue(())
        }
      })
      ready.put(worker.to_ref())
      worker.join()
    }))
    let worker = ready.get()
    worker.send(Block)
    while worker.try_send(Filler) != Closed {
      @aio.pause()
    }
    try {
      ignore(worker.ask(reply => Request(reply)))
      "reply"
    } catch {
      @actors.ActorFailed(_, Boom) => "failed: Boom"
      @actors.Closed(_) => "closed"
      _ => "other"
    }
  })
  assert_eq(outcome, "failed: Boom")
}

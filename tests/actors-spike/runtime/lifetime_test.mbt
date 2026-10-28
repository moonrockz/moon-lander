///|
suberror Boom {
  Boom
} derive(Debug)

///|
/// A protocol whose request never gets a reply from the handler.
enum Job {
  Wait(@actors.Reply[Int])
  Fail(@actors.Reply[Int])
}

///|
async test "LIFE-1: scope exit cancels an idle actor and runs its cleanup" {
  let log = []
  let (idle, receiver) = @actors.scope(scope => {
    let idle = scope.start(0, (state, _ : Int) => Continue(state))
    let receiver = scope.spawn((inbox : @actors.Inbox[String]) => {
      defer log.push("cleanup")
      ignore(inbox.receive())
      "never"
    })
    log.push("body returns")
    (idle, receiver)
  })
  log.push("scope returned")
  assert_eq(log, ["body returns", "cleanup", "scope returned"])
  assert_true(idle.is_ended())
  assert_true(receiver.is_ended())
  let joined = try {
    ignore(receiver.join())
    "result"
  } catch {
    @actors.ActorCancelled(_) => "cancelled"
    _ => "other"
  }
  assert_eq(joined, "cancelled")
}

///|
async test "LIFE-1: a parent that returns cancels and joins its child first" {
  let log = []
  let child_cell : Ref[@actors.Actor[String, Unit]?] = Ref(None)
  let result = @actors.scope(scope => {
    let parent = scope.spawn((inbox : @actors.Inbox[Int]) => {
      let child = inbox
        .scope()
        .spawn((child_inbox : @actors.Inbox[String]) => {
          defer log.push("child cleanup")
          ignore(child_inbox.receive())
        })
      child_cell.val = Some(child)
      log.push("parent returns")
      42
    })
    let result = parent.join()
    log.push("parent joined")
    result
  })
  assert_eq(result, 42)
  assert_eq(log, ["parent returns", "child cleanup", "parent joined"])
  assert_true(child_cell.val.unwrap().is_ended())
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

///|
/// A private service with mutable state.
struct Account {
  mut balance : Int
  log : Array[String]
}

///|
suberror Refused {
  Refused(String)
} derive(Debug)

///|
async test "SVC-1: a service gives typed results of different types with no message enum" {
  @actors.scope(scope => {
    let account = scope.create({ balance: 10, log: [] })
    let balance : Int = account.ask(service => service.balance)
    let text : String = account.ask(service => {
      @aio.pause()
      "balance \{service.balance}"
    })
    assert_eq(balance, 10)
    assert_eq(text, "balance 10")
  })
}

///|
async test "SVC-1: an ask error goes to its caller, and the next call sees the earlier change" {
  @actors.scope(scope => {
    let account = scope.create({ balance: 10, log: [] })
    let outcome = try {
      account.ask(service => {
        service.balance -= 30
        if service.balance < 0 {
          raise Refused("overdrawn")
        }
        service.balance
      })
      |> ignore
      "answered"
    } catch {
      Refused(reason) => "refused: \{reason}"
      _ => "other"
    }
    assert_eq(outcome, "refused: overdrawn")
    assert_eq(account.ask(service => service.balance), -20)
    assert_true(account.status() is Running)
  })
}

///|
async test "SVC-1: calls run one at a time on the service task" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = @actors.scope(scope => {
    let account = scope.create({ balance: 0, log: [] })
    @aio.with_task_group(group => {
      group.spawn_bg(() => {
        account.ask(service => {
          service.log.push("first starts")
          started.put(())
          gate.get()
          service.log.push("first ends")
        })
      })
      started.get()
      group.spawn_bg(() => account.ask(service => service.log.push("second")))
      @aio.pause()
      gate.put(())
    })
    account.ask(service => service.log.copy())
  })
  assert_eq(log, ["first starts", "first ends", "second"])
}

///|
async test "SVC-1: a tell failure ends the service, runs its cleanup and fails the owner scope" {
  let log = []
  let never : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let outcome = try {
    @actors.scope(scope => {
      let account = scope.create({ balance: 0, log: [] }, on_stop=() => {
        log.push("cleanup")
      })
      account.tell(_ => raise Refused("tell"))
      never.get()
    })
    "returned"
  } catch {
    Refused(reason) => "failed: \{reason}"
    _ => "other"
  }
  assert_eq(outcome, "failed: tell")
  assert_eq(log, ["cleanup"])
}

///|
async test "SVC-1: closing a service lets the running call finish and wakes a queued caller with Closed" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let outcomes = []
  @actors.scope(scope => {
    let account = scope.create({ balance: 0, log: [] })
    @aio.with_task_group(group => {
      let running = group.spawn(() => {
        account.ask(service => {
          started.put(())
          gate.get()
          service.balance += 1
          service.balance
        })
      })
      started.get()
      let queued = group.spawn(() => {
        try {
          ignore(account.ask(service => service.balance))
          "answered"
        } catch {
          @actors.Closed(_) => "closed"
          _ => "other"
        }
      })
      @aio.pause()
      account.close()
      outcomes.push(queued.wait())
      gate.put(())
      outcomes.push("running \{running.wait()}")
    })
    account.join()
    assert_true(account.status() is Ended(Completed))
  })
  assert_eq(outcomes, ["closed", "running 1"])
}

///|
async test "SVC-1: a service drains its queued calls and can be cancelled" {
  @actors.scope(scope => {
    let account = scope.create({ balance: 0, log: [] })
    account.tell(service => service.balance += 5)
    account.drain()
    let late = try {
      account.tell(service => service.balance += 1)
      "admitted"
    } catch {
      @actors.Closed(_) => "closed"
      _ => "other"
    }
    assert_eq(late, "closed")
    let other = scope.create(0)
    other.cancel()
    let joined = try {
      other.join()
      "result"
    } catch {
      @actors.ActorCancelled(address) if address == other.address() => "cancelled"
      _ => "other"
    }
    assert_eq(joined, "cancelled")
  })
}

///|
async test "SVC-1: a responder answers with the handler result and no reply plumbing" {
  @actors.scope(scope => {
    let doubler = scope.respond(value => {
      @aio.pause()
      value * 2
    })
    assert_eq(doubler.ask(21), 42)
    assert_eq(doubler.try_ask(4), Some(8))
  })
}

///|
async test "SVC-1: a rejection in the reply type does not end the responder" {
  @actors.scope(scope => {
    let checker = scope.respond((value : Int) => {
      if value < 0 {
        Err("negative")
      } else {
        Ok(value)
      }
    })
    assert_eq(checker.ask(-1), Err("negative"))
    assert_eq(checker.ask(3), Ok(3))
    assert_true(checker.status() is Running)
  })
}

///|
async test "SVC-1: a responder handler error ends it and wakes every pending caller with the cause" {
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let ready : @aio.Queue[@actors.RequestActor[Int, Int]] = @aio.Queue(
    kind=Unbounded,
  )
  let outcomes = @aio.with_task_group(group => {
    group.spawn_bg(allow_failure=true, () => @actors.scope(scope => {
      let failing = scope.respond((value : Int) => {
        started.put(())
        gate.get()
        if value == 0 {
          raise Refused("zero")
        }
        value
      })
      ready.put(failing)
      failing.join()
    }))
    let failing = ready.get()
    let first = group.spawn(() => {
      try {
        ignore(failing.ask(0))
        "answered"
      } catch {
        @actors.ActorFailed(_, Refused(reason)) => "failed: \{reason}"
        _ => "other"
      }
    })
    started.get()
    let second = group.spawn(() => {
      try {
        ignore(failing.ask(1))
        "answered"
      } catch {
        @actors.ActorFailed(_, Refused(reason)) => "failed: \{reason}"
        _ => "other"
      }
    })
    @aio.pause()
    gate.put(())
    [first.wait(), second.wait()]
  })
  assert_eq(outcomes, ["failed: zero", "failed: zero"])
}

///|
async test "SVC-1: service and responder share the admission rules of actors" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let one = @actors.MailboxCapacity::from_int(1)
  @actors.scope(scope => {
    let account = scope.create({ balance: 0, log: [] }, mailbox=Bounded(one))
    account.tell(_ => {
      started.put(())
      gate.get()
    })
    started.get()
    account.tell(service => service.balance += 1)
    let limit = @lander_core.TimeLimit::millis(20)
    // The full mailbox makes the ask time out during admission.
    let asked = account.ask(service => service.balance, timeout=Within(limit)) catch {
      @actors.TimedOut(_) => -1
      error => raise error
    }
    assert_eq(asked, -1)
    gate.put(())
    assert_eq(account.ask(service => service.balance), 1)
    let responder = scope.respond((value : Int) => value, mailbox=Bounded(one))
    responder.close()
    let closed = try {
      ignore(responder.ask(1))
      "answered"
    } catch {
      @actors.Closed(address) if address == responder.address() => "closed"
      _ => "other"
    }
    assert_eq(closed, "closed")
  })
}

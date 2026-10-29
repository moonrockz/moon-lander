///|
/// A protocol where the actor holds one reply and answers it later.
enum Clerk {
  Hold(@actors.Reply[String])
  Answer(@actors.Reply[String])
  Number(@actors.Reply[Int])
  Text(@actors.Reply[String])
  Twice(@actors.Reply[Int])
  Leave(@actors.Reply[Int])
}

///|
/// A clerk actor. `held` gets an acknowledgement when it holds a reply.
fn clerk(
  scope : @actors.Scope,
  held : @aio.Queue[Unit],
  log : Array[String],
) -> @actors.Actor[Clerk, Unit] raise @actors.ActorError {
  let holding : Ref[@actors.Reply[String]?] = Ref(None)
  scope.start(0, (count, message) => {
    match message {
      Hold(reply) => {
        holding.val = Some(reply)
        held.put(())
        Continue(count)
      }
      Answer(reply) => {
        ignore(reply.send("second"))
        if holding.val is Some(first) {
          ignore(first.send("first"))
        }
        Continue(count)
      }
      Number(reply) => {
        ignore(reply.send(count))
        Continue(count + 1)
      }
      Text(reply) => {
        ignore(reply.send("count \{count}"))
        Continue(count)
      }
      Twice(reply) => {
        log.push(if reply.send(1) is Delivered { "Delivered" } else { "Expired" })
        log.push(if reply.send(2) is Delivered { "Delivered" } else { "Expired" })
        Continue(count)
      }
      Leave(reply) => {
        // The reply is dropped: the caller sees the end.
        ignore(reply)
        Stop
      }
    }
  })
}

///|
async test "Concurrent requests: each caller receives only its own reply" {
  let held : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let replies = @actors.scope(scope => {
    let actor = clerk(scope, held, [])
    @aio.with_task_group(group => {
      let first = group.spawn(() => actor.ask(reply => Hold(reply)))
      held.get()
      let second = actor.ask(reply => Answer(reply))
      [first.wait(), second]
    })
  })
  assert_eq(replies, ["first", "second"])
}

///|
async test "Duplicate or late reply: the duplicate reports expired and the actor goes on" {
  let held : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  @actors.scope(scope => {
    let actor = clerk(scope, held, log)
    assert_eq(actor.ask(reply => Twice(reply)), 1)
    assert_eq(actor.ask(reply => Number(reply)), 0)
  })
  assert_eq(log, ["Delivered", "Expired"])
}

///|
async test "Different replies in one protocol: an Int and a String" {
  let held : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let actor = clerk(scope, held, [])
    let number : Int = actor.ask(reply => Number(reply))
    let text : String = actor.ask(reply => Text(reply))
    assert_eq((number, text), (0, "count 1"))
  })
}

///|
async test "Explicit indefinite wait: the ask wakes with closed" {
  let held : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let outcome = @actors.scope(scope => {
    let actor = clerk(scope, held, [])
    try {
      ignore(actor.ask(reply => Leave(reply), timeout=UntilStopped))
      "answered"
    } catch {
      @actors.Closed(_) => "closed"
      _ => "other"
    }
  })
  assert_eq(outcome, "closed")
}

///|
suberror Fault {
  Fault
} derive(Debug)

///|
async test "Actor fails before replying: every caller wakes with the cause" {
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let ready : @aio.Queue[@actors.ActorRef[@actors.Reply[Int]]] = @aio.Queue(
    kind=Unbounded,
  )
  let outcomes = @aio.with_task_group(group => {
    group.spawn_bg(allow_failure=true, () => @actors.scope(scope => {
      let actor = scope.start((), (_, reply : @actors.Reply[Int]) => {
        ignore(reply)
        started.put(())
        gate.get()
        raise Fault
      })
      ready.put(actor.to_ref())
      actor.join()
    }))
    let actor = ready.get()
    let ask = async fn() -> String {
      try {
        ignore(actor.ask(reply => reply))
        "answered"
      } catch {
        @actors.ActorFailed(_, Fault) => "failed"
        _ => "other"
      }
    }
    let first = group.spawn(ask)
    started.get()
    let second = group.spawn(ask)
    while actor.queued_count() == 0 {
      @aio.pause()
    }
    gate.put(())
    [first.wait(), second.wait()]
  })
  assert_eq(outcomes, ["failed", "failed"])
}

///|
async test "Cancel a caller: the request changes the state and its reply expires" {
  let held : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let actor = clerk(scope, held, [])
    @aio.with_task_group(group => {
      let caller = group.spawn(() => actor.ask(reply => Hold(reply)))
      held.get()
      caller.cancel()
    })
    // The held reply now expires; the actor still works.
    assert_eq(actor.ask(reply => Answer(reply)), "second")
    assert_eq(actor.ask(reply => Number(reply)), 0)
  })
}

///|
async test "Map an event to a protocol: the event enters the same mailbox" {
  @actors.scope(scope => {
    let totals = scope.start(0, (sum, message : Result[Int, @actors.Reply[Int]]) => {
      match message {
        Ok(value) => Continue(sum + value)
        Err(reply) => {
          ignore(reply.send(sum))
          Continue(sum)
        }
      }
    })
    let events : @actors.Subject[Int] = totals.to_ref().to_subject().contramap(value => Ok(value))
    events.send(2)
    totals.send(Ok(40))
    assert_eq(totals.ask(reply => Err(reply)), 42)
  })
}

///|
async test "Ask a custom destination: the ask returns the typed response" {
  let custom : @actors.Subject[@actors.Reply[String]] = @actors.Subject::new(
    send=reply => {
      ignore(reply.send("custom"))
      Admitted
    },
    try_send=_ => Accepted,
  )
  assert_eq(custom.ask(reply => reply), "custom")
}

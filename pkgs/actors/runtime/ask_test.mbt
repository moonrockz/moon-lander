///|
/// A protocol for request tests.
enum Desk {
  /// Hold the reply until the next `Release`.
  Hold(@actors.Reply[String])
  /// Answer the held reply, then this one.
  Release(@actors.Reply[String])
  /// Reply two times.
  Twice(@actors.Reply[Int])
  /// Wait at the gate, then add one to the state and reply.
  Slow(@actors.Reply[Int])
  /// Reply with the state.
  Count(@actors.Reply[Int])
  /// End without a reply.
  Quit(@actors.Reply[Int])
  /// Answer through a reply destination, two times.
  ViaSubject(@actors.Reply[Int])
  /// A note without a reply.
  Noted(String)
}

///|
fn ms_limit(count : Int) -> @actors.WaitPolicy {
  Within(@lander_core.TimeLimit::millis(count)) catch {
    _ => panic()
  }
}

///|
/// A desk actor. `log` gets the outcomes of the replies that it sends.
fn start_desk(
  scope : @actors.Scope,
  gate : @aio.Queue[Unit],
  started : @aio.Queue[Unit],
  log : Array[String],
  mailbox? : @actors.MailboxPolicy = @actors.MailboxPolicy::default(),
) -> @actors.Actor[Desk, Unit] raise @actors.ActorError {
  let held : Ref[@actors.Reply[String]?] = Ref(None)
  scope.start(0, mailbox~, (count, message) => {
    match message {
      Hold(reply) => {
        held.val = Some(reply)
        started.put(())
        Continue(count)
      }
      Release(reply) => {
        if held.val is Some(first) {
          log.push("first \{first.send("first") == Delivered}")
        }
        ignore(reply.send("second"))
        Continue(count)
      }
      Twice(reply) => {
        log.push("one \{reply.send(1) == Delivered}")
        log.push("two \{reply.send(2) == Delivered}")
        Continue(count)
      }
      Slow(reply) => {
        started.put(())
        gate.get()
        log.push("slow \{reply.send(count + 1) == Delivered}")
        Continue(count + 1)
      }
      Count(reply) => {
        ignore(reply.send(count))
        Continue(count)
      }
      Quit(reply) => {
        ignore(reply)
        Stop
      }
      ViaSubject(reply) => {
        let subject = @actors.Subject::from_reply(reply)
        log.push("reply \{subject.try_send(count) == Accepted}")
        log.push("again \{subject.try_send(count) == Closed}")
        Continue(count)
      }
      Noted(text) => {
        log.push("noted \{text}")
        Continue(count)
      }
    }
  })
}

///|
async test "ASK-1: two callers each get their own reply when the actor answers in reverse order" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  let (first, second) = @actors.scope(scope => {
    let desk = start_desk(scope, gate, started, log)
    @aio.with_task_group(group => {
      let first = group.spawn(() => desk.ask(reply => Hold(reply)))
      started.get()
      let second = desk.ask(reply => Release(reply))
      (first.wait(), second)
    })
  })
  assert_eq((first, second), ("first", "second"))
}

///|
async test "ASK-1: a duplicate reply reports Expired and the actor goes on" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  @actors.scope(scope => {
    let desk = start_desk(scope, gate, started, log)
    assert_eq(desk.ask(reply => Twice(reply)), 1)
    assert_eq(desk.ask(reply => Count(reply)), 0)
  })
  assert_eq(log, ["one true", "two false"])
}

///|
async test "ASK-1: a reply after the caller timed out reports Expired, and the request still changed the state" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  @actors.scope(scope => {
    let desk = start_desk(scope, gate, started, log)
    let outcome = try {
      ignore(desk.ask(reply => Slow(reply), timeout=ms_limit(20)))
      "reply"
    } catch {
      @actors.TimedOut(_) => "timed out"
      _ => "other"
    }
    assert_eq(outcome, "timed out")
    started.get()
    gate.put(())
    assert_eq(desk.ask(reply => Count(reply)), 1)
  })
  assert_eq(log, ["slow false"])
}

///|
async test "ASK-1: try_ask gives None only on timeout" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  @actors.scope(scope => {
    let desk = start_desk(scope, gate, started, log)
    assert_eq(desk.try_ask(reply => Count(reply)), Some(0))
    assert_eq(desk.try_ask(reply => Slow(reply), timeout=ms_limit(10)), None)
    started.get()
    gate.put(())
    ignore(desk.try_ask(reply => Quit(reply)) catch { _ => None })
    desk.join()
    let closed = try {
      ignore(desk.try_ask(reply => Count(reply)))
      "answered"
    } catch {
      @actors.Closed(_) => "closed"
      _ => "other"
    }
    assert_eq(closed, "closed")
  })
}

///|
async test "ASK-1: admission uses the same deadline as the reply" {
  // Admission waits about 150 ms of a 250 ms limit, and the reply comes
  // 150 ms after admission. One deadline times out; two would not.
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  let one = @actors.MailboxCapacity::from_int(1)
  let outcome = @actors.scope(scope => {
    let desk = start_desk(scope, gate, started, log, mailbox=Bounded(one))
    @aio.with_task_group(group => {
      group.spawn_bg(() => ignore(desk.ask(reply => Slow(reply))))
      started.get()
      group.spawn_bg(() => ignore(desk.ask(reply => Slow(reply))))
      while desk.queued_count() == 0 {
        @aio.pause()
      }
      group.spawn_bg(() => {
        @aio.sleep(150)
        gate.put(())
        started.get()
        @aio.sleep(150)
        gate.put(())
        started.get()
        gate.put(())
      })
      try {
        ignore(desk.ask(reply => Slow(reply), timeout=ms_limit(250)))
        "reply"
      } catch {
        @actors.TimedOut(_) => "timed out"
        _ => "other"
      }
    })
  })
  assert_eq(outcome, "timed out")
}

///|
async test "ASK-1: an indefinite ask wakes with Closed when the actor ends without a reply" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  let outcome = @actors.scope(scope => {
    let desk = start_desk(scope, gate, started, log)
    try {
      ignore(desk.ask(reply => Quit(reply), timeout=UntilStopped))
      "reply"
    } catch {
      @actors.Closed(address) if address == desk.address() => "closed"
      _ => "other"
    }
  })
  assert_eq(outcome, "closed")
}

///|
async test "ASK-1: close wakes a discarded ask at once and keeps the in-flight ask replyable" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  let events = []
  @actors.scope(scope => {
    let desk = start_desk(scope, gate, started, log)
    @aio.with_task_group(group => {
      let in_flight = group.spawn(() => desk.ask(reply => Slow(reply)))
      started.get()
      let queued = group.spawn(() => {
        try {
          ignore(desk.ask(reply => Count(reply)))
          events.push("queued answered")
        } catch {
          @actors.Closed(_) => events.push("queued closed")
          _ => events.push("queued other")
        }
      })
      while desk.queued_count() == 0 {
        @aio.pause()
      }
      guard desk.close() is Some(pending) else { fail("no snapshot") }
      assert_eq(pending.length(), 1)
      queued.wait()
      // The discarded ask woke while the in-flight message still waits.
      events.push("in flight still waits")
      gate.put(())
      events.push("in flight \{in_flight.wait()}")
    })
    desk.join()
  })
  assert_eq(events, ["queued closed", "in flight still waits", "in flight 1"])
  assert_eq(log, ["slow true"])
}

///|
suberror Jam {
  Jam
} derive(Debug)

///|
async test "ASK-1: a failure wakes in-flight and queued asks with the cause" {
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let ready : @aio.Queue[@actors.ActorRef[Desk]] = @aio.Queue(kind=Unbounded)
  let outcomes = @aio.with_task_group(group => {
    group.spawn_bg(allow_failure=true, () => @actors.scope(scope => {
      let desk = scope.start((), (_, message : Desk) => {
        match message {
          Slow(_) => {
            started.put(())
            gate.get()
            raise Jam
          }
          _ => Continue(())
        }
      })
      ready.put(desk.to_ref())
      desk.join()
    }))
    let desk = ready.get()
    let asks = [
      group.spawn(() => {
        try {
          ignore(desk.ask(reply => Slow(reply)))
          "reply"
        } catch {
          @actors.ActorFailed(_, Jam) => "failed: Jam"
          _ => "other"
        }
      }),
    ]
    started.get()
    asks.push(
      group.spawn(() => {
        try {
          ignore(desk.ask(reply => Count(reply)))
          "reply"
        } catch {
          @actors.ActorFailed(_, Jam) => "failed: Jam"
          _ => "other"
        }
      }),
    )
    while desk.queued_count() == 0 {
      @aio.pause()
    }
    gate.put(())
    [asks[0].wait(), asks[1].wait()]
  })
  assert_eq(outcomes, ["failed: Jam", "failed: Jam"])
}

///|
async test "ASK-1: a cancelled caller leaves its admitted request intact" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  @actors.scope(scope => {
    let desk = start_desk(scope, gate, started, log)
    @aio.with_task_group(group => {
      let caller = group.spawn(() => desk.ask(reply => Slow(reply)))
      started.get()
      caller.cancel()
    })
    gate.put(())
    assert_eq(desk.ask(reply => Count(reply)), 1)
    assert_true(desk.status() is Running)
  })
  assert_eq(log, ["slow false"])
}

///|
/// Events that a desk can take through a mapped destination.
enum Note {
  Note(String)
}

///|
async test "ASK-1: subjects of references, replies, queues and functions report delivery" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  let one = @actors.MailboxCapacity::from_int(1)
  @actors.scope(scope => {
    let desk = start_desk(scope, gate, started, log, mailbox=Bounded(one))
    let subject = desk.to_ref().to_subject()
    // A mapped destination puts the message in the same mailbox: there is no
    // other queue, so a full mailbox is full through it too.
    let mapped : @actors.Subject[Note] = subject.contramap(note => {
      let Note(text) = note
      Noted(text)
    })
    @aio.with_task_group(group => {
      group.spawn_bg(() => ignore(desk.ask(reply => Slow(reply))))
      started.get()
      assert_eq(mapped.try_send(Note("a")), Accepted)
      assert_eq(desk.queued_count(), 1)
      assert_eq(subject.try_send(Noted("direct")), Full)
      assert_eq(mapped.try_send(Note("b")), Full)
      gate.put(())
    })
    // A reply destination delivers once.
    assert_eq(desk.ask(reply => ViaSubject(reply)), 1)
    // A queue destination follows the queue.
    let queue : @aio.Queue[Int] = @aio.Queue(kind=Blocking(1))
    let to_queue = @actors.Subject::from_queue(queue)
    to_queue.send(1)
    assert_eq(to_queue.try_send(2), Full)
    queue.close()
    assert_eq(to_queue.try_send(3), Closed)
    let closed = try {
      to_queue.send(4)
      "admitted"
    } catch {
      @actors.DestinationClosed => "closed"
      _ => "other"
    }
    assert_eq(closed, "closed")
  })
  assert_eq(log, ["slow true", "noted a", "reply true", "again true"])
}

///|
async test "ASK-1: an ask through a custom destination gets the response that it sends" {
  let seen = []
  let custom : @actors.Subject[Desk] = @actors.Subject::new(
    send=message => {
      match message {
        Count(reply) => {
          seen.push("count")
          ignore(reply.send(42))
        }
        _ => seen.push("other")
      }
      true
    },
    try_send=_ => Closed,
  )
  assert_eq(custom.ask(reply => Count(reply)), 42)
  let silent : @actors.Subject[Desk] = @actors.Subject::new(
    send=_ => true,
    try_send=_ => Accepted,
  )
  assert_eq(silent.try_ask(reply => Count(reply), timeout=ms_limit(10)), None)
  let refusing : @actors.Subject[Desk] = @actors.Subject::new(
    send=_ => false,
    try_send=_ => Closed,
  )
  let outcome = try {
    ignore(refusing.ask(reply => Count(reply)))
    "answered"
  } catch {
    @actors.DestinationClosed => "closed"
    _ => "other"
  }
  assert_eq(outcome, "closed")
  assert_eq(seen, ["count"])
}

///|
async test "ASK-1: an ask through an actor subject sees the actor end" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  let outcome = @actors.scope(scope => {
    let desk = start_desk(scope, gate, started, log)
    let subject = desk.to_ref().to_subject()
    assert_eq(subject.ask(reply => Count(reply)), 0)
    try {
      ignore(subject.ask(reply => Quit(reply), timeout=UntilStopped))
      "answered"
    } catch {
      @actors.Closed(_) => "closed"
      _ => "other"
    }
  })
  assert_eq(outcome, "closed")
}

///|
fn ms(count : Int) -> @lander_core.TimeLimit {
  @lander_core.TimeLimit::millis(count) catch {
    _ => panic()
  }
}

///|
fn one() -> @actors.MailboxPolicy {
  Bounded(@actors.MailboxCapacity::from_int(1)) catch {
    _ => panic()
  }
}

///|
async test "Receive order: three receives give A, B and C" {
  let three = @actors.scope(scope => {
    let actor = scope.spawn(_ => {
      @actors.receive()
      .zip(@actors.receive())
      .zip_with(@actors.receive(), (pair, c) => [pair.0, pair.1, c])
    })
    actor.send("A")
    actor.send("B")
    actor.send("C")
    actor.join()
  })
  assert_eq(three, ["A", "B", "C"])
}

///|
async test "Timeout preserves the mailbox: a later message is the next receive" {
  let expired : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = @actors.scope(scope => {
    let actor = scope.spawn(_ => {
      @actors.receive()
      .within(ms(10), on_timeout=() => @actors.done("expired"))
      .bind(first => {
        expired.put(())
        @actors.receive().map(second => [first, second])
      })
    })
    expired.get()
    actor.send("message")
    actor.join()
  })
  assert_eq(log, ["expired", "message"])
}

///|
async test "Poll after close: a poll on a closed empty mailbox continues as closed" {
  let polled = @actors.poll(on_empty=() => @actors.done("empty")).on_closed(() => {
    @actors.done("closed")
  })
  assert_eq(@actors.run_test(polled, [], at_end=Close).result(), Some("closed"))
}

///|
async test "Skip an earlier message: select B, then receive A and C" {
  let log = @actors.scope(scope => {
    let actor = scope.spawn(_ => {
      @actors.select(message => if message == "B" { Some(message) } else { None })
      .zip(@actors.receive())
      .zip_with(@actors.receive(), (pair, c) => [pair.0, pair.1, c])
    })
    actor.send("A")
    actor.send("B")
    actor.send("C")
    actor.join()
  })
  assert_eq(log, ["B", "A", "C"])
}

///|
async test "Non-matches still occupy capacity, and a timed select keeps them" {
  let log = @actors.scope(scope => {
    let actor = scope.spawn(mailbox=one(), _ => {
      @actors.select(message => if message == "match" { Some(message) } else { None })
      .within(ms(20), on_timeout=() => @actors.done("expired"))
      .zip(@actors.receive())
      .zip_with(@actors.receive(), (pair, last) => [pair.0, pair.1, last])
    })
    actor.send("skip")
    assert_eq(actor.try_send("match"), Full)
    @aio.with_task_group(group => {
      // This send waits until the timed select ends and the actor takes "skip".
      group.spawn_bg(() => actor.send("match"))
      actor.join()
    })
  })
  assert_eq(log, ["expired", "skip", "match"])
}

///|
async test "Full mailbox: the producer waits until the actor takes the queued message" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let events = []
  @actors.scope(scope => {
    let actor = scope.start((), mailbox=one(), (_, _ : Int) => {
      started.put(())
      gate.get()
      Continue(())
    })
    actor.send(1)
    started.get()
    actor.send(2)
    @aio.with_task_group(group => {
      group.spawn_bg(() => {
        actor.send(3)
        events.push("admitted")
      })
      @aio.pause()
      events.push("waiting")
      gate.put(())
    })
    gate.put(())
    gate.put(())
  })
  assert_eq(events, ["waiting", "admitted"])
}

///|
async test "Unbounded opt-in: more than 128 messages without a wait" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let actor = scope.start((), mailbox=Unbounded, (_, _ : Int) => {
      gate.get()
      Continue(())
    })
    for value in 0..<200 {
      assert_eq(actor.try_send(value), Accepted)
    }
    for _ in 0..<200 {
      gate.put(())
    }
  })
}

///|
async test "Reenqueue keeps FIFO order: B then C" {
  let log = @actors.scope(scope => {
    let actor = scope.spawn(context => {
      @actors.receive().bind(a => {
        ignore(context.reenqueue("C"))
        @actors.receive().zip_with(@actors.receive(), (b, c) => [a, b, c])
      })
    })
    actor.send("A")
    actor.send("B")
    actor.join()
  })
  assert_eq(log, ["A", "B", "C"])
}

///|
async test "Unit test of a protocol: the test runner keeps the noise in order" {
  let receive = @actors.select(message => if message == "hello" { Some(1) } else { None })
    .zip_with(
      @actors.select(message => if message == "pin" { Some(2) } else { None }),
      (a, b) => a + b,
    )
  let run = @actors.run_test(receive, ["noise", "pin", "hello", "noise"])
  assert_eq(run.result(), Some(3))
  assert_eq(run.remaining(), ["noise", "noise"])
}

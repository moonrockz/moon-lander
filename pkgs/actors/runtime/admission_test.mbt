///|
/// A protocol for admission tests: `Block` waits at a gate.
enum Work {
  Block
  Item(Int)
  End
}

///|
fn capacity(count : Int) -> @actors.MailboxPolicy {
  Bounded(@actors.MailboxCapacity::from_int(count)) catch {
    _ => panic()
  }
}

///|
/// Start a worker that logs each item, waits at `gate` on `Block` and stops on
/// `End`. `started` gets an acknowledgement when a `Block` starts.
fn start_worker(
  scope : @actors.Scope,
  mailbox : @actors.MailboxPolicy,
  log : Array[Int],
  started : @aio.Queue[Unit],
  gate : @aio.Queue[Unit],
) -> @actors.Actor[Work, Unit] raise @actors.ActorError {
  scope.start((), mailbox~, (_, work) => {
    match work {
      Block => {
        started.put(())
        gate.get()
        Continue(())
      }
      Item(value) => {
        log.push(value)
        Continue(())
      }
      End => Stop
    }
  })
}

///|
async test "ADM-1: the default mailbox admits 128 queued messages and then is full" {
  let log = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let worker = start_worker(
      scope,
      @actors.MailboxPolicy::default(),
      log,
      started,
      gate,
    )
    worker.send(Block)
    started.get()
    // The message in progress does not count.
    for value in 0..<128 {
      assert_eq(worker.try_send(Item(value)), Accepted)
    }
    assert_eq(worker.queued_count(), 128)
    assert_eq(worker.try_send(Item(128)), Full)
    gate.put(())
    worker.send(End)
    worker.join()
  })
  // No message was dropped or overwritten.
  assert_eq(log, Array::makei(128, value => value))
}

///|
async test "ADM-1: a full mailbox makes send wait until the actor takes a message" {
  let log = []
  let events = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let worker = start_worker(scope, capacity(1), log, started, gate)
    worker.send(Block)
    started.get()
    worker.send(Item(1))
    @aio.with_task_group(group => {
      group.spawn_bg(() => {
        worker.send(Item(2))
        events.push("admitted")
      })
      @aio.pause()
      events.push("still full")
      assert_eq(worker.queued_count(), 1)
      gate.put(())
    })
    worker.send(End)
    worker.join()
  })
  assert_eq(events, ["still full", "admitted"])
  assert_eq(log, [1, 2])
}

///|
async test "ADM-1: an unbounded mailbox admits more than 128 messages without waiting" {
  let log = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let worker = start_worker(scope, Unbounded, log, started, gate)
    worker.send(Block)
    started.get()
    for value in 0..<300 {
      assert_eq(worker.try_send(Item(value)), Accepted)
    }
    assert_eq(worker.queued_count(), 300)
    gate.put(())
    worker.send(End)
    worker.join()
  })
  assert_eq(log.length(), 300)
}

///|
async test "ADM-1: try_send gives Full and then Closed without waiting" {
  let log = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let worker = start_worker(scope, capacity(1), log, started, gate)
    worker.send(Block)
    started.get()
    assert_eq(worker.try_send(End), Accepted)
    assert_eq(worker.try_send(Item(1)), Full)
    gate.put(())
    worker.join()
    assert_eq(worker.try_send(Item(2)), Closed)
    let sent = try {
      worker.send(Item(3))
      "admitted"
    } catch {
      Closed(address) if address == worker.address() => "closed"
      _ => "other"
    }
    assert_eq(sent, "closed")
  })
  assert_eq(log, [])
}

///|
async test "ADM-1: a producer cancelled before admission leaves no message" {
  let log = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let worker = start_worker(scope, capacity(1), log, started, gate)
    worker.send(Block)
    started.get()
    worker.send(Item(1))
    @aio.with_task_group(group => {
      let producer = group.spawn(() => worker.send(Item(2)))
      @aio.pause()
      producer.cancel()
    })
    assert_eq(worker.queued_count(), 1)
    gate.put(())
    worker.send(End)
    worker.join()
  })
  assert_eq(log, [1])
}

///|
async test "ADM-1: a producer cancelled after admission does not take the message back" {
  let log = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let parked : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let worker = start_worker(scope, capacity(4), log, started, gate)
    worker.send(Block)
    started.get()
    @aio.with_task_group(group => {
      let producer = group.spawn(() => {
        worker.send(Item(7))
        // The message is admitted; now the producer waits and is cancelled.
        parked.get()
      })
      while worker.queued_count() == 0 {
        @aio.pause()
      }
      producer.cancel()
    })
    gate.put(())
    worker.send(End)
    worker.join()
  })
  assert_eq(log, [7])
}

///|
async test "ADM-1: blocked producers wake with Closed when the actor ends" {
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let outcomes = []
  @actors.scope(scope => {
    let worker = scope.start((), mailbox=capacity(1), (_, work : Work) => {
      match work {
        Block => {
          started.put(())
          gate.get()
          Stop
        }
        Item(_) | End => Continue(())
      }
    })
    worker.send(Block)
    started.get()
    worker.send(Item(1))
    @aio.with_task_group(group => {
      for value in 2..<4 {
        group.spawn_bg(() => {
          let outcome = try {
            worker.send(Item(value))
            "admitted"
          } catch {
            Closed(_) => "closed"
            _ => "other"
          }
          outcomes.push(outcome)
        })
      }
      @aio.pause()
      gate.put(())
    })
    assert_eq(worker.queued_count(), 0)
  })
  assert_eq(outcomes, ["closed", "closed"])
}

///|
async test "ADM-1: queued_count is a snapshot of queued messages without the one in progress" {
  let log = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let worker = start_worker(scope, capacity(8), log, started, gate)
    assert_eq(worker.queued_count(), 0)
    worker.send(Block)
    started.get()
    assert_eq(worker.queued_count(), 0)
    worker.send(Item(1))
    worker.send(Item(2))
    assert_eq(worker.queued_count(), 2)
    assert_eq(worker.to_ref().queued_count(), 2)
    gate.put(())
    worker.send(End)
    worker.join()
  })
}

///|
/// Wait without a suspension until the clock moves by one millisecond.
fn spin_one_millisecond() -> Unit {
  let start = @aio.now()
  while @aio.now() == start {
    ()
  }
}

///|
async test "ADM-1: a busy actor yields between batches so another ready actor makes progress" {
  let order = []
  @actors.scope(scope => {
    // Each message takes about a millisecond and never suspends.
    let busy = scope.start(
      0,
      (count, _ : Int) => {
        spin_one_millisecond()
        if count == 199 {
          order.push("busy done")
        }
        Continue(count + 1)
      },
      mailbox=Unbounded,
    )
    let other = scope.start((), (_, _ : Int) => {
      order.push("other")
      Continue(())
    })
    for value in 0..<200 {
      assert_eq(busy.try_send(value), Accepted)
    }
    assert_eq(other.try_send(1), Accepted)
    while order.length() < 2 {
      @aio.pause()
    }
  })
  assert_eq(order, ["other", "busy done"])
}

///|
/// A receive that takes one message, puts it back and starts again, with no
/// suspension.
fn cycle(
  context : @actors.ActorContext[Int],
  one : @actors.MessageCount,
) -> @actors.Receive[Int, Unit] {
  @actors.receive_n(one, value => ignore(context.reenqueue(value))).bind(_ => {
    cycle(context, one)
  })
}

///|
async test "ADM-1: chained one-message loops still yield to another ready actor" {
  let order = []
  @actors.scope(scope => {
    let one = @actors.MessageCount::from_int(1)
    let busy = scope.spawn(context => cycle(context, one))
    let other = scope.start((), (_, _ : Int) => {
      order.push("other")
      Continue(())
    })
    assert_eq(busy.try_send(0), Accepted)
    assert_eq(other.try_send(1), Accepted)
    // Without a yield between batches, this wait never ends.
    while order.is_empty() {
      @aio.pause()
    }
  })
  assert_eq(order, ["other"])
}

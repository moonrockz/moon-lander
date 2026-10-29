///|
async test "ADM-1: a producer cancelled while it waits for space leaves no waiter and no message" {
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let producing : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  scope(scope => {
    let one = @policy.MailboxCapacity::from_int(1)
    let worker = scope.start((), mailbox=Bounded(one), (_, value : Int) => {
      if value == 0 {
        started.put(())
        gate.get()
      } else {
        log.push(value)
      }
      Continue(())
    })
    worker.send(0)
    started.get()
    worker.send(1)
    let mailbox = worker.target.mailbox
    @aio.with_task_group(group => {
      let producer = group.spawn(() => {
        producing.put(())
        worker.send(2)
      })
      producing.get()
      // The producer acknowledged just before its send; wait until it waits.
      while mailbox.waiting_producers == 0 {
        @aio.pause()
      }
      assert_eq(mailbox.waiting_producers, 1)
      assert_eq(worker.queued_count(), 1)
      producer.cancel()
    })
    assert_eq(mailbox.waiting_producers, 0)
    assert_eq(worker.queued_count(), 1)
    gate.put(())
    worker.send(3)
    while log.length() < 2 {
      @aio.pause()
    }
  })
  // Message 2 never entered the mailbox.
  assert_eq(log, [1, 3])
}

///|
async test "ADM-1: blocked producers wake on close and leave no waiter" {
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let outcomes = []
  scope(scope => {
    let one = @policy.MailboxCapacity::from_int(1)
    let worker = scope.start((), mailbox=Bounded(one), (_, value : Int) => {
      if value == 0 {
        started.put(())
        gate.get()
        Stop
      } else {
        Continue(())
      }
    })
    worker.send(0)
    started.get()
    worker.send(1)
    let mailbox = worker.target.mailbox
    @aio.with_task_group(group => {
      for value in 2..<4 {
        group.spawn_bg(() => {
          let outcome = try {
            worker.send(value)
            "admitted"
          } catch {
            Closed(_) => "closed"
            _ => "other"
          }
          outcomes.push(outcome)
        })
      }
      while mailbox.waiting_producers < 2 {
        @aio.pause()
      }
      gate.put(())
    })
    assert_eq(mailbox.waiting_producers, 0)
  })
  assert_eq(outcomes, ["closed", "closed"])
}

///|
/// The protocol of the ACT-2 counter. Two cases reply with different types.
enum CounterMessage {
  Increment
  Read(@actors.Reply[Int])
  Describe(@actors.Reply[String])
  Halt
}

///|
/// The counter handler as a named function. A named handler must be an
/// `async fn`; this one never suspends, so the pinned compiler needs the
/// `unused_async` warning off.
#warnings("-unused_async")
async fn handle_counter(
  state : Int,
  message : CounterMessage,
) -> @actors.Next[Int] {
  match message {
    Increment => @actors.Continue(state + 1)
    Read(reply) => {
      ignore(reply.send(state))
      @actors.Continue(state)
    }
    Describe(reply) => {
      ignore(reply.send("count \{state}"))
      Continue(state)
    }
    Halt => Stop
  }
}

///|
/// The ACT-2 counter example in the pipeline form.
async fn counter_example() -> Int {
  @actors.scope <| scope => {
    let counter = scope.start(0) <| (state, message) => {
      match message {
        Increment => @actors.Continue(state + 1)
        Read(reply) => {
          ignore(reply.send(state))
          @actors.Continue(state)
        }
        Describe(_) | Halt => @actors.Continue(state)
      }
    }
    counter.send(Increment)
    counter.ask(reply => Read(reply))
  }
}

///|
async test "ACT-2: the counter replies one after one increment" {
  assert_eq(counter_example(), 1)
}

///|
async test "ACT-2: one protocol replies with an Int and a String" {
  @actors.scope(scope => {
    let counter = scope.start(0, handle_counter)
    counter.send(Increment)
    counter.send(Increment)
    let count : Int = counter.ask(reply => Read(reply))
    let text : String = counter.ask(reply => Describe(reply))
    assert_eq(count, 2)
    assert_eq(text, "count 2")
  })
}

///|
async test "ACT-1: with concurrent producers, a handler ends before the next one starts" {
  let log = []
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let counter = scope.start(0, (state, message : CounterMessage) => {
      match message {
        Increment => {
          log.push("start \{state}")
          started.put(())
          gate.get()
          log.push("end \{state}")
          Continue(state + 1)
        }
        Read(reply) => {
          ignore(reply.send(state))
          Continue(state)
        }
        Describe(_) | Halt => Continue(state)
      }
    })
    @aio.with_task_group(group => {
      group.spawn_bg(() => counter.send(Increment))
      group.spawn_bg(() => counter.send(Increment))
    })
    started.get()
    gate.put(())
    started.get()
    gate.put(())
    assert_eq(counter.ask(reply => Read(reply)), 2)
  })
  assert_eq(log, ["start 0", "end 0", "start 1", "end 1"])
}

///|
async test "ACT-1: a second actor makes progress while the first one waits" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let waiting = scope.start((), (_, _ : Int) => {
      gate.get()
      Continue(())
    })
    let counter = scope.start(0, handle_counter)
    waiting.send(1)
    counter.send(Increment)
    assert_eq(counter.ask(reply => Read(reply)), 1)
    gate.put(())
  })
}

///|
async test "ACT-2: Stop ends a start actor normally" {
  @actors.scope(scope => {
    let counter = scope.start(0, handle_counter)
    counter.send(Halt)
    counter.join()
    assert_eq(counter.try_send(Increment), Closed)
  })
}

///|
async test "RECV-1: a finite actor gives its total and admits no more messages" {
  @actors.scope(scope => {
    let three = @actors.MessageCount::from_int(3)
    let summing = scope.spawn(_ => {
      let total = Ref(0)
      @actors.receive_n(three, (value : Int) => total.val += value).map(_ => {
        total.val
      })
    })
    summing.send(1)
    summing.send(2)
    summing.send(3)
    assert_eq(summing.join(), 6)
    assert_eq(summing.try_send(4), Closed)
  })
}

///|
async test "RECV-1: an actor does async work between two receives" {
  let ack : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let total = @actors.scope(scope => {
    let actor = scope.spawn(_ => {
      @actors.receive().bind(first => {
        ack.get()
        @actors.receive().map(second => first * 10 + second)
      })
    })
    actor.send(4)
    actor.send(2)
    ack.put(())
    actor.join()
  })
  assert_eq(total, 42)
}

///|
async test "LIFE-1: two joiners get the result after one of them is cancelled" {
  @actors.scope(scope => {
    let actor = scope.spawn(_ => @actors.receive())
    let outcomes = @aio.with_task_group(group => {
      let cancelled = group.spawn(() => actor.join())
      let kept = group.spawn(() => actor.join())
      @aio.pause()
      cancelled.cancel()
      actor.send("result")
      kept.wait()
    })
    assert_eq(outcomes, "result")
    assert_eq(actor.join(), "result")
  })
}

///|
async test "ADM-1: reenqueue appends at the tail of the own mailbox" {
  let log = @actors.scope(scope => {
    let actor = scope.spawn(context => {
      @actors.receive().bind(first => {
        // B is queued; C goes behind it.
        assert_eq(context.reenqueue("C"), Accepted)
        @actors.receive().zip_with(@actors.receive(), (second, third) => {
          [first, second, third]
        })
      })
    })
    actor.send("A")
    actor.send("B")
    actor.join()
  })
  assert_eq(log, ["A", "B", "C"])
}

///|
async test "ADM-1: reenqueue to a full own mailbox gives Full without waiting" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let one = @actors.MailboxCapacity::from_int(1)
  let log = @actors.scope(scope => {
    let actor = scope.spawn(mailbox=Bounded(one), context => {
      @actors.receive().bind(first => {
        gate.get()
        let admission = context.reenqueue("again")
        let queued = context.queued_count()
        @actors.receive().map(second => {
          (first, second, admission, queued)
        })
      })
    })
    actor.send("A")
    actor.send("B")
    gate.put(())
    actor.join()
  })
  assert_eq(log, ("A", "B", Full, 1))
}

///|
async test "RECV-1: the context reference sends to the actor itself" {
  let result = @actors.scope(scope => {
    let actor = scope.spawn(context => {
      @actors.done(()).bind(_ => {
        context.self_ref().send(5)
        @actors.receive()
      })
    })
    actor.join()
  })
  assert_eq(result, 5)
}

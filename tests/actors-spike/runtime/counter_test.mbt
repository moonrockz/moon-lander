///|
/// The protocol of the ACT-2 counter. Two cases reply with different types.
enum CounterMessage {
  Increment
  Read(@actors.Reply[Int])
  Describe(@actors.Reply[String])
  Halt
}

///|
/// The counter handler, as a named function for the NAME-1 example. A named
/// handler must be an `async fn`; this one never suspends, so the pinned
/// compiler needs the `unused_async` warning off.
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
/// The ACT-2 counter example as the design shows it, with the compiled forms.
async fn counter_example() -> Int {
  @actors.scope(scope => {
    let counter = scope.start(0, (state, message) => {
      match message {
        Increment => @actors.Continue(state + 1)
        Read(reply) => {
          ignore(reply.send(state))
          @actors.Continue(state)
        }
        Describe(_) | Halt => @actors.Continue(state)
      }
    })
    counter.send(Increment)
    counter.ask(reply => Read(reply))
  })
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
async test "ACT-1: a handler ends before the next one starts" {
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

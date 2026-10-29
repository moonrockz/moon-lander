///|
/// The counter of the requirement "Start an anonymous typed actor".
enum Counter {
  Increment
  Read(@actors.Reply[Int])
}

///|
/// The counter handler. It waits at `gate` when one is given.
fn counter(
  gate? : @aio.Queue[Unit],
) -> async (Int, Counter) -> @actors.Next[Int] {
  (state, message) => {
    match message {
      Increment => {
        if gate is Some(gate) {
          gate.get()
        }
        @actors.Continue(state + 1)
      }
      Read(reply) => {
        ignore(reply.send(state))
        @actors.Continue(state)
      }
    }
  }
}

///|
async test "Counter with default settings: the reply is one" {
  let count = @actors.scope(scope => {
    let actor = scope.start(0, counter())
    actor.send(Increment)
    actor.ask(reply => Read(reply))
  })
  assert_eq(count, 1)
}

///|
async test "Concurrent producers: the second handler starts after the first ends" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let count = @actors.scope(scope => {
    let actor = scope.start(0, counter(gate~))
    @aio.with_task_group(group => {
      group.spawn_bg(() => actor.send(Increment))
      group.spawn_bg(() => actor.send(Increment))
    })
    gate.put(())
    gate.put(())
    actor.ask(reply => Read(reply))
  })
  assert_eq(count, 2)
}

///|
async test "Independent actors: one actor waits while another processes" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let waiting = scope.start(0, counter(gate~))
    let other = scope.start(0, counter())
    waiting.send(Increment)
    other.send(Increment)
    assert_eq(other.ask(reply => Read(reply)), 1)
    gate.put(())
    assert_eq(waiting.ask(reply => Read(reply)), 1)
  })
}

///|
async test "Finite actor: join gives the total and the actor accepts no more" {
  @actors.scope(scope => {
    let actor = scope.spawn(_ => {
      @actors.receive()
      .zip_with(@actors.receive(), (a, b) => a + b)
      .zip_with(@actors.receive(), (ab, c) => ab + c)
    })
    for value in [1, 2, 3] {
      actor.send(value)
    }
    assert_eq(actor.join(), 6)
    assert_eq(actor.try_send(4), Closed)
  })
}

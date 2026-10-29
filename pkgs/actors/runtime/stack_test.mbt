///|
/// The number of steps of the stack tests.
const STEPS : Int = 100000

///|
/// A loop that carries its state forward: each step binds the next one.
fn sum_forward(left : Int, total : Int) -> @actors.Receive[Int, Int] {
  if left == 0 {
    @actors.done(total)
  } else {
    @actors.receive().bind(value => sum_forward(left - 1, total + value))
  }
}

///|
/// A loop that builds its result after the recursive step.
fn sum_back(left : Int) -> @actors.Receive[Int, Int] {
  if left == 0 {
    @actors.done(0)
  } else {
    @actors.receive().bind(value => sum_back(left - 1).map(rest => rest + value))
  }
}

///|
fn ones() -> Array[Int] {
  Array::make(STEPS, 1)
}

///|
async test "RECV-1: a 100,000-step loop that carries its state runs in the test runner" {
  assert_eq(sum_forward(STEPS, 0) |> @actors.run_messages(ones()), Some(STEPS))
}

///|
async test "RECV-1: a 100,000-step loop that builds its result on the way back runs in the test runner" {
  assert_eq(sum_back(STEPS) |> @actors.run_messages(ones()), Some(STEPS))
}

///|
async test "RECV-1: 100,000 joined receives in one chain run without stack growth" {
  let mut chain : @actors.Receive[Int, Int] = @actors.done(0)
  for _ in 0..<STEPS {
    chain = chain.zip_with(@actors.receive(), (total, value) => total + value)
  }
  assert_eq(chain |> @actors.run_messages(ones()), Some(STEPS))
}

///|
async test "RECV-1: 100,000 nested recover frames that end normally leave no frame" {
  let mut chain : @actors.Receive[Int, Int] = @actors.done(0)
  for _ in 0..<STEPS {
    chain = chain
      .zip_with(@actors.receive(), (total, value) => total + value)
      .recover(_ => @actors.done(-1))
  }
  assert_eq(chain |> @actors.run_messages(ones()), Some(STEPS))
}

///|
/// Send `STEPS` ones to `actor` and give its result.
async fn run_live(make : () -> @actors.Receive[Int, Int]) -> Int {
  @actors.scope(scope => {
    let actor = scope.spawn(_ => make())
    for _ in 0..<STEPS {
      actor.send(1)
    }
    actor.join()
  })
}

///|
async test "RECV-1: a live actor runs a 100,000-step loop that carries its state" {
  assert_eq(run_live(() => sum_forward(STEPS, 0)), STEPS)
}

///|
async test "RECV-1: a live actor runs a 100,000-step loop that builds its result on the way back" {
  assert_eq(run_live(() => sum_back(STEPS)), STEPS)
}

///|
async test "RECV-1: a live receive_loop takes 100,000 messages" {
  let total = @actors.scope(scope => {
    let ack : @aio.Queue[Int] = @aio.Queue(kind=Unbounded)
    let actor = scope.start(0, (total, value : Int?) => {
      match value {
        Some(value) => Continue(total + value)
        None => {
          ack.put(total)
          Stop
        }
      }
    })
    for _ in 0..<STEPS {
      actor.send(Some(1))
    }
    actor.send(None)
    ack.get()
  })
  assert_eq(total, STEPS)
}

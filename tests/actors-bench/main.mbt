///|
/// Local benchmark of the receive shapes of the add-typed-actors design
/// (RECV-1). Run it only through `mise run bench:actors`. It is not a test, and
/// `mise run check`, CI and the release workflow never run it.
///
/// The pinned compiler rejects async benchmarks in `moon bench` ("async
/// benchmark is currently not supported"), so this program times each shape
/// with the monotonic clock of `moonbitlang/core/bench` and prints nanoseconds
/// for each message. Use the numbers for ratios only.

///|
/// The number of messages of each shape.
const MESSAGES : Int = 200000

///|
/// The number of scheduler round trips of the last shape.
const PAUSES : Int = 1000

///|
/// The number of rounds of each shape. The report gives the fastest round.
const ROUNDS : Int = 5

///|
/// A loop that carries its state forward with `bind`.
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
/// Run `shape` `ROUNDS` times and print the fastest round in nanoseconds for
/// each message.
async fn measure(
  name : String,
  shape : async () -> Int,
  count? : Int = MESSAGES,
) -> Unit {
  let mut best = 0.0
  for round in 0..<ROUNDS {
    let start = @bench.monotonic_clock_start()
    let result = shape()
    let elapsed = @bench.monotonic_clock_end(start)
    guard result == count else {
      abort("\{name} gave \{result}, expected \{count}")
    }
    if round == 0 || elapsed < best {
      best = elapsed
    }
  }
  // The clock gives microseconds.
  let nanoseconds = best * 1000.0 / count.to_double()
  println("\{name}: \{nanoseconds.to_int()} ns/message")
}

///|
async fn main {
  let messages = Array::make(MESSAGES, 1)
  let handler : async (Int, Int) -> @actors.Next[Int] = (total, value) => {
    @actors.Continue(total + value)
  }
  measure("plain async handler call", () => {
    let mut total = 0
    for value in messages {
      guard handler(total, value) is Continue(next) else { break }
      total = next
    }
    total
  })
  measure("receive_loop as one repeat node", () => {
    let summing = @actors.receive_loop(0, handler)
    @actors.run_test(summing, messages, at_end=Close).result().unwrap_or(-1)
  })
  measure("start actor end to end", () => {
    @actors.scope(scope => {
      let replies : @aio.Queue[Int] = @aio.Queue(kind=Unbounded)
      let actor = scope.start(0, mailbox=Unbounded, (total, value : Int?) => {
        match value {
          Some(value) => Continue(total + value)
          None => {
            replies.put(total)
            Stop
          }
        }
      })
      for value in messages {
        actor.send(Some(value))
      }
      actor.send(None)
      replies.get()
    })
  })
  measure("state loop written with bind", () => {
    sum_forward(MESSAGES, 0) |> @actors.run_messages(messages) |> Option::unwrap
  })
  measure("loop that builds its result on the way back", () => {
    sum_back(MESSAGES) |> @actors.run_messages(messages) |> Option::unwrap
  })
  // A round trip is slow, above all on js, so this shape takes fewer rounds.
  measure("one scheduler round trip (@aio.pause)", count=PAUSES, () => {
    for _ in 0..<PAUSES {
      @aio.pause()
    }
    PAUSES
  })
}

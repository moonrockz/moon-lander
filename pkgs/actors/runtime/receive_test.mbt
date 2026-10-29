///|
/// The login protocol of the design (RECV-1, TEST-1).
enum Login {
  Hello(String)
  Credentials(Int)
  Noise(String)
} derive(Eq, Debug)

///|
fn hello(message : Login) -> String? {
  match message {
    Hello(name) => Some(name)
    _ => None
  }
}

///|
fn credentials(message : Login) -> Int? {
  match message {
    Credentials(pin) => Some(pin)
    _ => None
  }
}

///|
fn limit(milliseconds : Int) -> @lander_core.TimeLimit {
  @lander_core.TimeLimit::millis(milliseconds) catch {
    _ => panic()
  }
}

///|
/// The design's login receive: the first Hello, then the first Credentials.
fn login() -> @actors.Receive[Login, String] {
  @actors.select(hello)
  .zip_with(@actors.select(credentials), (name, pin) => "\{name}:\{pin}")
  .within(limit(5000), on_timeout=() => @actors.done("timed out"))
}

///|
async test "TEST-1: the login receive joins Hello and Credentials and keeps the noise" {
  let messages = [Noise("x"), Credentials(7), Hello("ann"), Noise("y")]
  assert_eq(login() |> @actors.run_messages(messages), Some("ann:7"))
  let run = @actors.run_test(login(), messages)
  assert_eq(run.result(), Some("ann:7"))
  assert_eq(run.remaining(), [Noise("x"), Noise("y")])
}

///|
async test "TEST-1: a receive that waits gives no result, and the messages stay" {
  let run = @actors.run_test(login(), [Noise("x"), Hello("ann")])
  assert_true(run.outcome() is Waiting)
  assert_eq(run.remaining(), [Noise("x")])
}

///|
async test "TEST-1: an expired time limit continues with its timeout receive" {
  let run = @actors.run_test(login(), [Hello("ann")], at_end=Expire)
  assert_eq(run.result(), Some("timed out"))
  assert_eq(run.remaining(), [])
}

///|
async test "RECV-1: receive takes messages in admission order" {
  let three = @actors.receive()
    .zip(@actors.receive())
    .zip_with(@actors.receive(), (pair, last) => [pair.0, pair.1, last])
  assert_eq(three |> @actors.run_messages(["A", "B", "C"]), Some(["A", "B", "C"]))
}

///|
async test "RECV-1: a select skips an earlier message, and later receives keep the order" {
  let receive = @actors.select(message => if message == "B" { Some(1) } else { None })
    .zip(@actors.receive())
    .zip_with(@actors.receive(), (pair, last) => (pair.0, pair.1, last))
  assert_eq(receive |> @actors.run_messages(["A", "B", "C"]), Some((1, "A", "C")))
}

///|
async test "RECV-1: done, map and then give results without a message" {
  let receive : @actors.Receive[String, Int] = @actors.done(20).map(value => {
    value + 1
  })
  assert_eq(receive |> @actors.run_messages([]), Some(21))
  let then = @actors.receive().then(@actors.done(7))
  assert_eq(then |> @actors.run_messages(["drop"]), Some(7))
}

///|
async test "RECV-1: bind does async work between two receives" {
  let receive = @actors.receive().bind(first => {
    @aio.pause()
    @actors.receive().map(second => first + second)
  })
  assert_eq(receive |> @actors.run_messages([1, 2, 3]), Some(3))
}

///|
async test "RECV-1: a state loop adds values until a stop message" {
  let sum = @actors.receive_loop(0, (total, message : Int?) => {
    match message {
      Some(value) => @actors.Continue(total + value)
      None => @actors.Stop
    }
  })
  let run = @actors.run_test(sum, [Some(1), Some(2), Some(3), None, Some(9)])
  assert_eq(run.result(), Some(6))
  assert_eq(run.remaining(), [Some(9)])
}

///|
async test "RECV-1: a state loop ends with its state when the mailbox closes" {
  let sum = @actors.receive_loop(0, (total, value : Int) => {
    @actors.Continue(total + value)
  })
  assert_eq(@actors.run_test(sum, [1, 2], at_end=Close).result(), Some(3))
}

///|
async test "RECV-1: receive_all handles every message until close" {
  let seen = []
  let all = @actors.receive_all((message : String) => seen.push(message))
  assert_eq(@actors.run_test(all, ["a", "b"], at_end=Close).result(), Some(()))
  assert_eq(seen, ["a", "b"])
}

///|
async test "RECV-1: receive_n stops after the count or at close" {
  let seen = []
  let two = @actors.MessageCount::from_int(2)
  let run = @actors.run_test(
    @actors.receive_n(two, (message : String) => seen.push(message)),
    ["a", "b", "c"],
  )
  assert_eq(run.result(), Some(()))
  assert_eq(run.remaining(), ["c"])
  let early = @actors.run_test(
    @actors.receive_n(two, (message : String) => seen.push(message)),
    ["d"],
    at_end=Close,
  )
  assert_eq(early.result(), Some(()))
  assert_eq(seen, ["a", "b", "d"])
}

///|
async test "RECV-1: poll continues with on_empty on an empty open mailbox" {
  let polled = @actors.poll(on_empty=() => @actors.done("empty"))
  assert_eq(polled |> @actors.run_messages([]), Some("empty"))
  assert_eq(polled |> @actors.run_messages(["first"]), Some("first"))
}

///|
async test "RECV-1: poll on a closed empty mailbox continues as closed" {
  let polled = @actors.poll(on_empty=() => @actors.done("empty")).on_closed(() => {
    @actors.done("closed")
  })
  assert_eq(@actors.run_test(polled, [], at_end=Close).result(), Some("closed"))
  let bare = @actors.poll(on_empty=() => @actors.done("empty"))
  assert_true(@actors.run_test(bare, [], at_end=Close).outcome() is MailboxClosed)
}

///|
async test "RECV-1: on_closed continues a waiting receive after close" {
  let receive = @actors.receive().on_closed(() => @actors.done("closed"))
  let run = @actors.run_test(receive, [], at_end=Close)
  assert_eq(run.result(), Some("closed"))
  assert_eq(
    @actors.run_test(receive, ["message"], at_end=Close).result(),
    Some("message"),
  )
}

///|
async test "RECV-1: within leaves the queued messages when it expires" {
  let receive = @actors.select(hello).within(limit(10), on_timeout=() => {
    @actors.done("timed out")
  })
  let run = @actors.run_test(receive, [Noise("a"), Noise("b")], at_end=Expire)
  assert_eq(run.result(), Some("timed out"))
  assert_eq(run.remaining(), [Noise("a"), Noise("b")])
}

///|
async test "RECV-1: the shorter of two nested time limits expires first" {
  let inner = @actors.receive().within(limit(10), on_timeout=() => {
    @actors.done("inner")
  })
  let outer = inner.within(limit(20), on_timeout=() => @actors.done("outer"))
  assert_eq(@actors.run_test(outer, [], at_end=Expire).result(), Some("inner"))
  let short_outer = inner.within(limit(5), on_timeout=() => {
    @actors.done("outer")
  })
  assert_eq(
    @actors.run_test(short_outer, [], at_end=Expire).result(),
    Some("outer"),
  )
}

///|
suberror Unreadable {
  Unreadable(String)
} derive(Debug)

///|
async test "RECV-1: recover continues after a step error" {
  let failing = @actors.receive().bind(message => {
    @aio.pause()
    raise Unreadable(message)
  })
  let recovered = failing.recover(error => {
    match error {
      Unreadable(text) => @actors.receive().map(next => "\{text} then \{next}")
      _ => @actors.done("other")
    }
  })
  assert_eq(recovered |> @actors.run_messages(["a", "b"]), Some("a then b"))
}

///|
async test "RECV-1: a selector error leaves the message and reaches recover" {
  let picky = @actors.select(message => {
    if message == "bad" {
      raise Unreadable(message)
    }
    None
  })
  let recovered : @actors.Receive[String, String] = picky.recover(_ => {
    @actors.receive()
  })
  let run = @actors.run_test(recovered, ["bad", "next"])
  assert_eq(run.result(), Some("bad"))
  assert_eq(run.remaining(), ["next"])
}

///|
async test "RECV-1: an error without recover is raised by the test runner" {
  let failing : @actors.Receive[String, Unit] = @actors.receive().bind(message => {
    raise Unreadable(message)
  })
  let outcome = try {
    ignore(@actors.run_test(failing, ["x"]))
    "finished"
  } catch {
    Unreadable(text) => "raised \{text}"
    _ => "other"
  }
  assert_eq(outcome, "raised x")
}

///|
async test "RECV-1: a recover frame ends with its receive" {
  // An error after the recovering receive is not caught by it.
  let first = @actors.receive().recover(_ => @actors.done("recovered"))
  let receive : @actors.Receive[String, String] = first.bind(message => {
    raise Unreadable(message)
  })
  let outcome = try {
    ignore(receive |> @actors.run_messages(["a"]))
    "finished"
  } catch {
    Unreadable(text) => "raised \{text}"
    _ => "other"
  }
  assert_eq(outcome, "raised a")
}

///|
async test "RECV-1: a loop handler error leaves the loop for recover" {
  let summing = @actors.receive_loop(0, (total, value : Int) => {
    if value < 0 {
      raise Unreadable("negative")
    }
    @actors.Continue(total + value)
  })
  let recovered = summing.recover(_ => @actors.receive().map(next => next * 100))
  let run = @actors.run_test(recovered, [1, -1, 2, 3])
  assert_eq(run.result(), Some(200))
  assert_eq(run.remaining(), [3])
}

///|
async test "RECV-1: one receive value runs more than once" {
  let pair = @actors.receive().zip(@actors.receive())
  let sum = @actors.receive_loop(0, (total, value : Int) => {
    @actors.Continue(total + value)
  })
  assert_eq(pair |> @actors.run_messages([1, 2]), Some((1, 2)))
  assert_eq(pair |> @actors.run_messages([3, 4]), Some((3, 4)))
  assert_eq(@actors.run_test(sum, [1], at_end=Close).result(), Some(1))
  assert_eq(@actors.run_test(sum, [5], at_end=Close).result(), Some(5))
}

///|
async test "RECV-1: the test runner counts waits against limits in order" {
  // The inner limit expires after 10 of the outer 12; the next limit of 5
  // then outlasts the 2 that remain of the outer one.
  let first = @actors.receive().within(limit(10), on_timeout=() => {
    @actors.receive().within(limit(5), on_timeout=() => @actors.done("A"))
  })
  let outer = first.within(limit(12), on_timeout=() => @actors.done("B"))
  assert_eq(@actors.run_test(outer, [], at_end=Expire).result(), Some("B"))
}

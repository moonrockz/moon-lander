///|
/// The next event of `probe`, as a short label with the payload, if any.
async fn next_label(probe : @aio.Queue[@actors.ActorEvent]) -> String {
  label_with_payload(probe.get())
}

///|
fn label_with_payload(event : @actors.ActorEvent) -> String {
  match event {
    Undelivered(_, _, payload~) =>
      match payload {
        Some(value) => "\{label_event(event)} \{describe_payload(value)}"
        None => "\{label_event(event)} -"
      }
    _ => label_event(event)
  }
}

///|
/// A compact text for the Ion payloads of these tests.
fn describe_payload(value : @ion.Ion) -> String {
  match value.kind() {
    Int(number) => number.to_string()
    String(text) => text
    List(items) => "[\{items.map(describe_payload).join(",")}]"
    Struct(fields) => "{\{fields.map(describe_field).join(",")}}"
    _ => "?"
  }
}

///|
fn describe_field(field : @ion.Field) -> String {
  let name = field.name().text().unwrap_or("?")
  "\{name}:\{describe_payload(field.value())}"
}

///|
/// The policy of the tests: each message is an Ion integer.
fn int_payload() -> @actors.PayloadPolicy[Int] {
  @actors.PayloadPolicy::encode(message => @ion.Ion::int(message))
}

///|
/// A capacity-one actor that holds its first message until `gate` opens.
fn blocked_actor(
  scope : @actors.Scope,
  ready : @aio.Queue[Unit],
  gate : @aio.Queue[Unit],
) -> @actors.Actor[Int, Unit] raise {
  scope.start(
    (),
    mailbox=Bounded(@actors.MailboxCapacity::from_int(1)),
    payload=int_payload(),
    (_, _ : Int) => {
      ready.put(())
      gate.get()
      Continue(())
    },
  )
}

///|
async test "UND: try_send to a full mailbox publishes Full with the target address" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  let ready : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let actor = blocked_actor(scope, ready, gate)
    let address = actor.address().to_string()
    assert_eq(next_label(probe), "started \{address}")
    actor.send(1)
    ready.get()
    assert_eq(actor.try_send(2), Accepted)
    assert_eq(actor.try_send(3), Full)
    assert_eq(next_label(probe), "undelivered \{address} full 3")
    assert_eq(actor.to_ref().try_send(4), Full)
    assert_eq(next_label(probe), "undelivered \{address} full 4")
    gate.put(())
    gate.put(())
    actor.cancel()
  })
}

///|
async test "UND: reenqueue to a full mailbox publishes Full" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  let ready : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let results : @aio.Queue[@actors.Admission] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let actor = scope.spawn(
      (context : @actors.ActorContext[Int]) => {
        @actors.receive_all(message => {
          if message == 1 {
            ready.put(())
            gate.get()
            results.put(context.reenqueue(99))
          }
        })
      },
      mailbox=Bounded(@actors.MailboxCapacity::from_int(1)),
      payload=int_payload(),
    )
    let address = actor.address().to_string()
    assert_eq(next_label(probe), "started \{address}")
    actor.send(1)
    ready.get()
    assert_eq(actor.try_send(2), Accepted)
    gate.put(())
    assert_eq(results.get(), Full)
    assert_eq(next_label(probe), "undelivered \{address} full 99")
    actor.cancel()
  })
}

///|
async test "UND: send and try_send to a closing or ended actor publish Closed" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  let ready : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let actor = blocked_actor(scope, ready, gate)
    let address = actor.address().to_string()
    assert_eq(next_label(probe), "started \{address}")
    actor.send(1)
    ready.get()
    // Closing: the actor still processes message 1.
    assert_true(actor.close() is Some(_))
    assert_true(actor.status() is Closing)
    assert_eq(actor.try_send(2), Closed)
    assert_eq(next_label(probe), "undelivered \{address} closed 2")
    let sent = try {
      actor.send(3)
      "admitted"
    } catch {
      Closed(_) => "closed"
      _ => "other"
    }
    assert_eq(sent, "closed")
    assert_eq(next_label(probe), "undelivered \{address} closed 3")
    gate.put(())
    assert_eq(next_label(probe), "ended \{address} completed")
    // Ended: only Closed events follow.
    assert_eq(actor.try_send(4), Closed)
    assert_eq(next_label(probe), "undelivered \{address} closed 4")
  })
}

///|
async test "UND: cancellation discards two queued messages in queue order before Ended" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  let ready : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let actor = scope.start(
      (),
      payload=int_payload(),
      (_, _ : Int) => {
        ready.put(())
        gate.get()
        Continue(())
      },
    )
    let address = actor.address().to_string()
    actor.send(1)
    ready.get()
    actor.send(2)
    actor.send(3)
    actor.cancel()
    assert_eq(next_label(probe), "started \{address}")
    assert_eq(next_label(probe), "undelivered \{address} discarded 2")
    assert_eq(next_label(probe), "undelivered \{address} discarded 3")
    assert_eq(next_label(probe), "ended \{address} cancelled")
    assert_true(probe.try_get() is None)
  })
}

///|
async test "UND: stop and failure discard queued messages before Ended" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let stopping = scope.start(
      (),
      payload=int_payload(),
      (_, _ : Int) => {
        gate.get()
        Stop
      },
    )
    let address = stopping.address().to_string()
    assert_eq(next_label(probe), "started \{address}")
    assert_eq(stopping.try_send(1), Accepted)
    assert_eq(stopping.try_send(2), Accepted)
    assert_eq(stopping.try_send(3), Accepted)
    gate.put(())
    stopping.join()
    assert_eq(next_label(probe), "undelivered \{address} discarded 2")
    assert_eq(next_label(probe), "undelivered \{address} discarded 3")
    assert_eq(next_label(probe), "ended \{address} completed")
  })
  let failed = try {
    @actors.scope(events~, scope => {
      ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
      let failing = scope.start(
        (),
        payload=int_payload(),
        (_, _ : Int) => {
          gate.get()
          raise Broken("boom")
        },
      )
      let address = failing.address().to_string()
      assert_eq(next_label(probe), "started \{address}")
      assert_eq(failing.try_send(1), Accepted)
      assert_eq(failing.try_send(2), Accepted)
      gate.put(())
      failing.join()
    })
    "joined"
  } catch {
    Broken(text) => text
    _ => "other"
  }
  assert_eq(failed, "boom")
  assert_true(next_label(probe).has_suffix(" discarded 2"))
  assert_true(next_label(probe).has_suffix(" failed"))
}

///|
async test "UND: close returns pending messages and publishes no event for them" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  let ready : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let actor = scope.start(
      (),
      payload=int_payload(),
      (_, _ : Int) => {
        ready.put(())
        gate.get()
        Continue(())
      },
    )
    let address = actor.address().to_string()
    actor.send(1)
    ready.get()
    actor.send(2)
    actor.send(3)
    guard actor.close() is Some(pending) else { fail("missing pending snapshot") }
    assert_eq(pending.messages(), [2, 3])
    gate.put(())
    actor.join()
    assert_eq(next_label(probe), "started \{address}")
    assert_eq(next_label(probe), "ended \{address} completed")
    assert_true(probe.try_get() is None)
  })
}

///|
async test "ORD: Started comes first for an actor closed at once, then Closed, then Ended" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let actor = scope.start(0, (count, _ : Int) => Continue(count + 1), payload=@actors.PayloadPolicy::json())
    let address = actor.address().to_string()
    ignore(actor.close())
    assert_eq(actor.to_ref().try_send(7), Closed)
    assert_eq(next_label(probe), "started \{address}")
    assert_eq(next_label(probe), "undelivered \{address} closed 7")
    assert_eq(next_label(probe), "ended \{address} completed")
  })
}

///|
async test "ORD: after Ended only Closed events follow for the actor" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let actor = scope.start((), (_, _ : Int) => Stop, payload=int_payload())
    let address = actor.address().to_string()
    actor.send(0)
    actor.join()
    assert_eq(next_label(probe), "started \{address}")
    assert_eq(next_label(probe), "ended \{address} completed")
    assert_eq(actor.try_send(1), Closed)
    let sent = try {
      actor.send(2)
      "admitted"
    } catch {
      Closed(_) => "closed"
      _ => "other"
    }
    assert_eq(sent, "closed")
    assert_eq(next_label(probe), "undelivered \{address} closed 1")
    assert_eq(next_label(probe), "undelivered \{address} closed 2")
    assert_true(probe.try_get() is None)
  })
}

///|
async test "PAY: the default policy omits the payload" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let actor = scope.start((), (_, _ : Int) => Stop)
    let address = actor.address().to_string()
    actor.send(0)
    actor.join()
    assert_eq(actor.try_send(5), Closed)
    assert_eq(next_label(probe), "started \{address}")
    assert_eq(next_label(probe), "ended \{address} completed")
    assert_eq(next_label(probe), "undelivered \{address} closed -")
  })
}

///|
enum Reading {
  Reading(@ion.Decimal, @ion.Timestamp)
}

///|
impl @ion.ToIon for Reading with to_ion(self) {
  let Reading(amount, time) = self
  @ion.Ion::list([@ion.Ion::decimal(amount), @ion.Ion::timestamp(time)])
}

///|
async test "PAY: the Ion policy keeps a decimal and a timestamp" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  let amount = @ion.Decimal::parse("12.340")
  let time = @ion.Timestamp::parse("2026-10-31T12:34:56.789Z")
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let actor = scope.start(
      (),
      (_, _ : Reading) => Stop,
      payload=@actors.PayloadPolicy::ion(),
    )
    ignore(actor.close())
    assert_eq(actor.try_send(Reading(amount, time)), Closed)
    ignore(probe.get())
    guard probe.get() is Undelivered(_, Closed, payload=Some(payload)) else {
      fail("expected a Closed event with a payload")
    }
    guard payload.kind() is List([first, second]) else { fail("not a list") }
    guard first.kind() is Decimal(decimal) else { fail("lost the decimal") }
    assert_eq(decimal.to_ion_string(), amount.to_ion_string())
    guard second.kind() is Timestamp(stamp) else { fail("lost the timestamp") }
    assert_eq(stamp.to_ion_string(), time.to_ion_string())
  })
}

///|
enum PaidCounter {
  Add(Int)
} derive(ToJson)

///|
async test "PAY: the JSON policy gives the Ion form of the JSON value" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let actor = scope.start(
      0,
      (count, message : PaidCounter) => {
        let Add(by) = message
        Continue(count + by)
      },
      payload=@actors.PayloadPolicy::json(),
    )
    ignore(actor.close())
    assert_eq(actor.try_send(Add(3)), Closed)
    ignore(probe.get())
    guard probe.get() is Undelivered(_, Closed, payload=Some(payload)) else {
      fail("expected a Closed event with a payload")
    }
    assert_true(payload.equals(@ion.Ion(ToJson::to_json(PaidCounter::Add(3)))))
  })
}

///|
enum Credential {
  Token(String, String)
}

///|
async test "PAY: a custom encoder redacts a secret" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let actor = scope.start_with(
      _ => (),
      (_, message : Credential) => {
        let Token(_, secret) = message
        ignore(secret)
        Stop
      },
      payload=@actors.PayloadPolicy::encode(message => {
        let Token(user, _) = message
        @ion.Ion::from_fields([
          @ion.Field("user", @ion.Ion::string(user)),
          @ion.Field("secret", @ion.Ion::string("[redacted]")),
        ])
      }),
    )
    ignore(actor.close())
    assert_eq(actor.try_send(Token("reader", "do-not-log")), Closed)
    assert_true(next_label(probe).has_prefix("started "))
    let label = next_label(probe)
    assert_true(label.has_suffix(" closed {user:reader,secret:[redacted]}"))
    assert_false(label.contains("do-not-log"))
  })
}

///|
// A wrong payload policy does not compile: `PayloadPolicy::ion()` needs
// `ToIon` and `PayloadPolicy::json()` needs `ToJson`, so
// `scope.start((), handler, payload=@actors.PayloadPolicy::ion())` for a
// protocol without `ToIon` is a type error. `create` has no `payload`
// argument, so a service closure never has a payload.
async test "PAY: service closures have no payload; respond encodes the request" {
  let events = @actors.RuntimeEvents::new()
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let service = scope.create(Ref(0))
    let service_address = service.address().to_string()
    assert_eq(next_label(probe), "started \{service_address}")
    service.close()
    let told = try {
      service.tell(counter => counter.val += 1)
      "admitted"
    } catch {
      Closed(_) => "closed"
      _ => "other"
    }
    assert_eq(told, "closed")
    assert_eq(next_label(probe), "undelivered \{service_address} closed -")
    assert_eq(next_label(probe), "ended \{service_address} completed")
    let responder = scope.respond(
      (request : Int) => request * 2,
      payload=int_payload(),
    )
    let responder_address = responder.address().to_string()
    assert_eq(next_label(probe), "started \{responder_address}")
    responder.close()
    let asked = try {
      ignore(responder.ask(21))
      "answered"
    } catch {
      @actors.ActorError::Closed(_) => "closed"
      _ => "other"
    }
    assert_eq(asked, "closed")
    // The ask waits inside its time limit, so the actor can end first.
    let later = [next_label(probe), next_label(probe)]
    assert_true(later.contains("undelivered \{responder_address} closed 21"))
    assert_true(later.contains("ended \{responder_address} completed"))
  })
}

///|
async test "COST: no subscriber means the encoder is never called" {
  let calls = Ref(0)
  let counting : @actors.PayloadPolicy[Int] = @actors.PayloadPolicy::encode(message => {
    calls.val += 1
    @ion.Ion::int(message)
  })
  let events = @actors.RuntimeEvents::new()
  @actors.scope(events~, scope => {
    let actor = scope.start((), (_, _ : Int) => Stop, payload=counting)
    ignore(actor.close())
    for index in 0..<10 {
      assert_eq(actor.try_send(index), Closed)
    }
  })
  assert_eq(calls.val, 0)
  // A scope without a channel never encodes either.
  @actors.scope(scope => {
    let actor = scope.start((), (_, _ : Int) => Stop, payload=counting)
    actor.send(0)
    actor.join()
    for index in 0..<10 {
      assert_eq(actor.try_send(index), Closed)
    }
  })
  assert_eq(calls.val, 0)
  // With a subscriber, only undelivered messages are encoded, once each.
  let probe : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    ignore(events.subscribe(scope, @actors.Subject::from_queue(probe)))
    let actor = scope.start((), (_, _ : Int) => Stop, payload=counting)
    actor.send(0)
    actor.join()
    assert_eq(actor.try_send(1), Closed)
  })
  assert_eq(calls.val, 1)
}

///|
async test "COST: each subscriber gets an independent payload" {
  let events = @actors.RuntimeEvents::new()
  let second : @aio.Queue[@actors.ActorEvent] = @aio.Queue(kind=Unbounded)
  let policy : @actors.PayloadPolicy[Int] = @actors.PayloadPolicy::encode(message => {
    @ion.Ion::from_fields([
      @ion.Field("items", @ion.Ion::list([@ion.Ion::int(message)])),
    ]).with_annotations([@ion.SymbolToken("sample")])
  })
  // The first subscriber changes its payload while the runtime delivers.
  let mutate : @actors.Subject[@actors.ActorEvent] = @actors.Subject::new(
    send=_ => Admitted,
    try_send=event => {
      if event is Undelivered(_, _, payload=Some(payload)) {
        payload.annotations().push(@ion.SymbolToken("changed"))
        if payload.kind() is Struct(fields) && fields[0].value().kind() is List(items) {
          items.push(@ion.Ion::int(99))
        }
      }
      Accepted
    },
  )
  @actors.scope(events~, scope => {
    ignore(events.subscribe(scope, mutate))
    ignore(events.subscribe(scope, @actors.Subject::from_queue(second)))
    let actor = scope.start((), (_, _ : Int) => Stop, payload=policy)
    ignore(actor.close())
    assert_eq(actor.try_send(1), Closed)
    ignore(second.get())
    guard second.get() is Undelivered(_, Closed, payload=Some(payload)) else {
      fail("expected a Closed event with a payload")
    }
    assert_eq(payload.annotations().length(), 1)
    assert_eq(describe_payload(payload), "{items:[1]}")
  })
}

///|
/// The protocol of a dead-letter counter: it observes runtime events and
/// answers how many undelivered messages it saw for each reason.
enum DeadLetters {
  Observe(@actors.ActorEvent)
  Totals(@actors.Reply[(Int, Int, Int)])
}

///|
/// Counts of `Full`, `Closed` and `Discarded` events, in that order.
fn count_dead_letters(
  totals : (Int, Int, Int),
  message : DeadLetters,
) -> @actors.Next[(Int, Int, Int)] {
  let (full, closed, discarded) = totals
  match message {
    Observe(Undelivered(_, Full, ..)) => Continue((full + 1, closed, discarded))
    Observe(Undelivered(_, Closed, ..)) =>
      Continue((full, closed + 1, discarded))
    Observe(Undelivered(_, Discarded, ..)) =>
      Continue((full, closed, discarded + 1))
    Observe(_) => Continue(totals)
    Totals(reply) => {
      ignore(reply.send(totals))
      Continue(totals)
    }
  }
}

///|
async test "Dead-letter counter: an actor counts undelivered messages by reason" {
  let events = @actors.RuntimeEvents::new()
  let ready : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let totals = @actors.scope(events~, scope => {
    // An unbounded mailbox, so the counter never drops an event.
    let counter = scope.start((0, 0, 0), mailbox=Unbounded, (totals, message) => {
      count_dead_letters(totals, message)
    })
    ignore(
      events.subscribe(
        scope,
        counter.to_ref().to_subject().contramap(event => Observe(event)),
      ),
    )
    let worker = scope.start(
      (),
      mailbox=Bounded(@actors.MailboxCapacity::from_int(1)),
      (_, _ : Int) => {
        ready.put(())
        gate.get()
        Continue(())
      },
    )
    worker.send(1)
    ready.get()
    assert_eq(worker.try_send(2), Accepted)
    // Full: the mailbox holds message 2.
    assert_eq(worker.try_send(3), Full)
    // Discarded: cancellation removes message 2.
    worker.cancel()
    // Closed: the worker no longer admits messages.
    assert_eq(worker.try_send(4), Closed)
    assert_eq(worker.try_send(5), Closed)
    counter.ask(reply => Totals(reply))
  })
  assert_eq(totals, (1, 2, 1))
}

///|
/// What a bridge writes for a payload: the JSON form when Ion converts to
/// JSON, or else the Ion text form as a string.
fn payload_property(payload : @ion.Ion) -> Json {
  @ion_json.to_json(payload) catch {
    _ => {
      let text = @ion_text.write_fragment(payload) catch { _ => "<unprintable>" }
      Json::string(text)
    }
  }
}

///|
/// Write one runtime event to `logger`. Only the application, here the
/// unpublished tests, imports both the actors runtime and logging.
fn log_event(logger : &@logging.Logger, event : @actors.ActorEvent) -> Unit {
  match event {
    Started(address) =>
      logger.debug("Actor {Actor} started", [Json::string(address.to_string())])
    Ended(address, end) => {
      let ending = match end {
        Completed => "completed"
        MailboxClosed => "mailbox closed"
        Failed(_) => "failed"
        Cancelled => "cancelled"
      }
      logger.info("Actor {Actor} ended: {End}", [
        Json::string(address.to_string()),
        Json::string(ending),
      ])
    }
    Undelivered(address, reason, payload~) => {
      let why = match reason {
        Full => "full"
        Closed => "closed"
        Discarded => "discarded"
      }
      match payload {
        Some(payload) =>
          logger.warn("Undelivered message to {Actor}: {Reason} {Payload}", [
            Json::string(address.to_string()),
            Json::string(why),
            payload_property(payload),
          ])
        None =>
          logger.warn("Undelivered message to {Actor}: {Reason}", [
            Json::string(address.to_string()),
            Json::string(why),
          ])
      }
    }
  }
}

///|
/// The bridge protocol: an event to write, or a request to confirm that all
/// earlier events are written.
enum Bridge {
  Write(@actors.ActorEvent)
  Flush(@actors.Reply[Unit])
}

///|
enum Order {
  Place(String, Int)
} derive(ToJson)

///|
async test "Logger bridge: an actor writes runtime events to a logger" {
  let memory = @logging.MemoryLogger::new()
  let logger : &@logging.Logger = memory
  let events = @actors.RuntimeEvents::new()
  @actors.scope(events~, scope => {
    let bridge = scope.start(
      (),
      (_, message : Bridge) => {
        match message {
          Write(event) => log_event(logger, event)
          Flush(reply) => ignore(reply.send(()))
        }
        Continue(())
      },
      mailbox=Unbounded,
    )
    ignore(
      events.subscribe(
        scope,
        bridge.to_ref().to_subject().contramap(event => Write(event)),
      ),
    )
    let orders = scope.start(
      (),
      (_, _ : Order) => Continue(()),
      payload=@actors.PayloadPolicy::json(),
    )
    // A symbol known only by its ID has no JSON form, so the bridge writes
    // the Ion text form of this payload.
    let symbols = scope.start(
      (),
      (_, _ : Int) => Continue(()),
      payload=@actors.PayloadPolicy::encode(_ => {
        @ion.Ion::symbol_token(@ion.SymbolToken::from_sid(10))
      }),
    )
    ignore(orders.close())
    ignore(symbols.close())
    assert_eq(orders.try_send(Place("tea", 2)), Closed)
    assert_eq(symbols.try_send(1), Closed)
    bridge.ask(reply => Flush(reply))
    let warnings = memory.events().filter(event => event.level == Warning)
    assert_eq(warnings.length(), 2)
    assert_eq(
      warnings[0].property("Payload"),
      Some(ToJson::to_json(Place("tea", 2))),
    )
    assert_eq(warnings[0].property("Reason"), Some(Json::string("closed")))
    assert_eq(
      warnings[0].property("Actor"),
      Some(Json::string(orders.address().to_string())),
    )
    guard warnings[1].property("Payload") is Some(String(text)) else {
      fail("expected the Ion text form as a string")
    }
    assert_eq(text, "$10")
  })
}

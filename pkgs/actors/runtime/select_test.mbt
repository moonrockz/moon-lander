///|
/// A message that a selective receive can skip.
enum Item {
  Plain(String)
  Wanted(String)
}

///|
fn wanted(item : Item) -> String? {
  match item {
    Wanted(text) => Some(text)
    Plain(_) => None
  }
}

///|
fn text(item : Item) -> String {
  match item {
    Plain(text) | Wanted(text) => text
  }
}

///|
/// The next message as its text.
fn next_text() -> @actors.Receive[Item, String] {
  @actors.receive().map(text)
}

///|
async test "RECV-1: a live select takes the oldest match and keeps the others in order" {
  let log = @actors.scope(scope => {
    let actor = scope.spawn(_ => {
      @actors.select(wanted)
      .zip(next_text())
      .zip_with(next_text(), (pair, last) => [pair.0, pair.1, last])
    })
    actor.send(Plain("A"))
    actor.send(Wanted("B"))
    actor.send(Plain("C"))
    actor.join()
  })
  assert_eq(log, ["B", "A", "C"])
}

///|
async test "RECV-1: a waiting select takes a later arrival and keeps earlier ones" {
  let selecting : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = @actors.scope(scope => {
    let actor = scope.spawn(_ => {
      @actors.done(())
      .bind(_ => {
        selecting.put(())
        @actors.select(wanted)
      })
      .zip(next_text())
      .zip_with(next_text(), (pair, last) => [pair.0, pair.1, last])
    })
    selecting.get()
    actor.send(Plain("A"))
    actor.send(Plain("B"))
    while actor.queued_count() < 2 {
      @aio.pause()
    }
    actor.send(Wanted("C"))
    actor.join()
  })
  assert_eq(log, ["C", "A", "B"])
}

///|
async test "RECV-1: skipped messages fill a bounded mailbox, and a timed select keeps them" {
  let one = @actors.MailboxCapacity::from_int(1)
  let log = @actors.scope(scope => {
    let actor = scope.spawn(mailbox=Bounded(one), context => {
      @actors.select(wanted)
      .within(limit(30), on_timeout=() => @actors.done("timed out"))
      .bind(timed => {
        let queued = context.queued_count()
        next_text()
        .zip(@actors.select(wanted))
        .map(pair => [timed, "queued \{queued}", pair.0, pair.1])
      })
    })
    actor.send(Plain("A"))
    assert_eq(actor.try_send(Wanted("B")), Full)
    @aio.with_task_group(group => {
      group.spawn_bg(() => actor.send(Wanted("B")))
      actor.join()
    })
  })
  assert_eq(log, ["timed out", "queued 1", "A", "B"])
}

///|
async test "RECV-1: a timed receive on an empty mailbox expires, and a later message arrives" {
  let expired : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = @actors.scope(scope => {
    let actor = scope.spawn(_ => {
      @actors.receive()
      .map(text)
      .within(limit(10), on_timeout=() => @actors.done("timed out"))
      .bind(first => {
        expired.put(())
        next_text().map(second => [first, second])
      })
    })
    expired.get()
    actor.send(Plain("late"))
    actor.join()
  })
  assert_eq(log, ["timed out", "late"])
}

///|
async test "RECV-1: a selector error leaves the message and reaches recover" {
  let log = @actors.scope(scope => {
    let actor = scope.spawn(_ => {
      let picky = @actors.select(item => {
        if text(item) == "bad" {
          raise Unreadable("bad")
        }
        wanted(item)
      })
      picky
      .recover(error => {
        match error {
          Unreadable(reason) => @actors.done("recovered \{reason}")
          _ => @actors.done("other")
        }
      })
      .zip_with(next_text(), (first, second) => [first, second])
    })
    actor.send(Plain("bad"))
    actor.join()
  })
  assert_eq(log, ["recovered bad", "bad"])
}

///|
suberror Boom {
  Boom
} derive(Debug)

///|
async test "LIFE-1: a recovered receive keeps the owner scope live and the actor processes another message" {
  let result = @actors.scope(scope => {
    let actor = scope.spawn(_ => {
      let failing : @actors.Receive[Int, Int] = @actors.receive().bind(_ => {
        raise Boom
      })
      failing.recover(_ => @actors.receive().map(next => next * 2))
    })
    actor.send(1)
    actor.send(21)
    actor.join()
  })
  assert_eq(result, 42)
}

///|
async test "LIFE-1: an unrecovered step error fails the actor and its scope" {
  let outcome = try {
    @actors.scope(scope => {
      let actor = scope.spawn(_ => {
        let failing : @actors.Receive[Int, Int] = @actors.receive().bind(_ => {
          raise Boom
        })
        failing
      })
      actor.send(1)
      actor.join()
    })
    |> ignore
    "returned"
  } catch {
    Boom => "failed: Boom"
    _ => "other"
  }
  assert_eq(outcome, "failed: Boom")
}

///|
async test "RECV-1: work between two waits does not use the time limit" {
  let log = @actors.scope(scope => {
    let actor = scope.spawn(_ => {
      @actors.receive()
      .bind(first => {
        // Work that takes longer than the limit, between two waits.
        @aio.sleep(60)
        @actors.receive().map(second => "\{first}\{second}")
      })
      .within(limit(30), on_timeout=() => @actors.done("timed out"))
    })
    actor.send("a")
    actor.send("b")
    actor.join()
  })
  assert_eq(log, "ab")
}

///|
async test "LIFE-1: recover does not catch cancellation" {
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = []
  let actor = @actors.scope(scope => {
    let actor = scope.spawn(_ => {
      let waiting : @actors.Receive[Int, Int] = @actors.receive().bind(value => {
        started.put(())
        gate.get()
        @actors.done(value)
      })
      waiting.recover(_ => {
        log.push("caught")
        @actors.done(0)
      })
    })
    actor.send(1)
    started.get()
    // The scope exit cancels the actor while it waits in `bind`.
    actor
  })
  assert_eq(log, [])
  let joined = try {
    ignore(actor.join())
    "result"
  } catch {
    @actors.ActorCancelled(_) => "cancelled"
    _ => "other"
  }
  assert_eq(joined, "cancelled")
}

///|
/// A message that a scan can skip.
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
fn ms(count : Int) -> @lander_core.TimeLimit {
  @lander_core.TimeLimit::millis(count) catch {
    _ => panic()
  }
}

///|
async test "RECV-1: a scan takes the oldest match and keeps the others in order" {
  let log = @actors.scope(scope => {
    let actor = scope.spawn((inbox : @actors.Inbox[Item]) => {
      let log = [inbox.scan(wanted)]
      log.push(text(inbox.receive()))
      log.push(text(inbox.receive()))
      log
    })
    actor.send(Plain("A"))
    actor.send(Wanted("B"))
    actor.send(Plain("C"))
    actor.join()
  })
  assert_eq(log, ["B", "A", "C"])
}

///|
async test "RECV-1: a waiting scan selects a later arrival and keeps earlier ones" {
  let scanning : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = @actors.scope(scope => {
    let actor = scope.spawn((inbox : @actors.Inbox[Item]) => {
      scanning.put(())
      let log = [inbox.scan(wanted)]
      log.push(text(inbox.receive()))
      log.push(text(inbox.receive()))
      log
    })
    actor.send(Plain("A"))
    actor.send(Plain("B"))
    scanning.get()
    assert_eq(actor.to_ref().queued_count(), 2)
    actor.send(Wanted("C"))
    actor.join()
  })
  assert_eq(log, ["C", "A", "B"])
}

///|
async test "RECV-1: skipped messages fill a bounded mailbox and a timed scan keeps them" {
  let log = @actors.scope(scope => {
    let one = @actors.MailboxCapacity::from_int(1)
    let actor = scope.spawn(mailbox=Bounded(one), (inbox : @actors.Inbox[Item]) => {
      let log = []
      let timed = try {
        log.push(inbox.scan(wanted, timeout=ms(30)))
        "matched"
      } catch {
        @actors.TimedOut(_) => "timed out"
        _ => "other"
      }
      log.push(timed)
      log.push("queued \{inbox.queued_count()}")
      log.push(text(inbox.receive()))
      log.push(inbox.scan(wanted))
      log
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
async test "RECV-1: a cancelled scan removes nothing" {
  let log = @actors.scope(scope => {
    let actor = scope.spawn((inbox : @actors.Inbox[Item]) => {
      let scanned = @aio.with_timeout_opt(20, () => inbox.scan(wanted))
      [scanned.unwrap_or("cancelled"), text(inbox.receive()), text(inbox.receive())]
    })
    actor.send(Plain("A"))
    actor.send(Plain("B"))
    actor.join()
  })
  assert_eq(log, ["cancelled", "A", "B"])
}

///|
suberror Unreadable {
  Unreadable(String)
} derive(Debug)

///|
async test "RECV-1: a selector error leaves the message and reaches the body" {
  let log = @actors.scope(scope => {
    let actor = scope.spawn((inbox : @actors.Inbox[Item]) => {
      let log = []
      let outcome = try {
        inbox.scan(item => {
          match item {
            Plain("B") => raise Unreadable("B")
            _ => None
          }
        })
      } catch {
        Unreadable(text) => "selector failed on " + text
        _ => "other"
      }
      log.push(outcome)
      for _ in 0..<3 {
        log.push(text(inbox.receive()))
      }
      log
    })
    actor.send(Plain("A"))
    actor.send(Plain("B"))
    actor.send(Plain("C"))
    actor.join()
  })
  assert_eq(log, ["selector failed on B", "A", "B", "C"])
}

///|
async test "ACT-2: a second receiver gets an ownership error and takes nothing" {
  let checked : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let log = @actors.scope(scope => {
    let actor = scope.spawn((inbox : @actors.Inbox[Item]) => {
      let log = []
      @aio.with_task_group(group => {
        // The mailbox is empty until `checked`, so this receive waits.
        group.spawn_bg(() => log.push(text(inbox.receive())))
        @aio.pause()
        let second = try {
          ignore(inbox.receive())
          "received"
        } catch {
          @actors.NotOwner(_) => "not owner"
          _ => "other"
        }
        log.push(second)
        checked.put(())
      })
      log
    })
    checked.get()
    actor.send(Plain("A"))
    actor.join()
  })
  assert_eq(log, ["not owner", "A"])
}

///|
async test "ACT-2: an inbox used after its body ends gives an ownership error" {
  let saved : Ref[@actors.Inbox[Item]?] = Ref(None)
  let outcome = @actors.scope(scope => {
    let actor = scope.spawn((inbox : @actors.Inbox[Item]) => saved.val = Some(inbox))
    actor.join()
    try {
      ignore(saved.val.unwrap().receive())
      "received"
    } catch {
      @actors.NotOwner(_) => "not owner"
      _ => "other"
    }
  })
  assert_eq(outcome, "not owner")
}

///|
struct Store {
  mut items : Int
}

///|
suberror Denied {
  Denied
} derive(Debug)

///|
async test "Heterogeneous return types: an Int and a String from one service" {
  @actors.scope(scope => {
    let store = scope.create({ items: 2 })
    let count : Int = store.ask(s => s.items)
    let text : String = store.ask(s => "\{s.items} items")
    assert_eq((count, text), (2, "2 items"))
  })
}

///|
async test "Ask error permits later calls: the next call sees the change" {
  @actors.scope(scope => {
    let store = scope.create({ items: 2 })
    let outcome = try {
      store.ask(s => {
        s.items = 0
        raise Denied
      })
      "answered"
    } catch {
      Denied => "denied"
      _ => "other"
    }
    assert_eq(outcome, "denied")
    assert_eq(store.ask(s => s.items), 0)
  })
}

///|
async test "Tell failure reaches owner: the service ends, cleans up and fails the scope" {
  let log = []
  let never : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let outcome = try {
    @actors.scope(scope => {
      let store = scope.create({ items: 0 }, on_stop=() => log.push("cleanup"))
      store.tell(_ => raise Denied)
      never.get()
    })
    "returned"
  } catch {
    Denied => "denied"
    _ => "other"
  }
  assert_eq((outcome, log), ("denied", ["cleanup"]))
}

///|
async test "Close a service with queued calls: the queued caller wakes with closed" {
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let outcomes = @actors.scope(scope => {
    let store = scope.create({ items: 0 })
    @aio.with_task_group(group => {
      let running = group.spawn(() => {
        store.ask(s => {
          started.put(())
          gate.get()
          s.items += 1
          s.items
        })
      })
      started.get()
      let queued = group.spawn(() => {
        try {
          ignore(store.ask(s => s.items))
          "answered"
        } catch {
          @actors.Closed(_) => "closed"
          _ => "other"
        }
      })
      @aio.pause()
      store.close()
      let queued = queued.wait()
      gate.put(())
      [queued, "running \{running.wait()}"]
    })
  })
  assert_eq(outcomes, ["closed", "running 1"])
}

///|
async test "No explicit reply plumbing: a doubling responder answers 42" {
  @actors.scope(scope => {
    let doubler = scope.respond(value => value * 2)
    assert_eq(doubler.ask(21), 42)
  })
}

///|
async test "Expected rejection: an error value goes to the caller and the next request works" {
  @actors.scope(scope => {
    let checker = scope.respond((value : Int) => {
      if value < 0 {
        Err("negative")
      } else {
        Ok(value)
      }
    })
    assert_eq(checker.ask(-1), Err("negative"))
    assert_eq(checker.ask(5), Ok(5))
  })
}

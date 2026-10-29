///|
fn name(text : String) -> @actors.ActorName {
  @actors.ActorName::parse(text) catch {
    _ => panic()
  }
}

///|
/// The address of the one member that `lookup` finds, or a label for the
/// other cases.
fn found(
  directory : @actors.Directory[CounterMessage],
  key : @actors.ActorName,
) -> String {
  match directory.lookup(key) {
    Missing => "missing"
    Found(entry) => entry.address().to_string()
    Ambiguous(conflict) =>
      "ambiguous " +
      conflict.refs().map(entry => entry.address().to_string()).join(" ")
  }
}

///|
async test "NAME-1: the named counter example compiles and finds the counter" {
  @actors.scope(scope => {
    let name = @actors.ActorName::parse("counter")
    let counter = scope.start(0, handle_counter, name~)
    let counters = @actors.Directory::of(counter.to_ref())
    let found = counters.lookup(name)
    let exact = counters.resolve(counter.address()) // ActorRef[CounterMessage]?
    guard found is Found(entry) else { fail("lookup did not find counter") }
    entry.send(Increment)
    assert_eq(exact.unwrap().ask(reply => Read(reply)), 1)
    assert_eq(counters.lookup(@actors.ActorName::parse("Counter")) is Missing, true)
  })
}

///|
async test "DIR-1: the composition example compiles with Add, Sub and methods" {
  @actors.scope(scope => {
    let counter = scope.start(0, handle_counter, name=name("counter"))
    let other = scope.start(0, handle_counter)
    let extra = scope.start(0, handle_counter)
    let dir1 = @actors.Directory::of(counter.to_ref())
    let dir2 = @actors.Directory::of(other.to_ref())
    let combined = dir1 + dir2
    let extended = combined.add(extra.to_ref())
    let restricted = extended.remove(counter.to_ref())
    let difference = extended - dir2
    let singleton = extended - @actors.Directory::of(extra.to_ref())
    assert_eq(combined.size(), 2)
    assert_eq(extended.size(), 3)
    assert_true(restricted == @actors.Directory::of(other.to_ref()) + @actors.Directory::of(extra.to_ref()))
    assert_true(difference == dir1.add(extra.to_ref()))
    assert_true(singleton == combined)
    assert_eq(dir1.size(), 1)
  })
}

///|
async test "DIR-1: union and difference laws hold for overlapping members" {
  @actors.scope(scope => {
    let one = scope.start(0, handle_counter).to_ref()
    let two = scope.start(0, handle_counter).to_ref()
    let three = scope.start(0, handle_counter).to_ref()
    let empty : @actors.Directory[CounterMessage] = @actors.Directory::empty()
    let a = @actors.Directory::of(one).add(two)
    let b = @actors.Directory::of(two).add(three)
    let c = @actors.Directory::of(three).add(one)
    assert_true(empty + a == a && a + empty == a)
    assert_true((a + b) + c == a + (b + c))
    assert_true(a + b == b + a)
    assert_true(a + a == a)
    assert_true(a.add(three).add(three) == a.add(three))
    assert_true(a.remove(one).remove(one) == a.remove(one))
    assert_true(a.remove(three) == a)
    assert_true(a - empty == a && a - a == empty)
    assert_true((a + b) - c == (a - c) + (b - c))
    assert_true(a - b == @actors.Directory::of(one))
    assert_eq((a + @actors.Directory::of(two)).size(), 2)
  })
}

///|
async test "NAME-1: the same name in two scopes gives distinct addresses" {
  let worker = name("worker")
  let (first, second) = @actors.scope(outer => {
    let first = outer.start(0, handle_counter, name=worker)
    let second = @actors.scope(inner => {
      inner.start(0, handle_counter, name=worker).to_ref()
    })
    (first.to_ref(), second)
  })
  assert_true(first.address() != second.address())
  let combined = @actors.Directory::of(first) + @actors.Directory::of(second)
  let reversed = @actors.Directory::of(second) + @actors.Directory::of(first)
  assert_true(combined == reversed)
  guard combined.lookup(worker) is Ambiguous(conflict) else {
    fail("worker is not ambiguous")
  }
  assert_eq(conflict.refs().length(), 2)
  assert_eq(combined.resolve(first.address()).unwrap().address(), first.address())
  assert_eq(combined.resolve(second.address()).unwrap().address(), second.address())
  assert_eq(found(combined.remove(second), worker), first.address().to_string())
  assert_true((combined + @actors.Directory::of(first)).lookup(worker) is Ambiguous(_))
}

///|
async test "NAME-1: a replacement reuses the name with a new address" {
  @actors.scope(scope => {
    let counter = name("counter")
    let old = scope.start(0, handle_counter, name=counter)
    let in_use = try {
      ignore(scope.start(0, handle_counter, name=counter))
      "started"
    } catch {
      @actors.NameInUse(_) => "name in use"
      _ => "other"
    }
    assert_eq(in_use, "name in use")
    let old_dir = @actors.Directory::of(old.to_ref())
    let without = old_dir.remove(old.to_ref())
    assert_eq(old.to_ref().queued_count(), 0)
    old.send(Halt)
    old.join()
    let replacement = scope.start(10, handle_counter, name=counter)
    assert_true(replacement.address() != old.address())
    let new_dir = without.add(replacement.to_ref())
    assert_eq(found(old_dir, counter), old.address().to_string())
    assert_eq(found(new_dir, counter), replacement.address().to_string())
    assert_true(new_dir.resolve(old.address()) is None)
    let stale = try {
      old_dir.resolve(old.address()).unwrap().send(Increment)
      "sent"
    } catch {
      @actors.Closed(_) => "closed"
      _ => "other"
    }
    assert_eq(stale, "closed")
    assert_eq(replacement.ask(reply => Read(reply)), 10)
  })
}

///|
async test "DIR-1: removal keeps the actor running and its name reserved" {
  @actors.scope(scope => {
    let counter = name("counter")
    let live = scope.start(0, handle_counter, name=counter)
    let copy = live.to_ref()
    let removed = @actors.Directory::of(live.to_ref()).remove(live.to_ref())
    assert_eq(removed.size(), 0)
    copy.send(Increment)
    assert_eq(copy.ask(reply => Read(reply)), 1)
    let again = try {
      ignore(scope.start(0, handle_counter, name=counter))
      "started"
    } catch {
      @actors.NameInUse(_) => "name in use"
      _ => "other"
    }
    assert_eq(again, "name in use")
  })
}

///|
async test "DIR-1: a directory stays usable after its owner scope exits" {
  let worker = name("worker")
  let (saved, outer_ref) = @actors.scope(outer => {
    let kept = outer.start(0, handle_counter, name=worker)
    let inner_ref = @actors.scope(inner => {
      inner.start(0, handle_counter).to_ref()
    })
    let saved = @actors.Directory::of(kept.to_ref()).add(inner_ref)
    assert_eq(found(saved, worker), kept.address().to_string())
    let closed = try {
      saved.resolve(inner_ref.address()).unwrap().send(Increment)
      "sent"
    } catch {
      @actors.Closed(_) => "closed"
      _ => "other"
    }
    assert_eq(closed, "closed")
    kept.send(Increment)
    assert_eq(kept.ask(reply => Read(reply)), 1)
    (saved, kept.to_ref())
  })
  assert_eq(saved.size(), 2)
  assert_eq(found(saved, worker), outer_ref.address().to_string())
  assert_true(outer_ref.try_send(Increment) == Closed)
}

///|
async test "DIR-1: union, add, remove and difference keep their laws for every small directory" {
  @actors.scope(scope => {
    let refs = Array::makei(4, _ => scope.start(0, handle_counter).to_ref()) catch {
      _ => panic()
    }
    // Every subset of four references.
    let all : Array[@actors.Directory[CounterMessage]] = Array::makei(16, mask => {
      let mut directory = @actors.Directory::empty()
      for bit in 0..<4 {
        if ((mask >> bit) & 1) == 1 {
          directory = directory.add(refs[bit])
        }
      }
      directory
    })
    let empty : @actors.Directory[CounterMessage] = @actors.Directory::empty()
    for a in all {
      assert_true(empty + a == a && a + empty == a && a + a == a)
      assert_true(a - empty == a && a - a == empty)
      for entry in refs {
        assert_true(a.add(entry) == a + @actors.Directory::of(entry))
        assert_true(a.add(entry).add(entry) == a.add(entry))
        assert_true(a.remove(entry).remove(entry) == a.remove(entry))
        assert_true(a.remove(entry).resolve(entry.address()) is None)
      }
      for b in all {
        assert_true(a + b == b + a)
        for c in all {
          assert_true((a + b) + c == a + (b + c))
          assert_true((a + b) - c == (a - c) + (b - c))
        }
      }
    }
    // The inputs did not change.
    assert_eq(all.map(directory => directory.size()), [
      0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4,
    ])
  })
}

///|
async test "NAME-1: of two concurrent named creators only one initializer runs" {
  let counter = name("counter")
  let initializers = Ref(0)
  @actors.scope(scope => {
    let outcomes = @aio.with_task_group(group => {
      let create = async fn() -> String {
        try {
          ignore(
            scope.start_with(
              _ => {
                initializers.val += 1
                @aio.pause()
                0
              },
              handle_counter,
              name=counter,
            ),
          )
          "started"
        } catch {
          @actors.NameInUse(taken) if taken == counter => "name in use"
          _ => "other"
        }
      }
      let first = group.spawn(create)
      let second = group.spawn(create)
      [first.wait(), second.wait()]
    })
    assert_true(outcomes.contains("started"))
    assert_true(outcomes.contains("name in use"))
  })
  assert_eq(initializers.val, 1)
}

///|
suberror Unready {
  Unready
} derive(Debug)

///|
async test "NAME-1: a failed named startup releases the name after its cleanup" {
  let counter = name("counter")
  let log = []
  @actors.scope(scope => {
    let failed = try {
      ignore(
        scope.start_with(
          setup => {
            setup.on_stop(() => {
              @aio.pause()
              log.push("cleanup")
            })
            raise Unready
          },
          handle_counter,
          name=counter,
        ),
      )
      "started"
    } catch {
      Unready => "failed"
      _ => "other"
    }
    assert_eq(failed, "failed")
    log.push("start again")
    let again = scope.start(0, handle_counter, name=counter)
    again.send(Increment)
    assert_eq(again.ask(reply => Read(reply)), 1)
  })
  assert_eq(log, ["cleanup", "start again"])
}

///|
async test "NAME-1: a closing actor keeps its name until its cleanup ends" {
  let counter = name("counter")
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let cleaning : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let old = scope.start(0, handle_counter, name=counter, on_stop=() => {
      cleaning.put(())
      gate.get()
    })
    let directory = @actors.Directory::of(old.to_ref())
    ignore(old.close())
    cleaning.get()
    let during = try {
      ignore(scope.start(0, handle_counter, name=counter))
      "started"
    } catch {
      @actors.NameInUse(_) => "name in use"
      _ => "other"
    }
    assert_eq(during, "name in use")
    assert_eq(directory.size(), 1)
    gate.put(())
    old.join()
    let replacement = scope.start(0, handle_counter, name=counter)
    assert_true(replacement.address() != old.address())
    // The old directory still holds the old actor, which stays closed.
    assert_eq(found(directory, counter), old.address().to_string())
    assert_eq(directory.resolve(old.address()).unwrap().try_send(Increment), Closed)
  })
}

///|
async test "NAME-1: names are case sensitive in lookup and in reservations" {
  @actors.scope(scope => {
    let upper = scope.start(0, handle_counter, name=name("Counter"))
    let lower = scope.start(0, handle_counter, name=name("counter"))
    let directory = @actors.Directory::of(upper.to_ref())
    assert_true(directory.lookup(name("counter")) is Missing)
    assert_eq(found(directory.add(lower.to_ref()), name("counter")), lower.address().to_string())
    assert_eq(upper.address().name(), Some(name("Counter")))
    assert_eq(upper.address().to_string().has_suffix("(Counter)"), true)
  })
}

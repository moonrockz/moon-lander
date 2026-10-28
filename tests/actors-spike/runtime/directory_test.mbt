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

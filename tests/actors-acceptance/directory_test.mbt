///|
enum Tick {
  Bump
  Value(@actors.Reply[Int])
}

///|
fn ticker(
  scope : @actors.Scope,
  name? : @actors.ActorName,
) -> @actors.Actor[Tick, Unit] raise @actors.ActorError {
  scope.start(
    0,
    (count, message) => {
      match message {
        Bump => Continue(count + 1)
        Value(reply) => {
          ignore(reply.send(count))
          Continue(count)
        }
      }
    },
    name?,
  )
}

///|
fn named(text : String) -> @actors.ActorName {
  @actors.ActorName::parse(text) catch {
    _ => panic()
  }
}

///|
async test "Discover a named actor: lookup gives a counter reference" {
  @actors.scope(scope => {
    let counter = ticker(scope, name=named("counter"))
    let directory = @actors.Directory::of(counter.to_ref())
    guard directory.lookup(named("counter")) is Found(found) else {
      fail("not found")
    }
    found.send(Bump)
    assert_eq(counter.ask(reply => Value(reply)), 1)
  })
}

///|
async test "Valid names and boundaries, and invalid names with their rule" {
  for text in ["a", "worker-17", "counter.total", "a".repeat(128)] {
    assert_eq(@actors.ActorName::parse(text).to_string(), text)
  }
  for text in ["", "9counter", "counter/total", "zähler", "two words", "a".repeat(129)] {
    let failed = try {
      ignore(@actors.ActorName::parse(text))
      false
    } catch {
      InvalidName(input~, ..) => input == text
    }
    assert_true(failed)
  }
}

///|
async test "Same name in separate directories: each lookup finds its own actor" {
  let worker = named("worker")
  let (first, second) = @actors.scope(outer => {
    let first = ticker(outer, name=worker)
    let second = @actors.scope(inner => ticker(inner, name=worker).to_ref())
    (first.to_ref(), second)
  })
  assert_true(first.address() != second.address())
  let one = @actors.Directory::of(first)
  let two = @actors.Directory::of(second)
  guard one.lookup(worker) is Found(found_one) else { fail("one") }
  guard two.lookup(worker) is Found(found_two) else { fail("two") }
  assert_true(found_one.address() == first.address())
  assert_true(found_two.address() == second.address())
  guard (one + two).lookup(worker) is Ambiguous(conflict) else {
    fail("not ambiguous")
  }
  assert_eq(conflict.refs().length(), 2)
}

///|
async test "Replacement with the same name: old directories keep the old actor" {
  @actors.scope(scope => {
    let counter = named("counter")
    let a = ticker(scope, name=counter)
    let old = @actors.Directory::of(a.to_ref())
    ignore(a.close())
    a.join()
    let b = ticker(scope, name=counter)
    let fresh = old.remove(a.to_ref()).add(b.to_ref())
    assert_true(a.address() != b.address())
    guard old.lookup(counter) is Found(found_a) else { fail("old") }
    guard fresh.lookup(counter) is Found(found_b) else { fail("fresh") }
    assert_true(found_a.address() == a.address())
    assert_true(found_b.address() == b.address())
    assert_true(fresh.resolve(a.address()) is None)
    assert_eq(old.resolve(a.address()).unwrap().try_send(Bump), Closed)
  })
}

///|
async test "Preserve an earlier directory: add and remove give new values" {
  @actors.scope(scope => {
    let a = ticker(scope).to_ref()
    let b = ticker(scope).to_ref()
    let original = @actors.Directory::of(a)
    let both = original.add(b)
    let only_b = both.remove(a)
    assert_eq((original.size(), both.size(), only_b.size()), (1, 2, 1))
    assert_true(original.resolve(a.address()) is Some(_))
    assert_true(only_b.resolve(a.address()) is None)
  })
}

///|
async test "Directory difference: A minus B, A minus empty and A minus A" {
  @actors.scope(scope => {
    let one = ticker(scope).to_ref()
    let two = ticker(scope).to_ref()
    let three = ticker(scope).to_ref()
    let a = @actors.Directory::of(one).add(two)
    let b = @actors.Directory::of(two).add(three)
    let empty : @actors.Directory[Tick] = @actors.Directory::empty()
    assert_true(a - b == @actors.Directory::of(one))
    assert_true(a - empty == a)
    assert_true(a - a == empty)
  })
}

///|
async test "Compose across owner scopes: scope A ends, B's actor stays, the directory keeps both" {
  @actors.scope(outer => {
    let kept = ticker(outer)
    let gone = @actors.scope(inner => ticker(inner).to_ref())
    let directory = @actors.Directory::of(kept.to_ref()).add(gone)
    assert_eq(directory.size(), 2)
    assert_eq(directory.resolve(gone.address()).unwrap().try_send(Bump), Closed)
    kept.send(Bump)
    assert_eq(kept.ask(reply => Value(reply)), 1)
  })
}

///|
/// A destination that records each event with its label.
fn recorder(label : String, log : Array[String]) -> @actors.Subject[Int] {
  @actors.Subject::new(
    send=event => {
      log.push("\{label} \{event}")
      Admitted
    },
    try_send=event => {
      log.push("\{label} \{event}")
      Accepted
    },
  )
}

///|
async test "TOPIC-1: publish delivers to the subscribers in subscription order" {
  let log = []
  @actors.scope(scope => {
    let topic : @actors.Topic[Int] = @actors.Topic::new()
    ignore(scope.subscribe(topic, recorder("a", log)))
    ignore(scope.subscribe(topic, recorder("b", log)))
    topic.publish(1)
    topic.publish(2)
  })
  assert_eq(log, ["a 1", "b 1", "a 2", "b 2"])
}

///|
async test "TOPIC-1: two actors each get one event in their own mailbox" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let topic : @actors.Topic[Int] = @actors.Topic::new()
    let slow = scope.start(0, (sum, event : Int) => {
      gate.get()
      Continue(sum + event)
    })
    let fast = scope.start(0, (sum, event : Int) => Continue(sum + event))
    ignore(scope.subscribe(topic, slow.to_ref().to_subject()))
    ignore(scope.subscribe(topic, fast.to_ref().to_subject()))
    // Publish returns at admission, while the slow handler still waits.
    topic.publish(5)
    topic.publish(6)
    assert_eq(slow.queued_count() + fast.queued_count() >= 1, true)
    gate.put(())
    gate.put(())
  })
}

///|
async test "TOPIC-1: a publication uses the snapshot taken when it starts" {
  let log = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  @actors.scope(scope => {
    let topic : @actors.Topic[Int] = @actors.Topic::new()
    let blocking : @actors.Subject[Int] = @actors.Subject::new(
      send=event => {
        log.push("blocking \{event}")
        started.put(())
        gate.get()
        Admitted
      },
      try_send=_ => Accepted,
    )
    ignore(scope.subscribe(topic, blocking))
    let late_leaver = scope.subscribe(topic, recorder("leaver", log))
    @aio.with_task_group(group => {
      group.spawn_bg(() => topic.publish(1))
      started.get()
      // A subscription made during the publication is not in its snapshot;
      // one that ends during it still gets the event.
      ignore(scope.subscribe(topic, recorder("joiner", log)))
      late_leaver.unsubscribe()
      gate.put(())
    })
    gate.put(())
    topic.publish(2)
  })
  assert_eq(log, ["blocking 1", "leaver 1", "blocking 2", "joiner 2"])
}

///|
async test "TOPIC-1: a closed destination is removed and the others still get the event" {
  let log = []
  @actors.scope(scope => {
    let topic : @actors.Topic[Int] = @actors.Topic::new()
    let ended = scope.start((), (_, _ : Int) => Stop)
    ended.send(0)
    ended.join()
    ignore(scope.subscribe(topic, ended.to_ref().to_subject()))
    ignore(scope.subscribe(topic, recorder("live", log)))
    assert_eq(topic.subscriber_count(), 2)
    topic.publish(1)
    assert_eq(topic.subscriber_count(), 1)
  })
  assert_eq(log, ["live 1"])
}

///|
async test "TOPIC-1: a full subscriber applies backpressure, and a cancelled publication keeps earlier admissions" {
  let log = []
  let started : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let one = @actors.MailboxCapacity::from_int(1)
  @actors.scope(scope => {
    let topic : @actors.Topic[Int] = @actors.Topic::new()
    let full = scope.start((), mailbox=Bounded(one), (_, event : Int) => {
      log.push("full got \{event}")
      started.put(())
      gate.get()
      Continue(())
    })
    full.send(0)
    started.get()
    full.send(0)
    ignore(scope.subscribe(topic, recorder("first", log)))
    ignore(scope.subscribe(topic, full.to_ref().to_subject()))
    ignore(scope.subscribe(topic, recorder("third", log)))
    @aio.with_task_group(group => {
      let publication = group.spawn(() => topic.publish(7))
      while log.length() < 2 {
        @aio.pause()
      }
      // The publication waits for the full second subscriber.
      assert_eq(full.queued_count(), 1)
      publication.cancel()
    })
    // The cancelled admission left no message, and the third subscriber was
    // not called.
    assert_eq(full.queued_count(), 1)
    gate.put(())
    gate.put(())
  })
  assert_eq(log, ["full got 0", "first 7", "full got 0"])
}

///|
async test "TOPIC-1: the end of the subscriber's scope removes its subscription" {
  let log = []
  @actors.scope(outer => {
    let topic : @actors.Topic[Int] = @actors.Topic::new()
    ignore(outer.subscribe(topic, recorder("outer", log)))
    @actors.scope(inner => {
      ignore(inner.subscribe(topic, recorder("inner", log)))
      topic.publish(1)
    })
    assert_eq(topic.subscriber_count(), 1)
    topic.publish(2)
  })
  assert_eq(log, ["outer 1", "inner 1", "outer 2"])
}

///|
async test "TOPIC-1: close rejects later publications and subscriptions" {
  @actors.scope(scope => {
    let topic : @actors.Topic[Int] = @actors.Topic::new()
    ignore(scope.subscribe(topic, recorder("a", [])))
    topic.close()
    assert_eq(topic.subscriber_count(), 0)
    let published = try {
      topic.publish(1)
      "published"
    } catch {
      @actors.TopicClosed => "closed"
      _ => "other"
    }
    let subscribed = try {
      ignore(scope.subscribe(topic, recorder("b", [])))
      "subscribed"
    } catch {
      @actors.TopicClosed => "closed"
      _ => "other"
    }
    assert_eq((published, subscribed), ("closed", "closed"))
  })
}

///|
suberror Unwritable {
  Unwritable
} derive(Debug)

///|
async test "TOPIC-1: a custom destination error stops the publication after earlier admissions" {
  let log = []
  let outcome = @actors.scope(scope => {
    let topic : @actors.Topic[Int] = @actors.Topic::new()
    ignore(scope.subscribe(topic, recorder("first", log)))
    ignore(
      scope.subscribe(
        topic,
        @actors.Subject::new(send=_ => raise Unwritable, try_send=_ => Closed),
      ),
    )
    ignore(scope.subscribe(topic, recorder("third", log)))
    try {
      topic.publish(1)
      "published"
    } catch {
      Unwritable => "unwritable"
      _ => "other"
    }
  })
  assert_eq((outcome, log), ("unwritable", ["first 1"]))
}

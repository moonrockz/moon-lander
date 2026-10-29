///|
async test "Fan-out to actors: each actor gets one event without waiting for handlers" {
  let gate : @aio.Queue[Unit] = @aio.Queue(kind=Unbounded)
  let got : @aio.Queue[String] = @aio.Queue(kind=Unbounded)
  let events = @actors.scope(scope => {
    let topic : @actors.Topic[Int] = @actors.Topic::new()
    let slow = scope.start((), (_, event : Int) => {
      gate.get()
      got.put("slow \{event}")
      Continue(())
    })
    let fast = scope.start((), (_, event : Int) => {
      got.put("fast \{event}")
      Continue(())
    })
    ignore(scope.subscribe(topic, slow.to_ref().to_subject()))
    ignore(scope.subscribe(topic, fast.to_ref().to_subject()))
    topic.publish(1)
    // The publication returned while the slow handler waits at its gate.
    let first = got.get()
    gate.put(())
    [first, got.get()]
  })
  assert_eq(events, ["fast 1", "slow 1"])
}

///|
async test "Scope removes subscriptions: a later publication excludes the subscriber" {
  let log = []
  @actors.scope(_ => {
    let topic : @actors.Topic[String] = @actors.Topic::new()
    let note : @actors.Subject[String] = @actors.Subject::new(
      send=event => {
        log.push(event)
        Admitted
      },
      try_send=_ => Accepted,
    )
    @actors.scope(inner => ignore(inner.subscribe(topic, note)))
    topic.publish("after")
    assert_eq(topic.subscriber_count(), 0)
  })
  assert_eq(log, [])
}

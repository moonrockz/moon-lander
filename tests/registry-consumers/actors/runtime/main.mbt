///|
/// The counter protocol of the actors README.
enum Counter {
  Increment
  Read(@actors.Reply[Int])
}

///|
/// A standalone runtime consumer. It resolves only actors, core and async.
async fn main {
  let count = @aio.with_timeout_opt(5000, () => {
    @actors.scope(scope => {
      let counter = scope.start(0, (state, message) => {
        match message {
          Increment => @actors.Continue(state + 1)
          Read(reply) => {
            ignore(reply.send(state))
            @actors.Continue(state)
          }
        }
      })
      counter.send(Increment)
      counter.ask(reply => Read(reply))
    })
  }) catch {
    error => abort("the counter failed: \{error}")
  }
  guard count is Some(1) else { abort("the counter gave a wrong count") }
  println("ok")
}

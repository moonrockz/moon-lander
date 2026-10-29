///|
/// The owner of actor lifetimes. `scope` makes it. When the body of `scope`
/// returns, the scope cancels its live actors and waits for them to end.
pub struct Scope {
  priv spawn_task : (async () -> Unit) -> Unit
  priv mut open : Bool
}

///|
/// Run `body` with a new scope. Actors that `body` starts belong to the scope.
/// When `body` returns, the scope stops accepting starts, cancels its live
/// actors and returns after they end. An actor that fails fails the scope and
/// cancels the other actors and `body`.
pub async fn[X] scope(body : async (Scope) -> X) -> X {
  @aio.with_task_group(group => {
    let scope = {
      spawn_task: task => group.spawn_bg(task, no_wait=true),
      open: true,
    }
    defer {
      scope.open = false
    }
    body(scope)
  })
}

///|
/// Make the lifetime record of a new actor.
fn Scope::begin(self : Scope, close_mailbox : () -> Unit) -> Lifetime raise ActorError {
  guard self.open else { raise ScopeClosed }
  Lifetime::new(close_mailbox)
}

///|
/// The owner of actor lifetimes. `scope` makes it. When the body of `scope`
/// returns, the scope cancels its live actors and waits for them to end.
pub struct Scope {
  /// Start a task that the scope owns. The result cancels the task.
  priv spawn_task : (async () -> Unit) -> () -> Unit
  priv mut open : Bool
}

///|
/// Run `body` with a new scope. Actors that `body` starts belong to the scope.
/// When `body` returns, the scope stops accepting starts, cancels its live
/// actors and returns after they and their cleanup end. An actor that fails
/// fails the scope and cancels the other actors and `body`.
pub async fn[X] scope(body : async (Scope) -> X) -> X {
  @aio.with_task_group(group => {
    let scope = {
      spawn_task: task => {
        let task = group.spawn(task, no_wait=true)
        () => task.cancel()
      },
      open: true,
    }
    defer {
      scope.open = false
    }
    body(scope)
  })
}

///|
/// A scope that accepts no start, for an actor that has no children.
fn Scope::closed() -> Scope {
  { spawn_task: _ => () => (), open: false }
}

///|
/// Make the lifetime record of a new actor.
fn Scope::begin(self : Scope, close_mailbox : () -> Unit) -> Lifetime raise ActorError {
  guard self.open else { raise ScopeClosed }
  Lifetime::new(close_mailbox)
}

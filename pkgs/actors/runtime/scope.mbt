///|
/// The owner of actor lifetimes. `scope` makes it. When the body of `scope`
/// returns, the scope cancels its live actors and waits for them to end.
pub struct Scope {
  /// Start a task that the scope owns. The result cancels the task.
  priv spawn_task : (async () -> Unit) -> () -> Unit
  priv mut open : Bool
  /// The names that live actors of this scope hold, with their addresses.
  priv names : Map[@policy.ActorName, ActorAddress]
  /// What runs when the body returns, such as ending subscriptions.
  priv exits : Array[() -> Unit]
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
      names: Map([]),
      exits: [],
    }
    defer {
      scope.open = false
      for exit in scope.exits {
        exit()
      }
    }
    body(scope)
  })
}

///|
/// A scope that accepts no start, for an actor that has no children.
fn Scope::closed() -> Scope {
  { spawn_task: _ => () => (), open: false, names: Map([]), exits: [] }
}

///|
/// Reserve `name` and make the lifetime record of a new actor. The name stays
/// reserved until the actor and its cleanup end; then only this actor's
/// reservation is released.
fn Scope::begin(
  self : Scope,
  name : @policy.ActorName?,
  close_mailbox : () -> Unit,
) -> Lifetime raise ActorError {
  guard self.open else { raise ScopeClosed }
  if name is Some(name) && self.names.contains(name) {
    raise NameInUse(name)
  }
  let address = ActorAddress::next(name)
  if name is Some(name) {
    self.names[name] = address
  }
  Lifetime::new(address, close_mailbox, () => {
    if name is Some(name) &&
      self.names.get(name) is Some(owner) &&
      owner == address {
      self.names.remove(name)
    }
  })
}

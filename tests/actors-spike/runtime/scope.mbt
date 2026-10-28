///|
/// The owner of actor lifetimes. `scope` makes it. When the body of `scope`
/// returns, the scope cancels its live actors and waits for them to end.
pub struct Scope {
  priv spawn_task : (async () -> Unit) -> Unit
  priv mut open : Bool
  priv names : Map[@policy.ActorName, ActorAddress]
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
      names: Map([]),
    }
    defer {
      scope.open = false
    }
    body(scope)
  })
}

///|
/// Reserve `name` and make the lifetime record of a new actor.
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
  {
    address,
    outcome: None,
    ended: @cond_var.Cond(),
    watchers: Map([]),
    last_watcher: 0,
    close_mailbox,
    release: () => {
      if name is Some(name) && self.names.get(name) is Some(owner) && owner == address {
        self.names.remove(name)
      }
    },
  }
}

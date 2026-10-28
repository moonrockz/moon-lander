///|
/// One serialized call on a private service. The closure hides the result
/// type, so calls with different result types share one mailbox.
priv struct Call[S] {
  run : async (S) -> Unit
}

///|
/// A handle to a service that one actor task owns. Calls run one at a time on
/// that task. The handle never exposes the service value.
pub struct ServiceRef[S] {
  priv actor : Actor[Call[S], Unit]
}

///|
/// Start an actor that owns `service`. The caller gives up its own use of the
/// value; captured aliases remain the caller's responsibility.
pub fn[S] Scope::create(
  self : Scope,
  service : S,
  mailbox? : @policy.MailboxPolicy = @policy.MailboxPolicy::default(),
) -> ServiceRef[S] raise ActorError {
  let actor = self.start(
    (),
    (_, call : Call[S]) => {
      (call.run)(service)
      Continue(())
    },
    mailbox~,
  )
  { actor, }
}

///|
/// Run `operation` on the service task and give its result. An error of
/// `operation` goes to this caller, and the service continues. Changes that
/// `operation` made before the error remain.
pub async fn[S, R] ServiceRef::ask(
  self : ServiceRef[S],
  operation : async (S) -> R,
  timeout? : @lander_core.TimeLimit = default_ask_limit(),
) -> R raise {
  let outcome : Result[R, Error] = self.actor.ask(
    reply => {
      run: service => {
        let result = try operation(service) catch {
          error => Err(error)
        } noraise {
          value => Ok(value)
        }
        ignore(reply.send(result))
      },
    },
    timeout~,
  )
  match outcome {
    Ok(value) => value
    Err(error) => raise error
  }
}

///|
/// Admit `operation` and return without its result. An error of `operation`
/// fails the service and its owner scope.
pub async fn[S] ServiceRef::tell(
  self : ServiceRef[S],
  operation : async (S) -> Unit,
) -> Unit raise ActorError {
  self.actor.send({ run: operation })
}

///|
/// The address of the service actor.
pub fn[S] ServiceRef::address(self : ServiceRef[S]) -> ActorAddress {
  self.actor.address()
}

///|
/// Wait until the service ends. See `Actor::join`.
pub async fn[S] ServiceRef::join(self : ServiceRef[S]) -> Unit {
  self.actor.join()
}

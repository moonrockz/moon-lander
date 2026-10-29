///|
/// One serialized call on a private service. The closure hides the result
/// type, so calls with different result types share one mailbox.
priv struct Call[S] {
  run : async (S) -> Unit
}

///|
/// A handle to a service that one actor task owns. Calls run one at a time on
/// that task. The handle never exposes the service value or a queued call.
pub struct ServiceRef[S] {
  priv actor : Actor[Call[S], Unit]
}

///|
/// Start an actor that owns `service`. The caller gives up its own use of the
/// value; captured aliases remain the caller's responsibility. `on_stop` and
/// `cleanup_limit` work as in `start`.
pub fn[S] Scope::create(
  self : Scope,
  service : S,
  mailbox? : @policy.MailboxPolicy = @policy.MailboxPolicy::default(),
  on_stop? : async () -> Unit,
  cleanup_limit? : @lander_core.TimeLimit = default_cleanup_limit(),
) -> ServiceRef[S] raise ActorError {
  let actor = self.start(
    (),
    (_, call : Call[S]) => {
      (call.run)(service)
      Continue(())
    },
    mailbox~,
    on_stop?,
    cleanup_limit~,
  )
  { actor, }
}

///|
/// Run `operation` on the service task and give its result. Each call can
/// have another result type. An error of `operation` goes to this caller,
/// and the service continues; changes that `operation` made before the error
/// remain. The wait policy works as in `ActorRef::ask`. Cancelling this
/// caller does not interrupt an admitted call.
pub async fn[S, R] ServiceRef::ask(
  self : ServiceRef[S],
  operation : async (S) -> R,
  timeout? : WaitPolicy = WaitPolicy::default(),
) -> R {
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
/// The lifecycle snapshot now. See `Actor::status`.
pub fn[S] ServiceRef::status(self : ServiceRef[S]) -> ActorStatus {
  self.actor.status()
}

///|
/// Reject new calls; queued callers wake with `Closed`. The call in progress
/// can finish. No queued call or service state is given back.
pub fn[S] ServiceRef::close(self : ServiceRef[S]) -> Unit {
  ignore(self.actor.close())
}

///|
/// Reject new calls, run the queued ones and wait for the end. See
/// `Actor::drain`.
pub async fn[S] ServiceRef::drain(self : ServiceRef[S]) -> Unit {
  self.actor.drain()
}

///|
/// Cancel the service. See `Actor::cancel`.
pub fn[S] ServiceRef::cancel(self : ServiceRef[S]) -> Unit {
  self.actor.cancel()
}

///|
/// Wait until the service ends. See `Actor::join`.
pub async fn[S] ServiceRef::join(self : ServiceRef[S]) -> Unit {
  self.actor.join()
}

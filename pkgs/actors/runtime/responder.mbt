///|
/// A request and the destination of its response.
priv struct Request[Req, Res] {
  request : Req
  reply : Reply[Res]
}

///|
/// An actor that answers each request with the result of one async handler.
/// The framework sends the response, so the caller needs no protocol enum and
/// no reply plumbing.
pub struct RequestActor[Req, Res] {
  priv actor : Actor[Request[Req, Res], Unit]
}

///|
/// Start an actor that answers each request with `handler(request)`. An error
/// of `handler` ends the actor, fails its owner scope and wakes every pending
/// caller with the cause. For a rejection that must not end the actor, give a
/// response type such as `Result[Value, Rejection]`.
pub fn[Req, Res] Scope::respond(
  self : Scope,
  handler : async (Req) -> Res,
  mailbox? : @policy.MailboxPolicy = @policy.MailboxPolicy::default(),
  on_stop? : async () -> Unit,
  cleanup_limit? : @lander_core.TimeLimit = default_cleanup_limit(),
) -> RequestActor[Req, Res] raise ActorError {
  let actor = self.start(
    (),
    (_, request : Request[Req, Res]) => {
      ignore(request.reply.send(handler(request.request)))
      Continue(())
    },
    mailbox~,
    on_stop?,
    cleanup_limit~,
  )
  { actor, }
}

///|
/// Send `request` and wait for the response, with the wait policy and the
/// termination rules of `ActorRef::ask`.
pub async fn[Req, Res] RequestActor::ask(
  self : RequestActor[Req, Res],
  request : Req,
  timeout? : WaitPolicy = WaitPolicy::default(),
) -> Res {
  self.actor.ask(reply => { request, reply }, timeout~)
}

///|
/// Like `ask`, but give `None` when the time limit ends first.
pub async fn[Req, Res] RequestActor::try_ask(
  self : RequestActor[Req, Res],
  request : Req,
  timeout? : WaitPolicy = WaitPolicy::default(),
) -> Res? {
  self.actor.try_ask(reply => { request, reply }, timeout~)
}

///|
/// The address of the actor.
pub fn[Req, Res] RequestActor::address(self : RequestActor[Req, Res]) -> ActorAddress {
  self.actor.address()
}

///|
/// The lifecycle snapshot now. See `Actor::status`.
pub fn[Req, Res] RequestActor::status(
  self : RequestActor[Req, Res],
) -> ActorStatus {
  self.actor.status()
}

///|
/// Reject new requests; queued callers wake with `Closed`. See `Actor::close`.
pub fn[Req, Res] RequestActor::close(self : RequestActor[Req, Res]) -> Unit {
  ignore(self.actor.close())
}

///|
/// Reject new requests, answer the queued ones and wait for the end. See
/// `Actor::drain`.
pub async fn[Req, Res] RequestActor::drain(self : RequestActor[Req, Res]) -> Unit {
  self.actor.drain()
}

///|
/// Cancel the actor. See `Actor::cancel`.
pub fn[Req, Res] RequestActor::cancel(self : RequestActor[Req, Res]) -> Unit {
  self.actor.cancel()
}

///|
/// Wait until the actor ends. See `Actor::join`.
pub async fn[Req, Res] RequestActor::join(self : RequestActor[Req, Res]) -> Unit {
  self.actor.join()
}

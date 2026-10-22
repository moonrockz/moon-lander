///|
/// A typed sender for one request type. It holds the one handler for that
/// request type. The context type `C`, the request type `Req`, and the reply
/// type `Res` are fixed at compile time, so a request of another type does not
/// compile. A sender exists only when the application builds it from a
/// handler: the compiler is the registry, and there is no runtime lookup.
struct Sender[C, Req, Res] {
  handle : (C, Req) -> Res raise
}

///|
/// Build a sender from its one handler. The handler takes the context value
/// and the request, and gives the reply or raises an error.
pub fn[C, Req, Res] sender(
  handle : (C, Req) -> Res raise,
) -> Sender[C, Req, Res] {
  { handle, }
}

///|
/// Send a request with a context value. The sender calls its one handler one
/// time and gives the handler reply. An error that the handler raises passes
/// out unchanged.
pub fn[C, Req, Res] Sender::send(
  self : Sender[C, Req, Res],
  ctx : C,
  req : Req,
) -> Res raise {
  (self.handle)(ctx, req)
}

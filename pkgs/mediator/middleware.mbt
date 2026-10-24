///|
/// One step of the pipeline around a handler. A middleware gets the next step
/// as a function value, the context value, and the request. It can run code
/// before and after it calls the next step, change the request or the reply,
/// give a reply without a call to the next step, or catch the error of the
/// next step. It cannot change which handler a sender calls.
struct Middleware[C, Req, Res] {
  wrap : ((C, Req) -> Res raise, C, Req) -> Res raise
}

///|
/// Build a middleware from a wrapper function. The wrapper gets `next`, the
/// context value, and the request, and gives the reply.
pub fn[C, Req, Res] middleware(
  wrap : ((C, Req) -> Res raise, C, Req) -> Res raise,
) -> Middleware[C, Req, Res] {
  { wrap, }
}

///|
/// Build a middleware that calls `hook` before the next step. An error that
/// `hook` raises ends the call, and the next step does not run.
pub fn[C, Req, Res] before(
  hook : (C, Req) -> Unit raise,
) -> Middleware[C, Req, Res] {
  middleware((next, ctx, req) => {
    hook(ctx, req)
    next(ctx, req)
  })
}

///|
/// Build a middleware that calls `hook` with the reply after the next step
/// gives it. `hook` does not run when the next step raises an error.
pub fn[C, Req, Res] after(
  hook : (C, Req, Res) -> Unit raise,
) -> Middleware[C, Req, Res] {
  middleware((next, ctx, req) => {
    let reply = next(ctx, req)
    hook(ctx, req, reply)
    reply
  })
}

///|
/// Build a middleware that calls `hook` after the next step, when the next
/// step gives a reply and when it raises an error. The error then passes out
/// unchanged. `hook` cannot raise, so it cannot hide the error of the next
/// step.
pub fn[C, Req, Res] finally_(
  hook : (C, Req) -> Unit,
) -> Middleware[C, Req, Res] {
  middleware((next, ctx, req) => {
    defer hook(ctx, req)
    next(ctx, req)
  })
}

///|
/// One async step of the pipeline around a handler. A middleware gets the next
/// step as an async function value, the context value, and the request. It can
/// wait, run code before and after it calls the next step, change the request
/// or the reply, give a reply without a call to the next step, or catch the
/// error of the next step. It cannot change which handler a sender calls.
struct Middleware[C, Req, Res] {
  wrap : async (async (C, Req) -> Res, C, Req) -> Res
}

///|
/// Build a middleware from an async wrapper function. The wrapper gets `next`,
/// the context value, and the request, and gives the reply.
pub fn[C, Req, Res] middleware(
  wrap : async (async (C, Req) -> Res, C, Req) -> Res,
) -> Middleware[C, Req, Res] {
  { wrap, }
}

///|
/// Build a middleware that calls the async `hook` before the next step. An
/// error that `hook` raises ends the call, and the next step does not run.
pub fn[C, Req, Res] before(
  hook : async (C, Req) -> Unit,
) -> Middleware[C, Req, Res] {
  middleware((next, ctx, req) => {
    hook(ctx, req)
    next(ctx, req)
  })
}

///|
/// Build a middleware that calls the async `hook` with the reply after the
/// next step gives it. `hook` does not run when the next step raises an error
/// or is cancelled.
pub fn[C, Req, Res] after(
  hook : async (C, Req, Res) -> Unit,
) -> Middleware[C, Req, Res] {
  middleware((next, ctx, req) => {
    let reply = next(ctx, req)
    hook(ctx, req, reply)
    reply
  })
}

///|
/// Build a middleware that calls `hook` after the next step: when the next
/// step gives a reply, when it raises an error, and when the caller cancels
/// it. The outcome then passes out unchanged. `hook` is a sync function that
/// cannot raise, so it runs also during a cancellation and cannot hide the
/// outcome of the next step.
pub fn[C, Req, Res] finally_(
  hook : (C, Req) -> Unit,
) -> Middleware[C, Req, Res] {
  middleware((next, ctx, req) => {
    defer hook(ctx, req)
    next(ctx, req)
  })
}

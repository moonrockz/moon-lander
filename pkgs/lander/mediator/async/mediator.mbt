///|
/// A typed async sender for one request type. It holds the one async handler
/// for that request type and the middleware around it. The context type `C`,
/// the request type `Req`, and the reply type `Res` are fixed at compile time,
/// so a request of another type does not compile. A sender exists only when
/// the application builds it from a handler: the compiler is the registry, and
/// there is no runtime lookup.
struct Sender[C, Req, Res] {
  handle : async (C, Req) -> Res
  /// The first item is the outermost step. No function changes this array
  /// after the sender exists.
  middleware : Array[Middleware[C, Req, Res]]
}

///|
/// Build an async sender from its one handler. The handler takes the context
/// value and the request, can wait, and gives the reply or raises an error.
pub fn[C, Req, Res] sender(handle : async (C, Req) -> Res) -> Sender[C, Req, Res] {
  { handle, middleware: [] }
}

///|
/// Give a new sender with `middleware` inside the middleware that the sender
/// has. The first middleware attached is the outermost step. The sender
/// itself does not change.
pub fn[C, Req, Res] Sender::use_(
  self : Sender[C, Req, Res],
  middleware : Middleware[C, Req, Res],
) -> Sender[C, Req, Res] {
  let steps = self.middleware.copy()
  steps.push(middleware)
  { handle: self.handle, middleware: steps }
}

///|
/// Send a request with a context value, and wait for the reply. The
/// middleware runs in attach order around the one handler. An error that no
/// middleware catches passes out unchanged.
pub async fn[C, Req, Res] Sender::send(
  self : Sender[C, Req, Res],
  ctx : C,
  req : Req,
) -> Res {
  run(self.middleware, 0, self.handle, ctx, req)
}

///|
/// Run the middleware from `index` to the end, then the handler.
async fn[C, Req, Res] run(
  steps : Array[Middleware[C, Req, Res]],
  index : Int,
  handle : async (C, Req) -> Res,
  ctx : C,
  req : Req,
) -> Res {
  if index >= steps.length() {
    handle(ctx, req)
  } else {
    (steps[index].wrap)((c, r) => run(steps, index + 1, handle, c, r), ctx, req)
  }
}

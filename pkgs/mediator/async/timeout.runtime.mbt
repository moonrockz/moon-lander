///|
/// Build a middleware that gives the next step the shared core `limit`.
/// A slow step is cancelled and raises a timeout error with that valid limit
/// and no request values. A step that ends in time gives its reply or error
/// unchanged.
pub fn[C, Req, Res] timeout(limit : @lander_core.TimeLimit) -> Middleware[C, Req, Res] {
  middleware((next, ctx, req) => {
    @aio.with_timeout(limit.to_millis(), () => next(ctx, req), error=@mediator.MediatorError::timed_out(limit))
  })
}

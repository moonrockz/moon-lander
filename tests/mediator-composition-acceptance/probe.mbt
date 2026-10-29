///|
/// The portable public composition surface, compiled on all four targets.
pub fn make_sender() -> @mediator_async.Sender[Unit, Int, Int] {
  @mediator_async.sender((_, request) => request + 1)
  .use_(@mediator_async.before((_, _) => ()))
  .use_(@mediator_async.after((_, _, _) => ()))
  .use_(@mediator_async.finally_((_, _) => ()))
}

///|
/// Run the host without ending the process. Hooks share one context and services
/// record. Start hooks run in registration order, stop hooks in reverse order.
/// Stop requests cancel the command task and its defers finish before shutdown.
/// Shutdown runs protected from outside cancellation.
pub async fn[S] run(host : Host[S], command : Hook[S]) -> RunOutcome {
  let config = @config.load(@config.builder(), @config.FileTree::new(complete=true)) catch {
    err => return outcome(err)
  }
  let config = match config {
    Done(config) => config
    Need(_) => abort("a complete file tree gives no file request")
  }
  let services = (host.factory)({ config, }) catch {
    err => return outcome(err)
  }
  let lifetime = Lifetime::new()
  lifetime.task_cancelled.val = @async.is_being_cancelled
  defer { lifetime.task_cancelled.val = () => false }
  let ctx : Context[S] = { services, config, lifetime }
  let mut step = Engine::start(host.services)
  while step is Run(pending, action) {
    if action == Raise(Stopping) { break }
    step = run_step(host, ctx, command, pending, action)
  }
  @async.protect_from_cancel(() => {
    while step is Run(pending, action) {
      step = run_step(host, ctx, command, pending, action)
    }
  })
  guard step is Finish(result) else { abort("the engine finishes after its last action") }
  lifetime.reason = Some(result.reason)
  if result.failures.is_empty() && result.requested_code is None && lifetime.exit_code is Some(code) {
    { ..result, exit_code: code }
  } else { result }
}

///|
async fn[S] run_step(host : Host[S], ctx : Context[S], command : Hook[S], pending : Pending, action : Action) -> Step {
  let lifetime = ctx.lifetime
  if pending.engine.reason is Some(reason) { lifetime.reason = Some(reason) }
  let completed = @async.handle_cancellation(() => {
    try {
      match action {
        Hook(reference, phase) => {
          if host.services[reference.index].hook(phase) is Some(hook) { hook(ctx) }
        }
        RunCommand => run_command(ctx, command)
        Raise(event) => lifetime.raise_event(event)
      }
      ActionResult::Returned
    } catch {
      StopRequested => { lifetime.stop_application(); Interrupted }
      error => Failed(error)
    }
  })
  if completed is None { lifetime.stop_application() }
  let result = completed.unwrap_or(Interrupted)
  let next = if lifetime.request is Some(request) {
    pending.stop_requested(request, lifetime.requested_code, result~, observed_signal?=lifetime.signal)
  } else if result is Failed(error) { pending.failed(error) }
  else { pending.done() }
  if pending.engine.reason is Some(reason) { lifetime.reason = Some(reason) }
  next
}

///|
async fn[S] run_command(ctx : Context[S], command : Hook[S]) -> Unit {
  let lifetime = ctx.lifetime
  @async.with_task_group(group => {
    let task = group.spawn(() => command(ctx), allow_failure=true)
    lifetime.cancel_command.val = Some(() => task.cancel())
    defer { lifetime.cancel_command.val = None }
    if lifetime.probe_stop() { task.cancel() }
    task.wait() catch {
      @async.WaitedTaskAlreadyCancelled => lifetime.stop_application()
      error => raise error
    }
  })
}

///|
/// A configuration or factory failure before the engine starts.
fn outcome(error : Error) -> RunOutcome {
  { exit_code: ExitCode::failure(), failures: [error], reason: StartFailed(error), requested_code: None, signal: None }
}

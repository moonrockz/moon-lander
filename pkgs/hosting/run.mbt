///|
/// Run the host without ending the process. Hooks share one context and services
/// record. Start hooks run in registration order, stop hooks in reverse order.
/// Stop requests cancel the command task and its defers finish before shutdown.
/// Shutdown runs protected from outside cancellation, within one time budget.
/// It reports each shutdown timeout for every exit code, and other failures only
/// for code 1 or 2, in failure order, through `error_report` or as
/// `<name>: <message>` on standard error. Report errors do not change the outcome.
pub async fn[S] run(host : Host[S], command : Hook[S]) -> RunOutcome {
  run_with_directory_reader(host, command)
}

///|
async fn[S] run_with_directory_reader(host : Host[S], command : Hook[S], read_directory? : () -> @lander_core.AbsolutePath raise WorkingDirectoryError = process_directory) -> RunOutcome {
  let result = execute(host, command, read_directory~)
  @async.protect_from_cancel(() => {
    for error in result.failures {
      if error is ShutdownTimedOut(_) || result.exit_code == ExitCode::failure() || result.exit_code == usage_exit_code() {
        try {
          match host.report {
            Some(report) => report(error, result.exit_code)
            None => write_report_line(report_text(host.name, error))
          }
        } catch { _ => () }
      }
    }
  })
  result
}

///|
async fn[S] execute(host : Host[S], command : Hook[S], read_directory~ : () -> @lander_core.AbsolutePath raise WorkingDirectoryError) -> RunOutcome {
  let settings = resolve_settings(host, read_directory~) catch { err => return outcome(err) }
  let parsed = parse_arguments(host, env=settings.variables) catch { err => return outcome(err) }
  let environment = resolve_environment(host, settings, parsed.discovery_options) catch { err => return outcome(err) }
  let options = environment_options(parsed.discovery_options, environment)
  let config = @config.load(configuration_builder(host, settings, options), @config.FileTree::new(complete=true)) catch {
    err => return outcome(err)
  }
  let config = match config {
    Done(config) => config
    Need(_) => abort("a complete file tree gives no file request")
  }
  let services = (host.factory)({ config, environment, args: parsed.matches, env_vars: settings.variables, working_dir: settings.directory }) catch {
    StopRequested => return {
      exit_code: ExitCode::success(), timed_out: false, failures: [],
      reason: Requested, requested_code: None, signal: None,
    }
    err => return outcome(err)
  }
  let lifetime = Lifetime::new()
  lifetime.task_cancelled.val = @async.is_being_cancelled
  defer { lifetime.task_cancelled.val = () => false }
  let ctx : Context[S] = { services, config, environment, lifetime, args: parsed.matches, env_vars: settings.variables, working_dir: settings.directory }
  let mut step = Engine::start(host.services)
  while step is Run(pending, action) {
    if action == Raise(Stopping) { break }
    step = run_step(host, ctx, command, pending, action)
  }
  if @async.is_being_cancelled() { lifetime.stop_application() }
  @async.protect_from_cancel(() => {
    let mut interrupted = ActionResult::Interrupted
    let completed = @async.with_timeout_opt(host.shutdown_timeout.to_millis(), () => {
      while step is Run(pending, action) {
        let result = perform_step(host, ctx, command, pending, action)
        // Keep the current token for timed_out, even if a hook absorbs cancellation.
        if @async.is_being_cancelled() {
          interrupted = result.unwrap_or(Interrupted)
          break
        }
        step = reply_step(ctx, pending, result)
      }
    })
    if completed is None && step is Run(pending, _) {
      ignore(lifetime.probe_stop())
      step = pending.timed_out(limit=host.shutdown_timeout, observed_signal?=lifetime.signal, result=interrupted)
    }
    // The timeout reply skips hooks and leaves only the stopped event.
    while step is Run(pending, action) {
      step = run_step(host, ctx, command, pending, action)
    }
  })
  guard step is Finish(result) else { abort("the engine finishes after its last action") }
  lifetime.reason = Some(result.reason)
  { ..result, exit_code: select_exit_code(result.signal, result.failures, result.timed_out,
      match lifetime.exit_code { Some(code) => Some(code); None => result.requested_code }) }
}

///|
async fn[S] run_step(host : Host[S], ctx : Context[S], command : Hook[S], pending : Pending, action : Action) -> Step {
  reply_step(ctx, pending, perform_step(host, ctx, command, pending, action))
}

///|
async fn[S] perform_step(host : Host[S], ctx : Context[S], command : Hook[S], pending : Pending, action : Action) -> ActionResult? {
  let lifetime = ctx.lifetime
  if pending.engine.reason is Some(reason) { lifetime.reason = Some(reason) }
  @async.handle_cancellation(() => {
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
}

///|
fn[S] reply_step(ctx : Context[S], pending : Pending, completed : ActionResult?) -> Step {
  let lifetime = ctx.lifetime
  if completed is None { lifetime.stop_application() }
  ignore(lifetime.probe_stop())
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
  { exit_code: select_exit_code(None, [error], false, None), timed_out: false, failures: [error], reason: StartFailed(error), requested_code: None, signal: None }
}

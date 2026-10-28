///|
/// Run the host without ending the process. Hooks share one context and services
/// record. Start hooks run in registration order, stop hooks in reverse order.
/// Stop requests cancel the command task and its defers finish before shutdown.
/// Shutdown runs protected from outside cancellation, within one time budget.
/// It reports each shutdown timeout for every exit code, and other failures only
/// for code 1 or 2, in failure order, through `error_report` or as
/// `<name>: <message>` on standard error. Report errors do not change the outcome.
///
/// A help or version request of the arguments writes the argparse text one
/// time with `println` and returns code 0 with the reason `Requested`, before
/// the configuration load, the factory and the hooks. The console driver then
/// ends the process with that code.
///
/// A console driver gives `signals`. The run registers the probe before the
/// first hook, so each cancellation check reads it, and a watcher task reads it
/// every 50 ms until the run ends. The first signal is a stop request with the
/// reason `Signal(kind)`, and it cancels the command task.
pub async fn[S] run(host : Host[S], command : Hook[S], signals? : SignalProbe) -> RunOutcome {
  run_with_directory_reader(host, command, signals?)
}

///|
/// The time between two reads of the signal probe by the watcher task.
let signal_watch_interval : Int = 50

///|
async fn[S] run_with_directory_reader(host : Host[S], command : Hook[S], read_directory? : () -> @lander_core.AbsolutePath raise WorkingDirectoryError = process_directory, signals? : SignalProbe) -> RunOutcome {
  let result = execute(host, command, read_directory~, signals?)
  @async.protect_from_cancel(() => {
    for error in result.failures {
      if error is ShutdownTimedOut(_) || result.exit_code == ExitCode::failure() || result.exit_code == usage_exit_code() {
        try {
          match host.report {
            Some(report) => report(error, result.exit_code)
            None =>
              match host.report_writer {
                Some(writer) => writer(report_text(host.name, error))
                None => write_report_line(report_text(host.name, error))
              }
          }
        } catch { _ => () }
      }
    }
  })
  result
}

///|
async fn[S] execute(host : Host[S], command : Hook[S], read_directory~ : () -> @lander_core.AbsolutePath raise WorkingDirectoryError, signals? : SignalProbe) -> RunOutcome {
  let inputs = configuration_inputs(host, read_directory~) catch {
    DisplayRequested(text) => {
      println(text)
      return with_signal(requested_outcome(), signals)
    }
    err => return with_signal(outcome(err), signals)
  }
  let config = @host.load(inputs.sources) catch { err => return with_signal(outcome(err), signals) }
  let configured = finish_configuration(host, inputs, config) catch {
    StopRequested => return with_signal(requested_outcome(), signals)
    err => return with_signal(outcome(err), signals)
  }
  let ctx = configured.context
  let lifetime = ctx.lifetime
  guard signals is Some(probe) else { return run_engine(host, configured, command) }
  lifetime.register_stop_probe(probe.request)
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      while true {
        @async.sleep(signal_watch_interval)
        ignore(lifetime.probe_stop())
      }
    })
    run_engine(host, configured, command)
  })
}

///|
/// A signal that arrived before the engine started still selects the exit code.
/// The reason stays the first event of the run.
fn with_signal(result : RunOutcome, signals : SignalProbe?) -> RunOutcome {
  guard signals is Some(probe) && (probe.request)() is Some(Signal(kind)) else { return result }
  { ..result, signal: Some(kind), exit_code: kind.exit_code() }
}

///|
async fn[S] run_engine(host : Host[S], configured : ConfiguredRun[S], command : Hook[S]) -> RunOutcome {
  let ctx = configured.context
  let lifetime = ctx.lifetime
  lifetime.task_cancelled.val = @async.is_being_cancelled
  defer { lifetime.task_cancelled.val = () => false }
  let mut step = lifetime.start_engine(host.services)
  while step is Run(pending, action) {
    if action == Raise(Stopping) { break }
    step = run_step(host, ctx, command, pending, action)
  }
  if @async.is_being_cancelled() { lifetime.stop_application() }
  @async.protect_from_cancel(() => {
    let mut interrupted = ActionResult::Interrupted
    let completed = @async.with_timeout_opt(configured.shutdown_timeout.to_millis(), () => {
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
      step = pending.timed_out(limit=configured.shutdown_timeout, observed_signal?=lifetime.signal, result=interrupted)
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
  if completed is None { ctx.lifetime.stop_application() }
  ctx.lifetime.reply(pending, completed.unwrap_or(Interrupted))
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

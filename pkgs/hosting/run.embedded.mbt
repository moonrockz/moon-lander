///|
// `%async.run` is a compiler intrinsic, not a public API. Keep its uses in this
// file only (design Risks). It runs an async closure until the closure returns
// or until its first suspension point, and then it returns.
fn run_until_suspension(work : async () -> Unit noraise) -> Unit = "%async.run"

///|
async fn[X] capture_cancellation(f : async () -> X, handler~ : async () -> X nocancel) -> X nocancel = "%async.capture_cancellation"

///|
/// How one hook, the command or one report ended in `%async.run`.
priv enum Completion {
  Returned
  Stopped
  Failed(Error)
  Cancelled
  Suspended
}

///|
/// Run `work` without an event loop. The result belongs to this call only: a
/// suspended continuation that resumes later finds the step closed and cannot
/// change the result of a completed step or run.
fn run_to_completion(work : async () -> Unit) -> Completion {
  let completion = Ref(Completion::Suspended)
  let open = Ref(true)
  run_until_suspension(() => {
    let result = capture_cancellation(() => { work(); Completion::Returned }, handler=() => Completion::Cancelled) catch {
      StopRequested => Stopped
      error => Failed(error)
    }
    if open.val { completion.val = result }
  })
  open.val = false
  completion.val
}

///|
/// Run the host without an event loop, on wasm and wasm-gc, and return when it
/// ends. The run does not end the process. Configuration comes from the
/// `files` tree. Hooks and the command run in the same order and with the same
/// failure and exit-code rules as `run`, but they must not suspend: a hook or
/// command that waits fails with `SuspendError` and code 1. Do not call
/// `moonbitlang/async` there, because it needs its own event loop.
/// There are no signals and no shutdown timeout. The run stops through
/// `stop_application` or through `stop_probe`. The host reads the probe in
/// each cancellation check and after each hook. When it gives `true`, the run
/// stops with the reason `Embedder`.
/// The default report writes `<name>: <message>` lines with `eprintln`: on
/// wasm to WASI standard error, on wasm-gc to the only output channel of core.
/// A replacement `error_report` must not suspend; the driver ignores a report
/// that raises or suspends.
/// A continuation that the embedder keeps and resumes after its step ended
/// cannot change the result of that step. It still runs with the context of
/// the run, so it can make a stop request while the run is in progress. Do not
/// keep continuations of hooks or the command.
pub fn[S] run_embedded(host : Host[S], command : Hook[S], stop_probe? : () -> Bool) -> RunOutcome {
  run_embedded_with_writer(host, command, stop_probe?, write_line=line => eprintln(line))
}

///|
fn[S] run_embedded_with_writer(host : Host[S], command : Hook[S], stop_probe? : () -> Bool, write_line~ : (String) -> Unit) -> RunOutcome {
  let result = execute_embedded(host, command, stop_probe)
  for error in result.failures {
    if error is ShutdownTimedOut(_) || result.exit_code == ExitCode::failure() || result.exit_code == usage_exit_code() {
      match host.report {
        Some(report) => ignore(run_to_completion(() => report(error, result.exit_code)))
        None => write_line(report_text(host.name, error))
      }
    }
  }
  result
}

///|
fn[S] execute_embedded(host : Host[S], command : Hook[S], stop_probe : (() -> Bool)?) -> RunOutcome {
  let inputs = configuration_inputs(host) catch { err => return outcome(err) }
  // Task 13.4: a help or version request will return here with code 0,
  // before configuration, the factory and the hooks. Today the pinned argparse
  // ends the process inside `parse_arguments`.
  let config = configuration_from_tree(inputs.sources, host.file_tree) catch { err => return outcome(err) }
  let configured = finish_configuration(host, inputs, config) catch {
    StopRequested => return {
      exit_code: ExitCode::success(), timed_out: false, failures: [],
      reason: Requested, requested_code: None, signal: None,
    }
    err => return outcome(err)
  }
  let ctx = configured.context
  let lifetime = ctx.lifetime
  if stop_probe is Some(probe) {
    lifetime.register_stop_probe(() => if probe() { Some(Embedder) } else { None })
  }
  let mut step = lifetime.skip_first_if_stopped(Engine::start(host.services))
  while step is Run(pending, action) {
    step = lifetime.reply(pending, perform_embedded(host, ctx, command, pending, action))
  }
  guard step is Finish(result) else { abort("the engine finishes after its last action") }
  lifetime.reason = Some(result.reason)
  { ..result, exit_code: select_exit_code(result.signal, result.failures, result.timed_out,
      match lifetime.exit_code { Some(code) => Some(code); None => result.requested_code }) }
}

///|
fn[S] perform_embedded(host : Host[S], ctx : Context[S], command : Hook[S], pending : Pending, action : Action) -> ActionResult {
  let lifetime = ctx.lifetime
  if pending.engine.reason is Some(reason) { lifetime.reason = Some(reason) }
  let (completion, suspended) = match action {
    Hook(reference, phase) => {
      let service = host.services[reference.index]
      guard service.hook(phase) is Some(hook) else { return Returned }
      (run_to_completion(() => hook(ctx)), HookSuspended(service=service.name, phase=hook_phase(phase)))
    }
    RunCommand => (run_to_completion(() => command(ctx)), CommandSuspended)
    Raise(event) => { lifetime.raise_event(event); return Returned }
  }
  match completion {
    Returned => Returned
    Failed(error) => Failed(error)
    Suspended => Failed(suspended)
    Stopped | Cancelled => { lifetime.stop_application(); Interrupted }
  }
}

///|
fn hook_phase(phase : Phase) -> HookPhase {
  match phase {
    Starting => Starting
    Start => Start
    Started => Started
    Stopping => Stopping
    Stop => Stop
    Stopped => Stopped
  }
}

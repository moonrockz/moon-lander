///|
/// Run a validated launch plan from synchronous `fn main`, then exit with the
/// selected process status. This driver owns its isolated runtime; no canonical
/// async task, scope or handle crosses this boundary.
///
/// Finalization runs once after child reaping, including startup failure and
/// cancellation. Completion receives the typed outcome after finalization.
/// Either callback's failure changes selected success into failure, preserving
/// an existing failure or OS signal status. A completion callback sees the
/// selection before its own invocation.
///
/// Standard streams are inherited directly; no forwarding task waits for stdin
/// EOF. The child keeps the caller's working directory. Output remains opaque.
/// Original SIGINT/SIGTERM forwarding is guaranteed on POSIX. Stock Windows
/// Moonrun delivers Ctrl-C as Ctrl-Break; actual child and parent outcomes stay
/// distinct. See the module guide for the qualified platform limitation.
pub fn run(
  plan : @moonx.LaunchPlan,
  grace~ : @moonx.ShutdownGrace = @moonx.ShutdownGrace::standard(),
  finalize~ : () -> Unit raise = () => (),
  completed~ : (@moonx.LaunchOutcome) -> Unit raise = _ => (),
) -> Unit {
  let status = Ref(@moonx.ProcessStatus::failure())
  let result : Ref[@moonx.LaunchResult?] = Ref(None)
  let failures : Array[@moonx.FinalizationFailure] = []
  let payload : Ref[OwnedPayload?] = Ref(None)
  @runtime.run(() => {
    @signal.set_global_cancellation_signals([SIGINT, SIGTERM, SIGHUP, SIGBREAK])
    defer @runtime.protect_from_cancel(() => {
      if result.val is None {
        result.val = Some(NotStarted(Cancelled(cancellation_cause())))
      }
      if payload.val is Some(owned) {
        owned.cleanup() catch {
          error => {
            failures.push(PayloadCleanup(error))
            if status.val.is_success() { status.val = @moonx.ProcessStatus::failure() }
          }
        }
      }
      finalize() catch {
        error => {
          failures.push(Finalizer(error))
          if status.val.is_success() { status.val = @moonx.ProcessStatus::failure() }
        }
      }
      status.val = selected_status(status.val)
      let outcome = @moonx.LaunchOutcome::new(result.val.unwrap(), status.val, failures)
      completed(outcome) catch {
        _ => {
          if status.val.is_success() { status.val = @moonx.ProcessStatus::failure() }
        }
      }
      status.val = selected_status(status.val)
    })
    let _ = @runtime.handle_cancellation(() => {
      match plan {
        Process(command) => launch(command, Direct, grace, result, status)
        Node(node) => {
          let command = materialize(node, payload) catch {
            error => {
              result.val = Some(NotStarted(Failed(Materialization(error))))
              None
            }
          } noraise { command => Some(command) }
          if command is Some(command) { launch(command, Node, grace, result, status) }
        }
      }
    })
  })
  @sys.exit(status.val.to_int())
}

///|
fn process_status(raw : Int) -> @moonx.ProcessStatus {
  let normalized = if @runtime.platform is Windows || raw >= 0 { raw } else { 128 - raw }
  @moonx.ProcessStatus::from_bits(normalized.reinterpret_as_uint())
}

///|
fn signal_identity(signal : @signal.Signal) -> @moonx.LauncherSignal {
  match signal {
    SIGINT => Interrupt
    SIGTERM => Terminate
    SIGHUP => Hangup
    SIGBREAK => Break
  }
}

///|
fn cancellation_cause() -> @moonx.CancellationCause {
  match @signal.received_cancellation_signal() {
    Some(signal) => Signal(signal_identity(signal))
    None => Requested
  }
}

///|
fn selected_status(finite : @moonx.ProcessStatus) -> @moonx.ProcessStatus {
  match @signal.exit_cancellation_signal() {
    None => finite
    Some(signal) => {
      // Stock native async and Moonrun both select STATUS_CONTROL_C_EXIT for
      // Windows console cancellation. Do not treat this as a POSIX signal code.
      if @runtime.platform is Windows {
        @moonx.ProcessStatus::from_bits(0xc000013aU)
      } else {
        @moonx.ProcessStatus::from_bits((128 + signal.to_int()).reinterpret_as_uint())
      }
    }
  }
}

///|
async fn launch(
  command : @moonx.Command,
  kind : ProcessKind,
  grace : @moonx.ShutdownGrace,
  result : Ref[@moonx.LaunchResult?],
  status : Ref[@moonx.ProcessStatus],
) -> Unit {
  let started = Ref(false)
  let stopped = Ref(false)
  let forced = Ref(false)
  let raw_status : Ref[Int?] = Ref(None)
  @runtime.with_task_group(group => {
    let child = @process.spawn(
      group, command.executable().to_string(), command.arguments().to_array(),
      stdin=@stdio.stdin, stdout=@stdio.stdout, stderr=@stdio.stderr,
      cancel_handler=@process.CancellationHandler(pid => {
        stopped.val = true
        let handler = match @signal.received_cancellation_signal() {
          Some(signal) => @process.graceful_cancel(
            timeout=grace.milliseconds(), signal~, on_force=() => forced.val = true,
          )
          None => @process.graceful_cancel(
            timeout=grace.milliseconds(), on_force=() => forced.val = true,
          )
        }
        let @process.CancellationHandler(cancel) = handler
        cancel(pid)
      }),
    )
    // spawn has returned an actual process. Record this before the next yield.
    started.val = true
    group.add_defer(() => {
      // All child tasks, including its protected wait and cancellation handler,
      // have finished before a group defer. Read the real retained wait result.
      raw_status.val = child.try_wait()
      if raw_status.val is Some(raw) {
        let child_status = process_status(raw)
        status.val = child_status
        result.val = Some(Started(if stopped.val {
          Stopped(cause=cancellation_cause(), status=child_status, force_requested=forced.val)
        } else { Exited(child_status) }))
      }
    })
    let _ = child.wait()
  }) catch {
    error => {
      result.val = Some(if started.val {
        Started(Failed(error))
      } else { NotStarted(Failed(startup_failure(command, kind, error))) })
      status.val = @moonx.ProcessStatus::failure()
    }
  }
}

///|
priv enum ProcessKind {
  Direct
  Node
}

///|
fn startup_failure(
  command : @moonx.Command,
  kind : ProcessKind,
  error : Error,
) -> @moonx.StartupFailure {
  match (kind, error) {
    (Node, @os_error.OSError(_) as missing) if missing.is_ENOENT() =>
      NodeMissing(executable=command.executable(), cause=error)
    _ => ProcessStart(error)
  }
}

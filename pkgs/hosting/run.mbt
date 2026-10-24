///|
/// Run the host with `command` and give the outcome. The run does not end the
/// process, so a test can call it.
///
/// The run loads the configuration, builds the services record one time, and
/// runs the six service hooks in phase order. Start phases use registration
/// order; stop phases use reverse order for started services only. A start
/// failure skips later start hooks and the command. Stop failures are collected
/// without skipping later hooks. Each hook and the command get the same context.
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
  let ctx : Context[S] = { services, config }
  let mut step = Engine::start(host.services)
  while step is Run(pending, action) {
    step = try {
      match action {
        Hook(reference, phase) => {
          if host.services[reference.index].hook(phase) is Some(hook) {
            hook(ctx)
          }
        }
        RunCommand => command(ctx)
        Raise(_) => ()
      }
    } catch {
      error => pending.failed(error)
    } noraise {
      _ => pending.done()
    }
  }
  guard step is Finish(result) else { abort("the engine finishes after its last action") }
  result
}

///|
/// A configuration or factory failure before the engine starts.
fn outcome(error : Error) -> RunOutcome {
  { exit_code: ExitCode::failure(), failures: [error], reason: Failed(error), requested_code: None }
}

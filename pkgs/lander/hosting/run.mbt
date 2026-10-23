///|
/// Run the host with `command` and give the outcome. The run does not end the
/// process, so a test can call it.
///
/// The run loads the configuration, builds the services record one time, runs
/// the `start` hooks in registration order, runs the command, and then runs the
/// `stop` hooks in reverse order. Only a service whose `start` hook succeeded
/// gets its `stop` hook. A failure in a `start` hook skips the other `start`
/// hooks and the command. A failure in a `stop` hook does not skip the other
/// `stop` hooks. The exit code is 1 when a failure occurred, else 0.
pub async fn[S] run(host : Host[S], command : Hook[S]) -> RunOutcome {
  let failures : Array[Error] = []
  let config = @config.load(@config.builder(), @config.FileTree::new(complete=true)) catch {
    err => return outcome([err])
  }
  let config = match config {
    Done(config) => config
    Need(_) => abort("a complete file tree gives no file request")
  }
  let services = (host.factory)({ config, }) catch {
    err => return outcome([err])
  }
  let ctx : Context[S] = { services, config }
  let mut started = 0
  let mut start_failed = false
  for service in host.services {
    if service.start is Some(start) {
      start(ctx) catch {
        err => {
          failures.push(err)
          start_failed = true
          break
        }
      }
    }
    started += 1
  }
  if !start_failed {
    command(ctx) catch {
      err => failures.push(err)
    }
  }
  for i = started - 1; i >= 0; i = i - 1 {
    if host.services[i].stop is Some(stop) {
      stop(ctx) catch {
        err => failures.push(err)
      }
    }
  }
  outcome(failures)
}

///|
/// The outcome with the exit code that `failures` gives.
fn outcome(failures : Array[Error]) -> RunOutcome {
  { exit_code: ExitCode(if failures.is_empty() { 0 } else { 1 }), failures }
}

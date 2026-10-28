///|
/// The behavior of the test host. The parent process selects it with the
/// environment variable `LANDER_CONSOLE_SCENARIO`.
pub(all) enum Scenario {
  /// All hooks and a command that returns.
  Clean
  /// The command writes `ready` and waits until a signal cancels it.
  Wait
  /// The command writes `ready` and polls `ctx.cancelled()` in a loop with no
  /// suspension point.
  Poll
  /// The command writes `ready` and loops with no suspension point and no
  /// check, so only a second signal can end the process.
  Spin
  /// As `Wait`, but the `stop` hook of `b` writes `slow` and waits.
  SlowStop
  /// The command writes `output_lines` lines and returns.
  Output
  /// As `Wait`, and the `stop` hook of `a` writes `output_lines` lines.
  OutputAfterSignal
  /// As `Wait`, and the `started` hook of `a` leaves a timer open on js.
  Linger
  /// The arguments are `--help`, so the run ends before any hook.
  Help
  /// The arguments are `--version`, so the run ends before any hook.
  Version
}

///|
/// The scenario named by `text`, or `None` for an unknown name.
pub fn Scenario::parse(text : String) -> Scenario? {
  match text {
    "clean" => Some(Clean)
    "wait" => Some(Wait)
    "poll" => Some(Poll)
    "spin" => Some(Spin)
    "slow-stop" => Some(SlowStop)
    "output" => Some(Output)
    "output-after-signal" => Some(OutputAfterSignal)
    "linger" => Some(Linger)
    "help" => Some(Help)
    "version" => Some(Version)
    _ => None
  }
}

///|
/// The count of lines in the output scenarios: more than one pipe buffer.
pub let output_lines : Int = 4000

///|
/// The text of output line `index`. Each line has 72 characters.
pub fn output_line(index : Int) -> String {
  let number = index.to_string()
  "line=" + "0".repeat(6 - number.length()) + number + " " + "x".repeat(60)
}

///|
fn reason_text(reason : @hosting.StopReason?) -> String {
  match reason {
    Some(Signal(Interrupt)) => "Signal(Interrupt)"
    Some(Signal(Terminate)) => "Signal(Terminate)"
    Some(Signal(Quit)) => "Signal(Quit)"
    Some(Completed) => "Completed"
    Some(Requested) => "Requested"
    Some(Embedder) => "Embedder"
    Some(StartFailed(_)) => "StartFailed"
    Some(Failed(_)) => "Failed"
    None => "none"
  }
}

///|
async fn write_output() -> Unit {
  for index in 0..<output_lines {
    emit(output_line(index))
  }
  emit("end")
}

///|
/// Run the test host with the console driver. On native the process ends
/// inside `@hosting_console.run`; on js it ends when the event loop is empty.
pub async fn run(
  scenario : Scenario,
  signals? : @hosting.SignalProbe,
  finalize? : @hosting_console.Finalizer,
) -> Unit {
  let polled = Ref(false)
  let args = match scenario {
    Help => ["--help"]
    Version => ["--version"]
    _ => []
  }
  let host : @hosting.Host[Unit] = @hosting.builder(
      @lander_core.AppName::parse("console-host"),
      args,
    )
    |> @hosting_argparse.command(name => @hosting_argparse.Command(
      name,
      version="1.2.3",
    ))
    |> @hosting.service(
      "a",
      starting=_ => emit("hook=a.starting"),
      start=_ => emit("hook=a.start"),
      started=_ => {
        emit("hook=a.started")
        if scenario is Linger {
          leave_timer_open()
        }
      },
      stopping=ctx => {
        emit("hook=a.stopping")
        emit("reason=" + reason_text(ctx.lifetime.stop_reason()))
        if polled.val {
          emit("polled=true")
        }
      },
      stop=_ => {
        emit("hook=a.stop")
        if scenario is OutputAfterSignal {
          write_output()
        }
      },
      stopped=_ => emit("hook=a.stopped"),
    )
    |> @hosting.service(
      "b",
      starting=_ => emit("hook=b.starting"),
      start=_ => emit("hook=b.start"),
      started=_ => emit("hook=b.started"),
      stopping=_ => emit("hook=b.stopping"),
      stop=_ => {
        emit("hook=b.stop")
        if scenario is SlowStop {
          emit("slow")
          @async.sleep(60000)
          emit("b.stop.end")
        }
      },
      stopped=_ => emit("hook=b.stopped"),
    )
    |> @hosting.build(_ => ())
  @hosting_console.run(host, ctx => {
    match scenario {
      Clean => emit("command")
      Help | Version => emit("command must not run")
      Output => write_output()
      Wait | SlowStop | OutputAfterSignal | Linger => {
        emit("ready")
        @async.sleep(60000)
        emit("command must be cancelled")
      }
      Poll => {
        emit("ready")
        let count = Ref(0UL)
        while !ctx.cancelled() {
          count.val = count.val + 1UL
        }
        // The stop request cancelled this task, so the next write would end
        // with cancellation. A stop hook writes the result.
        polled.val = true
      }
      Spin => {
        emit("ready")
        let count = Ref(0UL)
        while true {
          count.val = count.val + 1UL
        }
      }
    }
  }, signals?, finalize?)
}

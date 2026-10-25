///|
// Group 11 connects signal requests. Remove when the console driver constructs Signal.
#warnings("-6")
priv enum StopRequest {
  Requested
  Signal(SignalKind)
}

///|
priv enum Phase {
  Starting
  Start
  Started
  Stopping
  Stop
  Stopped
} derive(Eq, Debug)

///|
priv enum Event {
  Started
  Stopping
  Stopped
} derive(Eq, Debug)

///|
/// Only Engine::start makes a reference, from a service's registration index.
priv struct ServiceRef {
  index : Int
} derive(Eq, Debug)

///|
// Eq and Debug support white-box laws only. Remove when a driver uses them.
#warnings("-1")
priv enum Action {
  Hook(ServiceRef, Phase)
  RunCommand
  Raise(Event)
} derive(Eq, Debug)

///|
// wasm drivers arrive in group 13. Remove when they consume both steps.
#warnings("-6")
priv enum Step {
  Run(Pending, Action)
  Finish(RunOutcome)
}

///|
/// Marking a service is internal work, so absent hooks produce no driver step.
priv enum Instruction {
  Emit(Action)
  MarkStarted(ServiceRef)
}

///|
priv enum EnginePhase {
  Starting
  Command
  Stopping
  Finished(RunOutcome)
}

///|
priv struct Engine {
  instructions : Array[Instruction]
  stop_at : Int
  stopped_at : Int
  started : Array[Bool]
  failures : Array[Error]
  mut position : Int
  mut phase : EnginePhase
  mut reason : StopReason?
  mut requested_code : ExitCode?
  mut signal : SignalKind?
  mut stop_requested : Bool
  mut timed_out : Bool
}

///|
/// The cached reply belongs to this token, even after later tokens advance.
priv struct Pending {
  engine : Engine
  action : Action
  mut reply : Step?
}

///|
fn[S] HostedService::hook(self : HostedService[S], phase : Phase) -> Hook[S]? {
  match phase {
    Starting => self.starting
    Start => self.start
    Started => self.started
    Stopping => self.stopping
    Stop => self.stop
    Stopped => self.stopped
  }
}

///|
// The wasm drivers arrive in group 13. Remove when they call this method.
#warnings("-1")
fn[S] Engine::start(services : Array[HostedService[S]]) -> Step {
  let instructions = []
  for phase in [Phase::Starting, Start, Started] {
    for index, service in services {
      let reference = ServiceRef::{ index }
      if service.hook(phase) is Some(_) {
        instructions.push(Emit(Hook(reference, phase)))
      }
      if phase == Starting && service.start is None {
        instructions.push(MarkStarted(reference))
      }
      if phase == Start && service.start is Some(_) {
        instructions.push(MarkStarted(reference))
      }
    }
  }
  instructions.push(Emit(Raise(Started)))
  instructions.push(Emit(RunCommand))
  let stop_at = instructions.length()
  instructions.push(Emit(Raise(Stopping)))
  for phase in [Phase::Stopping, Stop, Stopped] {
    for index = services.length() - 1; index >= 0; index = index - 1 {
      if services[index].hook(phase) is Some(_) {
        instructions.push(Emit(Hook(ServiceRef::{ index }, phase)))
      }
    }
  }
  let stopped_at = instructions.length()
  instructions.push(Emit(Raise(Stopped)))
  let engine : Engine = {
    instructions, stop_at, stopped_at, started: Array::make(services.length(), false), failures: [], position: 0,
    phase: Starting, reason: None, requested_code: None, signal: None, stop_requested: false, timed_out: false,
  }
  engine.next()
}

///|
fn Engine::next(self : Engine) -> Step {
  if self.phase is Finished(outcome) {
    return Finish(outcome)
  }
  while self.position < self.instructions.length() {
    let instruction = self.instructions[self.position]
    self.position += 1
    match instruction {
      MarkStarted(reference) => self.started[reference.index] = true
      Emit(action) => {
        match action {
          Hook(reference, Stopping | Stop | Stopped) =>
            if !self.started[reference.index] { continue }
          Raise(Stopping) => {
            self.phase = Stopping
            if self.reason is None { self.reason = Some(Completed) }
          }
          RunCommand => self.phase = Command
          _ => ()
        }
        return Run({ engine: self, action, reply: None }, action)
      }
    }
  }
  let outcome : RunOutcome = {
    exit_code: select_exit_code(self.signal, self.failures, self.timed_out, self.requested_code),
    timed_out: self.timed_out,
    failures: self.failures.copy(),
    reason: self.reason.unwrap_or(Completed),
    requested_code: self.requested_code,
    signal: self.signal,
  }
  self.phase = Finished(outcome)
  Finish(outcome)
}

///|
// The embedded driver is added in group 13. Remove when it reports interrupted or failed actions.
#warnings("-6")
priv enum ActionResult {
  Returned
  Interrupted
  Failed(Error)
}

///|
priv enum Reply {
  Done
  Failed(Error)
  StopRequested(StopRequest, ExitCode?, ActionResult, SignalKind?)
  TimedOut(@lander_core.TimeLimit, SignalKind?, ActionResult)
}

///|
fn Pending::respond(self : Pending, reply : Reply) -> Step {
  if self.reply is Some(step) { return step }
  let engine = self.engine
  match reply {
    Done => ()
    Failed(error) => {
      if self.action is Raise(_) { abort("failed reply to a Raise step") }
      engine.failures.push(error)
      match engine.phase {
        Starting => {
          if engine.reason is None { engine.reason = Some(StartFailed(error)) }
          engine.position = engine.stop_at
        }
        Command => {
          if engine.reason is None { engine.reason = Some(Failed(error)) }
        }
        _ => ()
      }
    }
    StopRequested(request, code, result, observed_signal) => {
      if result is Failed(_) && self.action is Raise(_) { abort("failed reply to a Raise step") }
      if request is Signal(signal) { engine.signal = Some(signal) }
      if observed_signal is Some(signal) { engine.signal = Some(signal) }
      if !engine.stop_requested {
        engine.stop_requested = true
        if engine.reason is None {
          engine.reason = Some(match request { Requested => Requested; Signal(kind) => Signal(kind) })
        }
        engine.requested_code = code
      }
      if result is Failed(error) { engine.failures.push(error) }
      if engine.phase is Starting {
        // The current hook succeeded. Consume its mark before skipping startup.
        if result is Returned && engine.position < engine.instructions.length() &&
          engine.instructions[engine.position] is MarkStarted(reference) &&
          self.action is Hook(current, Starting | Start) && current == reference {
          engine.started[reference.index] = true
        }
        engine.position = engine.stop_at
      }
    }
    TimedOut(limit, observed_signal, result) => {
      match engine.phase {
        Starting => abort("timed_out outside the stop phase: Starting")
        Command => abort("timed_out outside the stop phase: Command")
        Finished(_) => abort("timed_out outside the stop phase: Finished")
        Stopping => ()
      }
      if observed_signal is Some(signal) { engine.signal = Some(signal) }
      if result is Failed(error) { engine.failures.push(error) }
      engine.timed_out = true
      engine.failures.push(ShutdownTimedOut(limit))
      // A timeout while raising Stopped must not raise the event twice.
      engine.position = if engine.position > engine.stopped_at { engine.position } else { engine.stopped_at }
    }
  }
  let next = engine.next()
  self.reply = Some(next)
  next
}

///|
// The wasm drivers arrive in group 13. Remove when they call this method.
#warnings("-1")
fn Pending::done(self : Pending) -> Step { self.respond(Done) }

///|
// The wasm drivers arrive in group 13. Remove when they call this method.
#warnings("-1")
fn Pending::failed(self : Pending, error : Error) -> Step { self.respond(Failed(error)) }

///|
// The embedded driver is added in group 13. Remove when it replies to requests.
#warnings("-1")
fn Pending::stop_requested(self : Pending, request : StopRequest, code : ExitCode?, result~ : ActionResult = Returned, observed_signal? : SignalKind) -> Step {
  self.respond(StopRequested(request, code, result, observed_signal))
}

///|
// The wasm drivers arrive in group 13. Remove when they use this reply.
#warnings("-1")
fn Pending::timed_out(self : Pending, limit~ : @lander_core.TimeLimit = default_shutdown_timeout(), observed_signal? : SignalKind, result~ : ActionResult = Interrupted) -> Step { self.respond(TimedOut(limit, observed_signal, result)) }

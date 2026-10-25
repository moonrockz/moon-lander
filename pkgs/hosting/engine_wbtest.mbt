///|
suberror EngineTestError { HookFailed(Int) } derive(Debug)

///|
pub extend EngineTestError with @debug.Debug::{to_repr}

///|
fn engine_services(masks : Array[Int]) -> Array[HostedService[Unit]] raise {
  let mut host : HostBuilder[Unit] = builder(@lander_core.AppName::parse("test"), [])
  let hook : Hook[Unit] = _ => ()
  for i, mask in masks {
    host = host |> service(
      "service-\{i}",
      starting?=if (mask & 1) != 0 { Some(hook) } else { None },
      start?=if (mask & 2) != 0 { Some(hook) } else { None },
      started?=if (mask & 4) != 0 { Some(hook) } else { None },
      stopping?=if (mask & 8) != 0 { Some(hook) } else { None },
      stop?=if (mask & 16) != 0 { Some(hook) } else { None },
      stopped?=if (mask & 32) != 0 { Some(hook) } else { None },
    )
  }
  host.services
}

///|
fn action_name(action : Action) -> String {
  match action {
    Hook(reference, phase) => "\{reference.index}.\{@debug.Debug::to_repr(phase)}"
    RunCommand => "command"
    Raise(event) => "event.\{@debug.Debug::to_repr(event)}"
  }
}

///|
fn engine_trace(
  masks : Array[Int],
  reply? : (Pending, Action) -> Step = (pending, _) => pending.done(),
) -> (Array[String], RunOutcome) raise {
  let log = []
  let mut step = Engine::start(engine_services(masks))
  while step is Run(pending, action) {
    log.push(action_name(action))
    step = reply(pending, action)
    same_step(step, pending.done())
    @expect.expect(log.length() <= masks.length() * 6 + 4).to_be_true()
  }
  guard step is Finish(outcome) else { fail("expected Finish") }
  (log, outcome)
}

///|
test "engine table: phase order and absent hooks" {
  let cases : Array[(Array[Int], Array[String])] = [
    ([], ["event.Started", "command", "event.Stopping", "event.Stopped"]),
    ([0], ["event.Started", "command", "event.Stopping", "event.Stopped"]),
    ([8], ["event.Started", "command", "event.Stopping", "0.Stopping", "event.Stopped"]),
    ([1, 2, 4, 8, 16, 32], [
      "0.Starting", "1.Start", "2.Started", "event.Started", "command",
      "event.Stopping", "3.Stopping", "4.Stop", "5.Stopped", "event.Stopped",
    ]),
    ([63, 63], [
      "0.Starting", "1.Starting", "0.Start", "1.Start", "0.Started", "1.Started",
      "event.Started", "command", "event.Stopping", "1.Stopping", "0.Stopping",
      "1.Stop", "0.Stop", "1.Stopped", "0.Stopped", "event.Stopped",
    ]),
  ]
  for (masks, expected) in cases {
    let (trace, outcome) = engine_trace(masks)
    @expect.expect(trace).to_equal(expected)
    @expect.expect(outcome.exit_code()).to_equal(ExitCode::success())
    @expect.expect(outcome.reason is Completed).to_be_true()
  }
}

///|
test "engine table: failure in each start phase" {
  let cases : Array[(Phase, Array[String])] = [
    (Starting, ["0.Starting", "1.Starting", "event.Stopping", "event.Stopped"]),
    (Start, [
      "0.Starting", "1.Starting", "0.Start", "1.Start", "event.Stopping",
      "0.Stopping", "0.Stop", "0.Stopped", "event.Stopped",
    ]),
    (Started, [
      "0.Starting", "1.Starting", "0.Start", "1.Start", "0.Started", "1.Started",
      "event.Stopping", "1.Stopping", "0.Stopping", "1.Stop", "0.Stop",
      "1.Stopped", "0.Stopped", "event.Stopped",
    ]),
  ]
  for (phase, expected) in cases {
    let (trace, outcome) = engine_trace([63, 63], reply=(pending, action) => {
      if action == Hook(ServiceRef::{ index: 1 }, phase) {
        pending.failed(HookFailed(1))
      } else { pending.done() }
    })
    @expect.expect(trace).to_equal(expected)
    @expect.expect(outcome.exit_code()).to_equal(ExitCode::failure())
    @expect.expect(outcome.failures().length()).to_equal(1)
    @expect.expect(outcome.reason is StartFailed(HookFailed(1))).to_be_true()
  }
}

///|
test "no-start services are started only when their starting phase was reached" {
  let (trace, _) = engine_trace([56, 57, 56], reply=(pending, action) => {
    if action == Hook(ServiceRef::{ index: 1 }, Starting) {
      pending.failed(HookFailed(1))
    } else { pending.done() }
  })
  @expect.expect(trace).to_equal([
    "1.Starting", "event.Stopping", "0.Stopping", "0.Stop", "0.Stopped", "event.Stopped",
  ])
  let (trace, _) = engine_trace([57, 57, 56], reply=(pending, action) => {
    if action == Hook(ServiceRef::{ index: 1 }, Starting) {
      pending.failed(HookFailed(1))
    } else { pending.done() }
  })
  @expect.expect(trace).to_equal([
    "0.Starting", "1.Starting", "event.Stopping", "0.Stopping", "0.Stop", "0.Stopped", "event.Stopped",
  ])
}

///|
test "engine collects every stop failure and command failure in order" {
  let (trace, outcome) = engine_trace([63, 63], reply=(pending, action) => {
    match action {
      Hook(reference, Stopping | Stop | Stopped) => pending.failed(HookFailed(reference.index))
      RunCommand => pending.failed(HookFailed(2))
      _ => pending.done()
    }
  })
  @expect.expect(trace.length()).to_equal(16)
  @expect.expect(outcome.exit_code()).to_equal(ExitCode::failure())
  @expect.expect(outcome.failures().map(error => match error {
    HookFailed(index) => index
    _ => -1
  })).to_equal([2, 1, 0, 1, 0, 1, 0])
  @expect.expect(outcome.reason is Failed(HookFailed(2))).to_be_true()
}

///|
test "engine table: stop requests in every phase complete the current action" {
  let code = ExitCode::from_int(4)
  let cases : Array[(Action, Array[String])] = [
    (Hook(ServiceRef::{ index: 0 }, Starting), [
      "0.Starting", "event.Stopping", "event.Stopped",
    ]),
    (Hook(ServiceRef::{ index: 0 }, Start), [
      "0.Starting", "1.Starting", "0.Start", "event.Stopping",
      "0.Stopping", "0.Stop", "0.Stopped", "event.Stopped",
    ]),
    (Hook(ServiceRef::{ index: 0 }, Started), [
      "0.Starting", "1.Starting", "0.Start", "1.Start", "0.Started", "event.Stopping",
      "1.Stopping", "0.Stopping", "1.Stop", "0.Stop", "1.Stopped", "0.Stopped", "event.Stopped",
    ]),
  ]
  for (target, expected) in cases {
    let (trace, outcome) = engine_trace([63, 63], reply=(pending, action) => {
      if action == target { pending.stop_requested(Requested, Some(code)) }
      else { pending.done() }
    })
    @expect.expect(trace).to_equal(expected)
    @expect.expect(outcome.exit_code()).to_equal(code)
    @expect.expect(outcome.requested_code).to_equal(Some(code))
    @expect.expect(outcome.reason is Requested).to_be_true()
  }
  let (clean, _) = engine_trace([63, 63])
  for target in [Action::RunCommand, Raise(Started), Raise(Stopping), Raise(Stopped),
    Hook(ServiceRef::{ index: 1 }, Stopping), Hook(ServiceRef::{ index: 1 }, Stop),
    Hook(ServiceRef::{ index: 1 }, Stopped)] {
    let (trace, outcome) = engine_trace([63, 63], reply=(pending, action) => {
      if action == target { pending.stop_requested(Requested, Some(code)) }
      else { pending.done() }
    })
    @expect.expect(trace).to_equal(if target == Raise(Started) {
      clean.filter(name => name != "command")
    } else { clean })
    @expect.expect(outcome.requested_code).to_equal(Some(code))
    @expect.expect(outcome.exit_code()).to_equal(code)
    @expect.expect(match target {
      RunCommand | Raise(Started) => outcome.reason is Requested
      _ => outcome.reason is Completed
    }).to_be_true()
  }
}

///|
test "stop during no-start starting counts the current service as started" {
  let (trace, _) = engine_trace([57, 56], reply=(pending, _) => {
    if pending.action == Hook(ServiceRef::{ index: 0 }, Starting) {
      pending.stop_requested(Requested, None)
    } else { pending.done() }
  })
  @expect.expect(trace).to_equal([
    "0.Starting", "event.Stopping", "0.Stopping", "0.Stop", "0.Stopped", "event.Stopped",
  ])
}

///|
test "engine table: timeout skips remaining stop hooks and preserves requested code" {
  for target in [Action::Raise(Stopping), Hook(ServiceRef::{ index: 1 }, Stopping),
    Hook(ServiceRef::{ index: 1 }, Stop), Hook(ServiceRef::{ index: 1 }, Stopped), Raise(Stopped)] {
    let code = ExitCode::from_int(4)
    let (trace, outcome) = engine_trace([63, 63], reply=(pending, action) => {
      if action == RunCommand { pending.stop_requested(Requested, Some(code)) }
      else if action == target { pending.timed_out(limit=default_shutdown_timeout()) }
      else { pending.done() }
    })
    let (clean, _) = engine_trace([63, 63])
    let expected = []
    for name in clean {
      expected.push(name)
      if name == action_name(target) { break }
    }
    if target != Raise(Stopped) { expected.push("event.Stopped") }
    @expect.expect(trace).to_equal(expected)
    @expect.expect(outcome.exit_code()).to_equal(ExitCode::failure())
    @expect.expect(outcome.requested_code).to_equal(Some(code))
    @expect.expect(outcome.reason is Requested).to_be_true()
    @expect.expect(outcome.failures().length()).to_equal(1)
    @expect.expect(outcome.failures()[0] is ShutdownTimedOut(limit) && limit == default_shutdown_timeout()).to_be_true()
  }
}

///|
test "engine law: timeout records the current failure before the limit and keeps a signal code" {
  let limit = @lander_core.TimeLimit::millis(1000)
  let error : Error = HookFailed(7)
  let (_, result) = engine_trace([63], reply=(pending, action) => {
    if action == Hook(ServiceRef::{ index: 0 }, Stop) {
      pending.timed_out(limit~, observed_signal=Terminate, result=Failed(error))
    } else { pending.done() }
  })
  @expect.expect(result.failures().length()).to_equal(2)
  @expect.expect(physical_equal(result.failures()[0], error)).to_be_true()
  @expect.expect(result.failures()[1] is ShutdownTimedOut(actual) && actual == limit).to_be_true()
  @expect.expect(result.timed_out).to_be_true()
  @expect.expect(result.exit_code().to_int()).to_equal(143)
}

///|
fn same_step(left : Step, right : Step) -> Unit raise {
  match (left, right) {
    (Run(a, action_a), Run(b, action_b)) => {
      @expect.expect(physical_equal(a, b)).to_be_true()
      @expect.expect(action_a).to_equal(action_b)
    }
    (Finish(a), Finish(b)) => @expect.expect(physical_equal(a, b)).to_be_true()
    _ => fail("a repeated reply changed the step")
  }
}

///|
/// An independent model builds the expected trace from each service's hook and
/// failure choices. It does not use the engine's instructions or started set.
test "law: random hooks and failures preserve cleanup, Finish and token replies" {
  let reached_command = Ref(0)
  let stop_failure_after_clean_start = Ref(0)
  @expect.for_all(
    (input : (Array[UInt], (UInt?, UInt?, UInt?, UInt?, UInt?, UInt?), Bool)) => {
      let choices = input.0
      let masks = choices.map(value => (value & 63).reinterpret_as_int())
      let failure_indices = [input.1.0, input.1.1, input.1.2, input.1.3, input.1.4, input.1.5]
        .map(index => if choices.is_empty() { None } else {
          match index {
            Some(value) if (value & 1) == 1 =>
              Some(((value >> 1) % choices.length().reinterpret_as_uint()).reinterpret_as_int())
            _ => None
          }
        })
      let expected = []
      let started = Array::make(choices.length(), false)
      let mut start_failed = false
      let mut failure_count = 0
      for phase_index = 0; phase_index < 3; phase_index = phase_index + 1 {
        if start_failed { break }
        for i, choice in choices {
          if (choice & (1U << phase_index)) != 0 {
            expected.push("\{i}.\{["Starting", "Start", "Started"][phase_index]}")
            if failure_indices[phase_index] == Some(i) {
              start_failed = true
              failure_count += 1
              break
            }
          }
          if (phase_index == 0 && (choice & 2) == 0) || phase_index == 1 {
            started[i] = true
          }
        }
      }
      if !start_failed {
        expected.push("event.Started")
        expected.push("command")
        if input.2 { failure_count += 1 }
      }
      let start_failure_count = failure_count
      if !start_failed { reached_command.val += 1 }
      expected.push("event.Stopping")
      for phase_index = 3; phase_index < 6; phase_index = phase_index + 1 {
        for i = choices.length() - 1; i >= 0; i = i - 1 {
          if started[i] && (choices[i] & (1U << phase_index)) != 0 {
            expected.push("\{i}.\{["Stopping", "Stop", "Stopped"][phase_index - 3]}")
            if failure_indices[phase_index] == Some(i) { failure_count += 1 }
          }
        }
      }
      expected.push("event.Stopped")
      if !start_failed && failure_count > start_failure_count { stop_failure_after_clean_start.val += 1 }
      let mut step = Engine::start(engine_services(masks))
      let actual = []
      let tokens : Array[(Pending, Step)] = []
      let mut last_engine : Engine? = None
      while step is Run(pending, action) {
        let engine = pending.engine
        last_engine = Some(engine)
        actual.push(action_name(action))
        @expect.expect(actual.length() <= choices.length() * 6 + 4).to_be_true()
        step = match action {
          Hook(reference, phase) => {
            let phase_index = match phase {
              Starting => 0
              Start => 1
              Started => 2
              Stopping => 3
              Stop => 4
              Stopped => 5
            }
            if failure_indices[phase_index] == Some(reference.index) {
              pending.failed(HookFailed(reference.index))
            } else { pending.done() }
          }
          RunCommand => if input.2 { pending.failed(HookFailed(-1)) } else { pending.done() }
          _ => pending.done()
        }
        let snapshot = EngineSnapshot::take(engine)
        same_step(step, pending.done())
        same_step(step, pending.failed(HookFailed(-2)))
        same_step(step, pending.stop_requested(Requested, Some(ExitCode::failure())))
        same_step(step, pending.timed_out(limit=default_shutdown_timeout()))
        snapshot.check(engine)
        tokens.push((pending, step))
      }
      @expect.expect(actual).to_equal(expected)
      guard step is Finish(outcome) else { fail("expected Finish") }
      @expect.expect(outcome.failures().length()).to_equal(failure_count)
      @expect.expect(outcome.exit_code()).to_equal(if failure_count == 0 {
        ExitCode::success()
      } else { ExitCode::failure() })
      guard last_engine is Some(engine) else { fail("missing engine") }
      same_step(step, engine.next())
      let snapshot = EngineSnapshot::take(engine)
      for (pending, cached) in tokens {
        same_step(cached, pending.done())
        same_step(cached, pending.failed(HookFailed(-2)))
        same_step(cached, pending.stop_requested(Requested, Some(ExitCode::failure())))
        same_step(cached, pending.timed_out(limit=default_shutdown_timeout()))
        snapshot.check(engine)
      }
      same_step(step, engine.next())
    },
    count=300,
    max_size=25,
    max_shrinks=100,
    seed=7303,
  )
  // Seed 7303, 300 cases: 192 reach command; 52 have stop failures after clean start.
  @expect.expect(reached_command.val >= 180).to_be_true()
  @expect.expect(stop_failure_after_clean_start.val >= 40).to_be_true()
}

///|
test "a start-phase stop request never marks a later no-start service" {
  for masks in [[63, 56], [7, 56]] {
    let (trace, _) = engine_trace(masks, reply=(pending, action) => {
      if action == Hook(ServiceRef::{ index: 0 }, Starting) {
        pending.stop_requested(Requested, None)
      } else { pending.done() }
    })
    @expect.expect(trace).to_equal(["0.Starting", "event.Stopping", "event.Stopped"])
  }
}

///|
priv struct EngineSnapshot {
  started : Array[Bool]
  reason : StopReason?
  requested_code : ExitCode?
  stop_requested : Bool
  signal : SignalKind?
  timed_out : Bool
  position : Int
  phase : EnginePhase
  failures : Array[Error]
}

///|
fn EngineSnapshot::take(engine : Engine) -> EngineSnapshot {
  { started: engine.started.copy(), reason: engine.reason,
    requested_code: engine.requested_code, signal: engine.signal, stop_requested: engine.stop_requested,
    timed_out: engine.timed_out, position: engine.position, phase: engine.phase,
    failures: engine.failures.copy() }
}

///|
fn EngineSnapshot::check(self : EngineSnapshot, engine : Engine) -> Unit raise {
  @expect.expect(engine.started).to_equal(self.started)
  @expect.expect(physical_equal(engine.reason, self.reason)).to_be_true()
  @expect.expect(engine.requested_code).to_equal(self.requested_code)
  @expect.expect(engine.stop_requested).to_equal(self.stop_requested)
  @expect.expect(engine.signal).to_equal(self.signal)
  @expect.expect(engine.timed_out).to_equal(self.timed_out)
  @expect.expect(engine.position).to_equal(self.position)
  @expect.expect(physical_equal(engine.phase, self.phase)).to_be_true()
  @expect.expect(engine.failures.length()).to_equal(self.failures.length())
  for i, error in engine.failures {
    @expect.expect(physical_equal(error, self.failures[i])).to_be_true()
  }
}

///|
test "engine table: first stop request keeps its code and any existing reason" {
  let first_code = ExitCode::from_int(4)
  let second_code = ExitCode::from_int(5)
  for first in [Action::Hook(ServiceRef::{ index: 0 }, Start), RunCommand,
    Raise(Stopping), Hook(ServiceRef::{ index: 0 }, Stopping)] {
    for code in [None, Some(first_code)] {
      let (_, outcome) = engine_trace([63], reply=(pending, action) => {
        if action == first { pending.stop_requested(Requested, code) }
        else if action == Hook(ServiceRef::{ index: 0 }, Stop) {
          pending.stop_requested(Requested, Some(second_code))
        } else { pending.done() }
      })
      @expect.expect(match first {
        Hook(_, Start) | RunCommand => outcome.reason is Requested
        _ => outcome.reason is Completed
      }).to_be_true()
      @expect.expect(outcome.requested_code).to_equal(code)
      @expect.expect(outcome.exit_code()).to_equal(code.unwrap_or(ExitCode::success()))
    }
  }
}

///|
test "engine table: stop requests preserve the reason throughout stop hooks" {
  let first_code = ExitCode::from_int(4)
  let second_code = ExitCode::from_int(5)
  let cases : Array[(Action?, (StopReason?) -> Bool)] = [
    (None, reason => reason is Some(Completed)),
    (Some(Hook(ServiceRef::{ index: 1 }, Start)), reason => reason is Some(StartFailed(HookFailed(1)))),
    (Some(RunCommand), reason => reason is Some(Failed(HookFailed(1)))),
  ]
  for (failure, has_expected_reason) in cases {
    let reasons = []
    let (_, outcome) = engine_trace([63, 63], reply=(pending, action) => {
      match action {
        Hook(_, Stopping | Stop | Stopped) => {
          reasons.push(pending.engine.reason)
          pending.stop_requested(Requested, Some(if reasons.length() == 1 {
            first_code
          } else { second_code }))
        }
        _ => if failure == Some(action) { pending.failed(HookFailed(1)) }
        else { pending.done() }
      }
    })
    @expect.expect(reasons.length()).to_equal(if failure is Some(Hook(_, Start)) { 3 } else { 6 })
    for reason in reasons {
      @expect.expect(has_expected_reason(reason)).to_be_true()
    }
    @expect.expect(has_expected_reason(Some(outcome.reason))).to_be_true()
    @expect.expect(outcome.requested_code).to_equal(Some(first_code))
    @expect.expect(outcome.exit_code()).to_equal(if failure is None { first_code } else { ExitCode::failure() })
    @expect.expect(outcome.failures().length()).to_equal(if failure is None { 0 } else { 1 })
  }
}

///|
test "started event stop request skips command" {
  let (trace, outcome) = engine_trace([63], reply=(pending, action) => {
    if action == Raise(Started) { pending.stop_requested(Requested, None) }
    else { pending.done() }
  })
  @expect.expect(trace).to_equal([
    "0.Starting", "0.Start", "0.Started", "event.Started", "event.Stopping",
    "0.Stopping", "0.Stop", "0.Stopped", "event.Stopped",
  ])
  @expect.expect(outcome.reason is Requested).to_be_true()
}

///|
test "panic timed_out in Starting is a driver fault" {
  guard Engine::start(engine_services([2])) is Run(pending, _) else { fail("missing start") }
  ignore(pending.timed_out(limit=default_shutdown_timeout()))
}

///|
test "panic timed_out in Command is a driver fault" {
  guard Engine::start(engine_services([])) is Run(started, _) else { fail("missing Started") }
  guard started.done() is Run(command, _) else { fail("missing command") }
  ignore(command.timed_out(limit=default_shutdown_timeout()))
}

///|
test "panic failed on Raise Started is a driver fault" {
  guard Engine::start(engine_services([])) is Run(pending, _) else { fail("missing Started") }
  ignore(pending.failed(HookFailed(0)))
}

///|
test "panic failed on Raise Stopping is a driver fault" {
  guard Engine::start(engine_services([])) is Run(started, _) else { fail("missing Started") }
  guard started.done() is Run(command, _) else { fail("missing command") }
  guard command.done() is Run(stopping, _) else { fail("missing Stopping") }
  ignore(stopping.failed(HookFailed(0)))
}

///|
test "panic failed on Raise Stopped is a driver fault" {
  guard Engine::start(engine_services([])) is Run(started, _) else { fail("missing Started") }
  guard started.done() is Run(command, _) else { fail("missing command") }
  guard command.done() is Run(stopping, _) else { fail("missing Stopping") }
  guard stopping.done() is Run(stopped, _) else { fail("missing Stopped") }
  ignore(stopped.failed(HookFailed(0)))
}

///|
test "signal requests record identity after a reason without replacing reason or requested code" {
  let first = ExitCode::from_int(4)
  let second = ExitCode::from_int(9)
  for signal in [SignalKind::Interrupt, Terminate, Quit] {
    for failed in [false, true] {
      let (_, result) = engine_trace([63], reply=(pending, action) => {
        match action {
          RunCommand => if failed { pending.failed(HookFailed(0)) }
            else { pending.stop_requested(Requested, Some(first)) }
          Hook(_, Stop) => pending.stop_requested(Signal(signal), Some(second))
          _ => pending.done()
        }
      })
      @expect.expect(result.signal).to_equal(Some(signal))
      @expect.expect(result.exit_code()).to_equal(signal.exit_code())
      @expect.expect(if failed { result.reason is Failed(HookFailed(0)) } else { result.reason is Requested }).to_be_true()
      @expect.expect(result.requested_code).to_equal(if failed { Some(second) } else { Some(first) })
    }
    let (_, result) = engine_trace([], reply=(pending, action) => {
      if action == RunCommand { pending.stop_requested(Signal(signal), None) }
      else { pending.done() }
    })
    @expect.expect(match result.reason { Signal(found) => found == signal; _ => false }).to_be_true()
    @expect.expect(result.signal).to_equal(Some(signal))
    @expect.expect(result.exit_code()).to_equal(signal.exit_code())
  }
}

///|
test "request then failure counts failure and follows the failed-start marking rule" {
  for target in [Phase::Starting, Start, Started] {
    let (trace, result) = engine_trace([63, 63], reply=(pending, action) => {
      if action == Hook(ServiceRef::{ index: 0 }, target) {
        pending.stop_requested(Requested, None, result=Failed(HookFailed(0)))
      } else { pending.done() }
    })
    @expect.expect(result.reason is Requested).to_be_true()
    @expect.expect(result.failures().length()).to_equal(1)
    @expect.expect(result.exit_code()).to_equal(ExitCode::failure())
    @expect.expect(trace.contains("0.Stop")).to_equal(target == Started)
    @expect.expect(trace.contains("command")).to_be_false()
  }
}

///|
/// Extend the hook/failure laws with a request at any emitted step, including a
/// request followed by failure. The model below has no engine instructions.
test "law: requests from any step preserve cleanup and single-use reply effects" {
  @expect.for_all((input : (Array[UInt], UInt, UInt, UInt)) => {
    let masks = input.0.map(value => (value & 63).reinterpret_as_int())
    let target = (input.1 % (masks.length() * 6 + 4).reinterpret_as_uint()).reinterpret_as_int()
    let code = ExitCode::from_int((input.3 % 256).reinterpret_as_int()) catch { _ => abort("code in range") }
    let expected : Array[Action] = []
    let started = Array::make(masks.length(), false)
    let mut ended = false
    let mut failures = 0
    let expected_reason : Ref[StopReason?] = Ref(None)
    let emit = (action : Action) => {
      let index = expected.length()
      expected.push(action)
      let request = index >= target
      let failure = match action {
        Raise(_) => false
        _ => ((input.2 >> (index % 32)) & 1) != 0
      }
      if failure { failures += 1 }
      if expected_reason.val is None {
        expected_reason.val = if request { Some(Requested) }
          else { match action {
            Hook(_, Starting | Start | Started) if failure => Some(StartFailed(HookFailed(index)))
            RunCommand => Some(if failure { Failed(HookFailed(index)) } else { Completed })
            _ => None
          } }
      }
      let interrupted = request && !failure && (input.1 & 0x80000000U) != 0 && !(action is Raise(_))
      (request, failure, interrupted)
    }
    for phase_index, phase in [Phase::Starting, Start, Started] {
      if ended { break }
      for i, mask in masks {
        let mut requested = false
        if (mask & (1 << phase_index)) != 0 {
          let (request, failure, interrupted) = emit(Hook(ServiceRef::{ index: i }, phase))
          requested = request
          if failure || interrupted { ended = true; break }
        }
        if (phase == Starting && (mask & 2) == 0) || (phase == Start && (mask & 2) != 0) { started[i] = true }
        if requested { ended = true; break }
      }
    }
    if !ended { let (request, _, _) = emit(Raise(Started)); ended = request }
    if !ended { ignore(emit(RunCommand)) }
    ignore(emit(Raise(Stopping)))
    for phase_index, phase in [Phase::Stopping, Stop, Stopped] {
      for i = masks.length() - 1; i >= 0; i = i - 1 {
        if started[i] && (masks[i] & (8 << phase_index)) != 0 { ignore(emit(Hook(ServiceRef::{ index: i }, phase))) }
      }
    }
    ignore(emit(Raise(Stopped)))
    let actual = []
    let tokens = []
    let mut step = Engine::start(engine_services(masks))
    let mut last : Engine? = None
    while step is Run(pending, action) {
      let index = actual.length()
      actual.push(action)
      let error : Error? = match action {
        Raise(_) => None
        _ => if ((input.2 >> (index % 32)) & 1) != 0 { Some(HookFailed(index)) } else { None }
      }
      let interrupted = (input.1 & 0x80000000U) != 0 && !(action is Raise(_))
      step = if index >= target {
        pending.stop_requested(Requested, Some(code), result=match error { Some(error) => Failed(error); None => if interrupted { Interrupted } else { Returned } })
      } else if error is Some(error) { pending.failed(error) }
      else { pending.done() }
      tokens.push((pending, step))
      last = Some(pending.engine)
    }
    @expect.expect(actual).to_equal(expected)
    guard step is Finish(result) else { fail("expected Finish") }
    @expect.expect(result.failures().length()).to_equal(failures)
    @expect.expect(match (expected_reason.val.unwrap(), result.reason) {
      (Requested, Requested) | (Completed, Completed) => true
      (StartFailed(HookFailed(expected)), StartFailed(HookFailed(actual))) => expected == actual
      (Failed(HookFailed(expected)), Failed(HookFailed(actual))) => expected == actual
      _ => false
    }).to_be_true()
    let requested_code = if target < expected.length() { Some(code) } else { None }
    @expect.expect(result.requested_code).to_equal(requested_code)
    @expect.expect(result.exit_code()).to_equal(if failures == 0 { requested_code.unwrap_or(ExitCode::success()) } else { ExitCode::failure() })
    let engine = last.unwrap()
    let snapshot = EngineSnapshot::take(engine)
    same_step(step, engine.next())
    for (pending, cached) in tokens {
      same_step(cached, pending.done())
      same_step(cached, pending.failed(HookFailed(-1)))
      same_step(cached, pending.stop_requested(Signal(Quit), Some(ExitCode::failure()), result=Failed(HookFailed(-1))))
      same_step(cached, pending.timed_out(limit=default_shutdown_timeout()))
      snapshot.check(engine)
    }
  }, count=300, max_size=25, seed=7404)
}

///|
test "an interrupted startup hook does not mark its service as started" {
  for masks in [[57, 56], [63, 63]] {
    for phase in [Phase::Starting, Start, Started] {
      if masks[0] == 57 && phase != Starting { continue }
      let (trace, result) = engine_trace(masks, reply=(pending, action) => {
        if action == Hook(ServiceRef::{ index: 0 }, phase) {
          pending.stop_requested(Requested, None, result=Interrupted)
        } else { pending.done() }
      })
      @expect.expect(trace.contains("0.Stop")).to_equal(phase == Started)
      @expect.expect(result.reason is Requested).to_be_true()
      @expect.expect(result.failures().length()).to_equal(0)
      @expect.expect(result.exit_code()).to_equal(ExitCode::success())
    }
  }
}

///|
test "panic failed on Raise with a stop request is a driver fault" {
  guard Engine::start(engine_services([])) is Run(pending, _) else { fail("missing Started") }
  ignore(pending.stop_requested(Requested, None, result=Failed(HookFailed(0))))
}

///|
test "a later signal observed in one reply keeps the first request reason and code" {
  let code = ExitCode::from_int(4)
  let (_, result) = engine_trace([], reply=(pending, action) => {
    if action == RunCommand {
      pending.stop_requested(Requested, Some(code), observed_signal=Quit)
    } else { pending.done() }
  })
  @expect.expect(result.reason is Requested).to_be_true()
  @expect.expect(result.signal).to_equal(Some(Quit))
  @expect.expect(result.exit_code()).to_equal(SignalKind::Quit.exit_code())
  @expect.expect(result.requested_code).to_equal(Some(code))
}

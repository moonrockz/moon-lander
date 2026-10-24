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
    if target == RunCommand || target == Raise(Started) {
      @expect.expect(outcome.reason is Requested).to_be_true()
    } else { @expect.expect(outcome.reason is Completed).to_be_true() }
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
      else if action == target { pending.timed_out() }
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
  }
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
  @expect.for_all(
    (input : (Array[UInt], Bool)) => {
      let choices = input.0
      let masks = choices.map(value => (value & 63).reinterpret_as_int())
      let expected = []
      let started = Array::make(choices.length(), false)
      let mut start_failed = false
      let mut failure_count = 0
      for phase_index = 0; phase_index < 3; phase_index = phase_index + 1 {
        if start_failed { break }
        for i, choice in choices {
          if (choice & (1U << phase_index)) != 0 {
            expected.push("\{i}.\{["Starting", "Start", "Started"][phase_index]}")
            if (choice & (64U << phase_index)) != 0 {
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
        if input.1 { failure_count += 1 }
      }
      expected.push("event.Stopping")
      for phase_index = 3; phase_index < 6; phase_index = phase_index + 1 {
        for i = choices.length() - 1; i >= 0; i = i - 1 {
          if started[i] && (choices[i] & (1U << phase_index)) != 0 {
            expected.push("\{i}.\{["Stopping", "Stop", "Stopped"][phase_index - 3]}")
            if (choices[i] & (64U << phase_index)) != 0 { failure_count += 1 }
          }
        }
      }
      expected.push("event.Stopped")
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
            if (choices[reference.index] & (64U << phase_index)) != 0 {
              pending.failed(HookFailed(reference.index))
            } else { pending.done() }
          }
          RunCommand => if input.1 { pending.failed(HookFailed(-1)) } else { pending.done() }
          _ => pending.done()
        }
        let position = engine.position
        let failures = engine.failures.length()
        same_step(step, pending.done())
        same_step(step, pending.failed(HookFailed(-2)))
        same_step(step, pending.stop_requested(Requested, Some(ExitCode::failure())))
        same_step(step, pending.timed_out())
        @expect.expect(engine.position).to_equal(position)
        @expect.expect(engine.failures.length()).to_equal(failures)
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
      for (pending, cached) in tokens { same_step(cached, pending.done()) }
      same_step(step, engine.next())
    },
    count=300,
    max_size=25,
    max_shrinks=100,
    seed=7303,
  )
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

///|
/// Call from a later JS turn, outside any MoonBit coroutine.
extern "js" fn foreign_probe(read : () -> Bool) -> @js_async.Promise[Bool] =
  #|read => new Promise((resolve, reject) => setTimeout(() => {
  #|  try { resolve(read()); } catch (error) { reject(error); }
  #|}, 0))

///|
async test "a real foreign callback polls an idle hosted lifetime" {
  let outcome = builder(@lander_core.AppName::parse("foreign-probe"), [])
    |> build(_ => ())
    |> run(ctx => {
      assert_false(foreign_probe(() => ctx.stop_requested() || ctx.lifetime.stop_requested() || ctx.lifetime.stop_token().stop_requested()).wait())
    })
  assert_true(outcome.stop_reason() is Completed)
}

///|
async test "a foreign callback polls a parent signal without yielding" {
  let signal : Ref[SignalKind?] = Ref(None)
  let observed = []
  let outcome = builder(@lander_core.AppName::parse("foreign-signal"), [])
    |> build(_ => ())
    |> run(signals=SignalProbe::new(() => signal.val), ctx => {
      ignore(foreign_probe(() => {
        // The watcher cannot run between publication and these synchronous reads.
        signal.val = Some(Terminate)
        observed.push(ctx.stop_requested())
        observed.push(ctx.lifetime.stop_requested())
        observed.push(ctx.lifetime.stop_token().stop_requested())
        true
      }).wait())
    })
  assert_eq(observed, [true, true, true])
  assert_true(outcome.stop_reason() is Signal(Terminate))
  assert_eq(outcome.exit_code().to_int(), 143)
  assert_eq(outcome.failures().length(), 0)
}

///|
async test "a foreign callback keeps a request reason and observes later signal precedence" {
  for with_signal in [false, true] {
    let signal : Ref[SignalKind?] = Ref(None)
    let observed = []
    let code = ExitCode::from_int(7)
    let outcome = builder(@lander_core.AppName::parse("foreign-request"), [])
      |> build(_ => ())
      |> run(signals=SignalProbe::new(() => signal.val), ctx => {
        ignore(foreign_probe(() => {
          ctx.lifetime.stop_application(exit_code=code)
          observed.push(ctx.stop_requested())
          if with_signal { signal.val = Some(Interrupt) }
          observed.push(ctx.lifetime.stop_requested())
          observed.push(ctx.lifetime.stop_token().stop_requested())
          true
        }).wait())
      })
    assert_eq(observed, [true, true, true])
    assert_true(outcome.stop_reason() is Requested)
    assert_eq(outcome.exit_code().to_int(), if with_signal { 130 } else { 7 })
    assert_eq(outcome.failures().length(), 0)
  }
}

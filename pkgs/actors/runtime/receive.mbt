///|
/// What a state handler gives after one message.
pub(all) enum Next[S] {
  /// Process the next message with this state.
  Continue(S)
  /// End the loop. A `start` actor ends normally and discards its queued
  /// messages.
  Stop
}

///|
/// An immutable description of what an actor receives next and of its result
/// `R`. Only the actor runtime and the test runner run it, so no other code
/// can take a message from a mailbox.
///
/// Internally a receive is a function from "what to do with the result" to a
/// step machine that has no result type. Each step returns to the runner, so
/// the call stack does not grow with the number of steps, joins or loop
/// iterations, and the type parameters stay in closures with no cast.
pub struct Receive[M, R] {
  priv steps : ((R) -> Step[M]) -> Step[M]
}

///|
/// The step machine of this receive, with `k` as what to do with the result.
fn[M, R] Receive::build(self : Receive[M, R], k : (R) -> Step[M]) -> Step[M] {
  (self.steps)(k)
}

///|
/// One state of the step machine of a receive. The runner runs it.
priv enum Step[M] {
  /// The final continuation ran. The runner stops.
  Done
  /// Call the function and continue with its step. This returns control to
  /// the runner between two steps.
  Bounce(() -> Step[M])
  /// Take the oldest message that the selector accepts.
  Take(Take[M])
  /// Run async work, then continue with its step.
  Work(async () -> Step[M])
  /// Call the handler for each message until it gives a step or the mailbox
  /// closes.
  Repeat(Repeat[M])
  /// Push a frame, then continue with the body.
  Enter(Frame[M], () -> Step[M])
  /// Pop the top frame, then continue.
  Leave(() -> Step[M])
}

///|
/// A receive of one message.
priv struct Take[M] {
  /// The continuation for a message that the receive accepts, or `None`.
  choose : (M) -> (() -> Step[M])? raise
  /// For a poll: the continuation when no message is queued.
  on_empty : (() -> Step[M])?
}

///|
/// A loop as one node: the runner calls `handle` for each message.
priv struct Repeat[M] {
  /// The next step when the loop ends, or `None` to take the next message.
  handle : async (M) -> Step[M]?
  /// The next step when the mailbox closes while the loop waits.
  finish : () -> Step[M]
}

///|
/// A frame of the runner's frame stack. A frame covers the steps of one
/// receive and ends at its `Leave`, or when the runner unwinds to it.
priv enum Frame[M] {
  /// An ordinary error of a step continues with this function.
  Recover((Error) -> Step[M])
  /// A wait that passes the time limit continues with `on_timeout`.
  Deadline(@lander_core.TimeLimit, () -> Step[M])
  /// A wait on a closed mailbox continues with this function.
  OnClosed(() -> Step[M])
}

///|
/// The oldest message. The receive waits when the mailbox is empty.
pub fn[M] receive() -> Receive[M, M] {
  { steps: k => Take({ choose: message => Some(() => k(message)), on_empty: None }) }
}

///|
/// The value of the oldest message for which `choose` gives a value. The
/// other messages stay queued in their order and count against the capacity.
/// When `choose` raises, the message stays queued and the error goes to the
/// nearest `recover`, or fails the actor.
pub fn[M, T] select(choose : (M) -> T? raise?) -> Receive[M, T] {
  let choose = lift_selector(choose)
  {
    steps: k => Take({
      choose: message => match choose(message) {
        Some(value) => Some(() => k(value))
        None => None
      },
      on_empty: None,
    }),
  }
}

///|
/// Give `select` the error effect `raise`. The pinned compiler fails to link an
/// async function that calls a `raise?` parameter (moonbitlang/moonbit-docs#1340,
/// bead lander-25h.10), so the runner calls this synchronous wrapper instead.
/// Remove it when a pinned compiler fixes the crash.
fn[M, T] lift_selector(choose : (M) -> T? raise?) -> (M) -> T? raise {
  message => choose(message)
}

///|
/// The result `value`, with no receive.
pub fn[M, R] done(value : R) -> Receive[M, R] {
  { steps: k => direct(() => k(value)) }
}

///|
/// The oldest message, or the receive of `on_empty()` at once when no message
/// is queued. On a closed empty mailbox the poll continues as a closed
/// receive, not with `on_empty`.
pub fn[M] poll(on_empty~ : () -> Receive[M, M]) -> Receive[M, M] {
  {
    steps: k => Take({
      choose: message => Some(() => k(message)),
      on_empty: Some(() => on_empty().build(k)),
    }),
  }
}

///|
/// Change the result with `f`.
pub fn[M, R, T] Receive::map(self : Receive[M, R], f : (R) -> T) -> Receive[M, T] {
  { steps: k => direct(() => self.build(value => direct(() => k(f(value))))) }
}

///|
/// Run this receive, then `other`, and keep both results.
pub fn[M, R, T] Receive::zip(
  self : Receive[M, R],
  other : Receive[M, T],
) -> Receive[M, (R, T)] {
  self.zip_with(other, (left, right) => (left, right))
}

///|
/// Run this receive, then `other`, and join both results with `f`.
pub fn[M, R, T, U] Receive::zip_with(
  self : Receive[M, R],
  other : Receive[M, T],
  f : (R, T) -> U,
) -> Receive[M, U] {
  {
    steps: k => direct(() => self.build(left => {
      direct(() => other.build(right => direct(() => k(f(left, right)))))
    })),
  }
}

///|
/// Run this receive, drop its result, then run `other`.
pub fn[M, R, T] Receive::then(
  self : Receive[M, R],
  other : Receive[M, T],
) -> Receive[M, T] {
  { steps: k => direct(() => self.build(_ => direct(() => other.build(k)))) }
}

///|
/// Run this receive, then the receive that the async function `next` makes
/// from its result. Async work between two receives goes here. An error of
/// `next` goes to the nearest `recover`, or fails the actor.
pub fn[M, R, T] Receive::bind(
  self : Receive[M, R],
  next : async (R) -> Receive[M, T],
) -> Receive[M, T] {
  {
    steps: k => direct(() => self.build(value => Work(() => next(value).build(k)))),
  }
}

///|
/// When this receive has waited for messages longer than `limit` in total,
/// continue with `on_timeout()`. Only the time that its receives wait counts;
/// async work in `bind` and handler time do not, and are not cut short.
/// Queued messages stay queued.
pub fn[M, R] Receive::within(
  self : Receive[M, R],
  limit : @lander_core.TimeLimit,
  on_timeout~ : () -> Receive[M, R],
) -> Receive[M, R] {
  {
    steps: k => Enter(Deadline(limit, () => on_timeout().build(k)), () => {
      self.build(value => Leave(() => k(value)))
    }),
  }
}

///|
/// When the mailbox closes while this receive waits, continue with `f()`.
/// Without it, a receive on a closed mailbox ends the actor as closed.
pub fn[M, R] Receive::on_closed(
  self : Receive[M, R],
  f : () -> Receive[M, R],
) -> Receive[M, R] {
  {
    steps: k => Enter(OnClosed(() => f().build(k)), () => {
      self.build(value => Leave(() => k(value)))
    }),
  }
}

///|
/// When a step of this receive raises an ordinary error, continue with
/// `on_error(error)`. A cancellation is not an error, so it is not caught.
pub fn[M, R] Receive::recover(
  self : Receive[M, R],
  on_error : (Error) -> Receive[M, R],
) -> Receive[M, R] {
  {
    steps: k => Enter(Recover(error => on_error(error).build(k)), () => {
      self.build(value => Leave(() => k(value)))
    }),
  }
}

///|
/// Call `handler` with the state and each message until it gives `Stop` or
/// the mailbox closes. The result is the last state. The loop runs as one
/// step, so it allocates nothing more than `handler` for each message.
pub fn[M, S] receive_loop(
  initial : S,
  handler : async (S, M) -> Next[S],
) -> Receive[M, S] {
  {
    steps: k => {
      let state = Ref(initial)
      Repeat({
        handle: message => match handler(state.val, message) {
          Continue(next) => {
            state.val = next
            None
          }
          Stop => Some(k(state.val))
        },
        finish: () => k(state.val),
      })
    },
  }
}

///|
/// Call `handler` for each message until the mailbox closes.
pub fn[M] receive_all(handler : async (M) -> Unit) -> Receive[M, Unit] {
  {
    steps: k => Repeat({
      handle: message => {
        handler(message)
        None
      },
      finish: () => k(()),
    }),
  }
}

///|
/// Call `handler` for each message, at most `count` times, or until the
/// mailbox closes.
pub fn[M] receive_n(
  count : @policy.MessageCount,
  handler : async (M) -> Unit,
) -> Receive[M, Unit] {
  {
    steps: k => {
      let left = Ref(count.to_int())
      Repeat({
        handle: message => {
          handler(message)
          left.val -= 1
          if left.val == 0 {
            Some(k(()))
          } else {
            None
          }
        },
        finish: () => k(()),
      })
    },
  }
}

///|
/// The number of pure steps that run in one call chain before a step returns
/// to the runner.
const DIRECT_LIMIT : Int = 32

///|
/// The depth of the current chain of pure steps.
let direct_depth : Ref[Int] = Ref(0)

///|
/// Call `next` at once while the chain is short, else return it to the runner.
fn[M] direct(next : () -> Step[M]) -> Step[M] {
  if direct_depth.val < DIRECT_LIMIT {
    direct_depth.val += 1
    let step = next()
    direct_depth.val -= 1
    step
  } else {
    Bounce(next)
  }
}

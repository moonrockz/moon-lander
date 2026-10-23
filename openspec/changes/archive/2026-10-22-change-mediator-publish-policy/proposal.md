# Proposal: Change the mediator publish policy

## Why

In `v0.2.0`, `Topic::publish` stops at the first handler that raises an
error, so the handlers after it do not run. The handlers of a topic are
independent reactions to one event, and the main consumers (the Morphir
workbench, and later moonrockz/smithy) need each reaction to run even when
another one fails. Foundatio.Mediator, the model for this package, uses this
contract by default: "a failing handler never prevents other handlers from
running". The planned async mediator (`add-mediator-async`) needs the same
contract and the same error case, so the core must change first.

## What Changes

- **BREAKING (behavior):** `Topic::publish` calls every handler of the
  topic one time, in add order, also after a handler raises an error. After
  the last handler, publish raises one error that holds every failure.
- Add the case `MediatorError::PublishFailed` to the core error type. It
  holds the number of handlers in the publish and each failure, with the
  position of its handler and the error that the handler raised, in add
  order. Publish raises it also when only one handler fails.
- `MediatorError::message` gives the failure count and the handler
  positions only. It does not show event values or the text of the wrapped
  errors, because both can hold secrets.
- Topic middleware still wraps the whole publish, so it gets the one
  combined error and can catch it.
- `Sender::send` does not change: a handler error passes out unchanged.
- Update the package README, the tests, the mediator acceptance suite and
  the generated interface. Add an `Unreleased` CHANGELOG entry that states
  the behavior change, and correct the `0.2.0` section, which omits the
  mediator that tag `v0.2.0` contains.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `mediator`: the requirement "A publish handler error stops publish" is
  removed. A new requirement says that a publish runs every handler and
  reports every failure in one error.

## Impact

- Code: `pkgs/lander/mediator` (`topic.mbt`, `error.mbt`, tests, README,
  `pkg.generated.mbti`) and `tests/mediator-acceptance`.
- API: one new error case and one new public record type for a failure.
  `MediatorError` is `pub(all)`, so a caller that matches its cases with no
  wildcard must add the new case.
- Behavior: a caller that relied on "stop at the first error" sees the
  later handlers run, and gets `PublishFailed` instead of the raw handler
  error.
- Release: this is a behavior change from `v0.2.0`. The next release must
  be `0.3.0`. The version change is a separate step that the owner
  approves, because a change to `moon.mod` on `main` starts the release
  workflow.

## Out of scope

- Concurrent publish, cancellation and timeouts. They come with the async
  mediator in `add-mediator-async`.
- A fire-and-forget publish, retries, and partial results from handlers.
- Any change to `Sender::send` or to the middleware order.
- The version change and the release itself.

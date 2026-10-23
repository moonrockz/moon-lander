# Design: Change the mediator publish policy

Labels: "Owner" marks a decision of the project owner. "Call" marks a
designer decision that the owner did not reject.

## Context

See proposal.md (Why). The facts that shape the design:

- `Topic::publish` in `pkgs/lander/mediator/topic.mbt` runs the topic
  middleware around one function that loops over the handlers. The loop
  has no `catch`, so the first handler error ends the loop and passes out.
- `MediatorError` is a `pub(all) suberror` with one case,
  `Rejected(reason~)`, and a `message` method. It derives nothing, so the
  package imports nothing (design D6 of the archived `add-mediator`).
- The core is synchronous. A `catch` catches every error that a sync
  handler raises; there is no cancellation in the core.
- The release workflow starts on a push to `main` that changes `moon.mod`,
  and it needs a `## X.Y.Z` section in `CHANGELOG.md`.

## Goals / Non-Goals

**Goals:**

- The Foundatio.Mediator `ForeachAwait` contract for `publish`: every
  handler runs, in add order, then one error reports every failure.
- One error shape that the sync core and the later async package share.

**Non-Goals:**

- Concurrent publish, cancellation, timeouts (see `add-mediator-async`).
- A change to `Sender::send`, which still passes a handler error out
  unchanged.

## Decisions

### D1. One error case with a record per failure (Owner: Foundatio model; Call: shape)

```moonbit
pub(all) struct PublishFailure {
  position : Int   // 1-based position of the handler, in add order
  error : Error    // the error that the handler raised, unchanged
}

pub(all) suberror MediatorError {
  Rejected(reason~ : String)
  PublishFailed(handlers~ : Int, failures~ : Array[PublishFailure])
}
```

- `failures` is in add order, so a caller can map each failure to its
  handler. `handlers` gives the total, so the text can say "2 of 3".
- Positions are 1-based because they appear in text for people. The
  field docs say so.
- Alternative: `Array[Error]` with no positions. Rejected: the caller
  could not tell which handler failed. Alternative: `Array[(Int, Error)]`.
  Rejected: a named record reads better in a `match` and in docs.

### D2. Always wrap, also for one failure (Owner)

- `publish` raises `PublishFailed` when one or more handlers fail.
  Foundatio throws an `AggregateException` in the same way. The caller has
  one error shape to handle for `publish`.
- `send` keeps its contract: one handler, so its error passes out
  unchanged. The two operations have different contracts on purpose.

### D3. The text holds counts and positions only (Owner; rule D6 of add-mediator)

- `message` gives, for example, "Publish failed: 2 of 3 handlers raised an
  error (positions 2, 3)".
- It does not include event values or the text of the wrapped errors. An
  application error can hold secrets, and the core never formats data it
  does not own. A caller reads each error from `failures`.

### D4. Topic middleware is unchanged (Call)

- The middleware still wraps the whole publish. Its next step runs the
  loop that collects the failures and raises `PublishFailed` at the end.
  So a middleware gets one combined error and can catch it.

### D5. Release and CHANGELOG (Owner: ask before a release)

- This change adds an `## Unreleased` section to `CHANGELOG.md` with the
  behavior change, marked as breaking. The release script matches only
  `## X.Y.Z` headings, so the section does not start a release.
- It also corrects the `0.2.0` section, which does not list the mediator
  that tag `v0.2.0` contains.
- The version change to `0.3.0` is a separate pull request that the owner
  approves. It renames `Unreleased` to the version heading.

## Risks / Trade-offs

- [A caller relies on "stop at the first error"] → The CHANGELOG marks the
  change as breaking, and the next release is a minor version change in
  `0.x`.
- [Handlers after a failing handler now run] → This is the intended
  contract. A topic that needs an ordered, all-or-nothing sequence uses one
  handler that calls the steps in order.
- [A new case breaks exhaustive matches on `MediatorError`] → It is
  `pub(all)`, so callers can match it. The `0.3.0` release already carries
  a behavior change, and the CHANGELOG names the new case.

## Migration Plan

No data migration. Callers update their `catch` from the raw handler error
to `MediatorError::PublishFailed`. Rollback is a revert of this change
before the `0.3.0` release.

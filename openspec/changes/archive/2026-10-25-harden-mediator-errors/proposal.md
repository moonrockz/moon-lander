## Why

Mediator errors permit invalid publish counts, positions and time limits. Their
failure array can change after an error is raised. Async topics use a Boolean
and an array to represent two different handler states.

## What Changes

- Restrict error construction and add supported rejection, timeout and derived publish constructors.
- Use the core `TimeLimit` for timeout errors and async timeout middleware.
- Expose read-only publish failures through safe accessors and a copied array.
- Use typed alternatives for wrapped core topics and async handlers.
- Update consumers, compiled guides and regression tests.

## Capabilities

### Modified Capabilities

- `mediator`: valid errors and immutable publish failure reports.
- `mediator-async`: typed timeout limits and core topic wrapping.

## Impact

This breaks direct construction of mediator errors and failure records. Callers
use the supported constructors and failure accessors. No new duration type,
release, publication or other mediator feature is in scope.

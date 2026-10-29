## MODIFIED Requirements

### Requirement: Same async behavior on wasm, js and native

The existing async sender, middleware, timeout and topic APIs SHALL retain the
same behavior on wasm, js and native. Sender and basic middleware composition
SHALL also build on wasm-gc without requiring an event loop. Runtime-only
timeout and topic operations SHALL remain limited by explicit target boundaries.
A selected acceptance leg that runs zero tests MUST NOT count as a pass.

#### Scenario: The acceptance suite on each target
- **WHEN** the existing async acceptance suite runs on wasm, js and native
- **THEN** its supported API, timeout behavior and results remain unchanged and each selected leg runs more than zero tests

#### Scenario: A four-target package imports public async composition
- **WHEN** a scratch consumer imports the public sender and before/after/finally middleware
- **THEN** planning and compilation succeed on wasm, wasm-gc, js and native without a copied mediator or unpublished dependency

## ADDED Requirements

### Requirement: Event-loop-free embedded async composition

A non-suspending async sender and its basic middleware SHALL complete under
`hosting.run_embedded` on wasm and wasm-gc. The middleware SHALL enclose the
actual handler call and retain ordered before/after/finally behavior. This
composition MUST NOT start an event loop or permit a suspended embedded hook
to appear completed.

#### Scenario: Embedded send completes
- **WHEN** an embedded command awaits a public async sender whose handler and middleware do not suspend
- **THEN** the reply and all middleware complete before the command returns on wasm and wasm-gc

#### Scenario: Embedded send fails or suspends
- **WHEN** a handler raises or a middleware suspends under the embedded driver
- **THEN** the handler error or the driver's typed suspension failure is retained, and suspension is not reported as successful completion

### Requirement: Real asynchronous completion remains enclosed

On native and JS, async middleware SHALL wait for the actual handler completion.
After middleware SHALL run only after a reply. Finally middleware SHALL run on
reply, failure and cancellation. Existing timeout consumers SHALL retain their
typed deadline and cancellation behavior on supported targets.

#### Scenario: JavaScript Promise completes later
- **WHEN** the handler awaits a JavaScript Promise that resolves after dispatch returns control to the runtime
- **THEN** after/finally middleware remains open until resolution and the caller receives the resolved reply

#### Scenario: Runtime failure, cancellation and timeout
- **WHEN** an async handler fails, is cancelled, or exceeds the existing timeout
- **THEN** its outcome passes through the real middleware with the specified after/finally behavior and no early synchronous dispatch

# Tasks: add-mediator

Epic: lander-4us.10

This change adds the pure package `moonrockz/moon-lander/mediator` in
`pkgs/lander/mediator`. It depends on no other change. It must not import
`moonbitlang/async`, `@hosting`, or any host adapter, and it must contain
no `#cfg` and no per-target file (design D5). Run each test on `wasm`,
`wasm-gc`, `js`, and `native` through `mise run test`. A test leg that
runs zero mediator tests is a failure (design D5).

## 0. MoonBit toolchain update

Bead: lander-4us.10.6

- [x] 0.1 Find the newest MoonBit release from the install endpoint (`https://cli.moonbitlang.com/binaries/<version>/`, as the pin comment in `.config/mise/config.toml` describes); record the exact version string in the bead
- [x] 0.2 Change the `http:moonbit` pin in `.config/mise/config.toml`: the `version` field and each platform URL, with `+` written as `%2B`; verify no other file holds the old version string (search the repo for it)
- [x] 0.3 Run `mise trust`, `mise install`, and the core-library completion step from `README.md` (Development setup); verify `mise exec -- moon version --all` shows the new version and `moonx` exists
- [x] 0.4 Run `mise run format` and then `mise run check` on the unchanged tree; verify lint, workspace and version validation, tests on all four targets, and builds pass with the new toolchain. Fix no mediator code in this group: a failure here is a toolchain problem, not a mediator problem
- [x] 0.5 Check that `mise run test:native-zig` still passes if the toolchain change touches native linking; verify the result in the bead

## 1. Tracer bullet: typed sync sender, one request, one reply

Bead: lander-4us.10.1

- [x] 1.1 Create the package `pkgs/lander/mediator` (`moon.pkg`, no import beyond the core prelude); verify `mise run build` passes on `wasm`, `wasm-gc`, `js`, and `native`
- [x] 1.2 Add `Sender[C, Req, Res]`, `sender`, and `Sender::send` as in design D1, with the handler type `(C, Req) -> Res raise`; verify a white-box test sends `Ping("Hello")` and gets `"Pong: Hello"`, and the handler runs one time
- [x] 1.3 Add two senders for two request types in one test; verify a send through the first runs only the first handler, and a request of the wrong type for a sender does not compile (record the compile failure in a comment in the test file; do not add a text-key API to make it run)
- [x] 1.4 Verify a test where the handler raises an application error: `send` raises the same error and gives no reply
- [x] 1.5 Verify the public interface holds no registration or send function that takes a text key or an untyped value; check with `moon info` output for the package
- [x] 1.6 Add the Ping example as a runnable example in the package `README.mbt.md`; verify the example runs in `mise run test` on all four targets

## 2. Middleware pipeline with ordering and short-circuit

Bead: lander-4us.10.2

- [x] 2.1 Add the middleware shape of design D3 and `Sender::use_`; verify `use_` gives a new sender value and the original sender still sends without the middleware
- [x] 2.2 Decide from the compiled README example whether `use_` takes a `Middleware` value or a plain function (design Open Questions); record the choice in design.md D3 and verify the example compiles with that form
- [x] 2.3 Add helper constructors for the before/after and finally shapes; verify a log middleware records its before entry, the handler run, and its after entry, in that order
- [x] 2.4 Verify a middleware that gives a reply without a call to the next step: the handler does not run and the caller gets the middleware reply
- [x] 2.5 Verify a middleware that changes the request before the next step and a middleware that changes the reply after it; each gets a unit test
- [x] 2.6 Attach middleware A and then B in one test; verify the run order is A, B, handler, B, A
- [x] 2.7 Verify a middleware that catches the error of the next step can give a reply instead, and a middleware that does not catch passes the same error out of `send`
- [x] 2.8 Document `use_` and the helper constructors with a runnable log-middleware example in the package README; verify the example runs on all four targets

## 3. Publish to many handlers

Bead: lander-4us.10.3

- [x] 3.1 Add `Topic[C, Ev]`, `topic`, `Topic::add`, and `Topic::publish` as in design D2; verify `add` gives a new topic value and the original topic keeps its handler count
- [x] 3.2 Verify a publish over three handlers runs each handler one time, in add order
- [x] 3.3 Verify publish stops at the first handler that raises: the handler before it has run, the handler after it has not run, and publish raises that error
- [x] 3.4 Add `Topic::use_` with the same middleware shape as group 2; verify the middleware order test of 2.6 passes in publish form
- [x] 3.5 Verify an event handler gives no reply value: the publish call type is `Unit` in the `moon info` output for the package
- [x] 3.6 Document publish with a runnable two-handler example in the package README; verify the example runs on all four targets

## 4. Context passing and typed errors

Bead: lander-4us.10.4

- [ ] 4.1 Fix the exact `MediatorError` cases of design D6: name only core-raised contract faults, each with a test that raises it; verify no case formats a request value into its text, with a test whose request holds a secret-like field
- [ ] 4.2 Verify the context value passes unchanged: a handler and a middleware read a field of a services record from the context and get the value the caller gave; use a test that changes the record field value between two sends and sees each value
- [ ] 4.3 Verify the core holds no context after a call: a test sends with one context value, then sends with a second, and the handler sees the second value only
- [ ] 4.4 Verify a handler can raise `MediatorError` and an application error through the same sender, and `send` passes each out unchanged when no middleware catches it
- [ ] 4.5 Document the context parameter and `MediatorError` in the package README with a runnable services-record example; verify the example runs on all four targets

## 5. Integration check, acceptance suite, and docs

Bead: lander-4us.10.5

- [ ] 5.1 Add the acceptance suite `tests/mediator-acceptance` in the unpublished `tests/` module for the spec scenarios: build a sender, two senders stay separate, handler errors, publish order, publish error stop, log middleware, short-circuit, middleware order, context read; verify `mise run test` passes on `wasm`, `wasm-gc`, `js`, and `native`
- [ ] 5.2 Verify each target leg of the mediator acceptance suite runs more than zero tests; record the test count per target in the bead, and treat a zero count as a failure of this task
- [ ] 5.3 Run `moon info` for the mediator package and verify the generated interface is the same for `wasm`, `wasm-gc`, `js`, and `native` (no diverging-interface report); verify the package source has no `#cfg`, no per-target file, and no import of `moonbitlang/async`
- [ ] 5.4 Add the mediator row to the layer table in `pkgs/lander/README.md` and one framework docs page that shows send, publish, and middleware with the Ping example; verify `mise run build:site` and the README example tests pass
- [ ] 5.5 Run `mise run check`; verify lint, workspace and version validation, all target tests, and builds pass

## Workflow follow-up

- Propose the async mediator package (`mediator/async`, `supported_targets = "wasm+js+native"`) as a later OpenSpec change after this change is archived. Do not add async code to the core package.
- Propose hosting integration (a builder step that holds senders in the services record and passes `Context[S]` as the context type) in the host lifecycle change or a later mediator change, after `add-host-lifecycle` lands.

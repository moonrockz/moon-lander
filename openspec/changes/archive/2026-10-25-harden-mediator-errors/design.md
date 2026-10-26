## Decisions

### D1 — Owner: reuse the core time limit

`TimedOut(after~ : TimeLimit)` and async `timeout(limit : TimeLimit)` use
`moonrockz/moon-lander-core`. The async adapter converts the limit to milliseconds
only when it calls `moonbitlang/async`.

### D2 — Call: derive publish errors from handler outcomes

Make `MediatorError` a `pub suberror`: external packages can match its cases but
cannot construct them directly. Supply `rejected(reason)` and `timed_out(after)`.
Supply `from_publish_errors(Array[Error?]) -> MediatorError?` for async and other
adapters. Each array slot represents one handler in add order. Empty arrays and
all-success arrays give `None`; failed slots derive positive positions and a
positive handler count. No caller supplies a position or a count.

`PublishFailure` is read-only and only mediator constructs it. `PublishFailures`
has private storage, `length`, optional `get`, and `to_array` that copies storage.
The derived constructor retains no caller-owned array. Error values remain valid
if the caller changes an input array or a returned copy.

### D3 — Call: represent core wrapping with an enum

Async topic handlers are `Core(core_topic)` or `Own(async_handlers)`. A core
alternative holds the core topic itself, not an array. Both publish operations
pass its error through unchanged. `add` converts it to ordinary async handlers,
with the core publish at position 1. `use_` preserves the alternative. Ordinary
sequential and concurrent publish derive errors from outcome slots.

### D4 — Owner: supported targets stay as documented

The explanation in async `moon.pkg` already landed in #78. Finding 3 of
lander-4us.24 is satisfied: async has no wasm-gc event loop in the pinned
`moonbitlang/async`. Verify the existing comment; do not duplicate it.

## Verification

Check empty, successful and failed outcome arrays, first and last positions,
copy isolation, rejection and valid timeout boundaries. Test core passthrough,
add and middleware on both publish paths. Compile the migration examples. Run
core on wasm, wasm-gc, js and native and async on wasm, js and native, then run
the repository check and strict OpenSpec validation.

# Isolated Moonx runtime

This optional module contains a frozen, namespaced subset of
`moonbitlang/async@0.22.5`, copyright International Digital Economy Academy,
licensed under Apache-2.0. See [LICENSE](LICENSE) and
[runtime/provenance.json](runtime/provenance.json) for source digests and every
production file's input and generated digest. There was no upstream NOTICE file.

The closure contains the runtime entry, processes, signals, standard streams and
filesystem operations, with their transitive support packages. It excludes the
public socket, HTTP, TLS and compression packages. Internal event-loop support
remains part of the frozen source. The complete licensed upstream test sources
and private fixture inputs are retained under `tests/assets/moonx-runtime/` in
the repository.

The declared modifications are namespace imports, production-only manifests,
Wasm/native target declarations, an explicit synchronous `runtime.run` entry,
and a first-signal observer latched before cancellation handlers run. Copyright
headers, native C symbols and the stock Moonrun Wasm host ABI are preserved.
The observer does not replace upstream cancellation or final runtime exit policy.
Changed source files identify the modification. The generator reconstructs and
formats the expected files from immutable inputs; a check fails on changed,
missing or undeclared runtime source files rather than trusting the manifest
stored alongside them.

Applications call the public synchronous driver from `fn main`. They must not
mix this runtime's tasks, I/O handles or scopes with canonical async values.
Existing hosting, actors and embedded applications continue using canonical
async; no framework module imports this optional launcher.

The upstream public observer request is
[moonbitlang/async#706](https://github.com/moonbitlang/async/issues/706). When a
released canonical async version provides a compatible observer and explicit
entry on both supported stock consumers, qualify it through the same real-host
and public-registry tests, remove this frozen closure and its generation inputs,
and replace only the launcher's adapter imports. Preserve the launch-plan API
and cleanup behavior. An upstream issue or unreleased source change alone is
not enough to remove the compatibility boundary.

Run retained upstream tests with `mise run test:moonx-runtime -- --test native`
and `mise run test:moonx-runtime -- --test wasm`; run the drift regression with
`mise run test:moonx-runtime -- --test-drift`. The test task creates an isolated,
unpublished workspace, overlays the committed production implementation and
runs the original closure's tests and documentation examples. Test-only support
packages stay in that workspace. It adapts `async test` and fixture `async main`
to explicit owned-runtime entries because stock compilers hard-code canonical
async for those language forms. It reads fixture artifact paths from the public
compiler JSON output, relocates filesystem fixture paths, and keeps the exact
`any([])` Failure/message assertion without its changed source-location snapshot.
No test assertion is updated by accepting a newly observed snapshot. The test
suite's upstream real-time and I/O cases remain intact.

Two observations support truthful completion reporting: a non-consuming view of
the existing runtime exit-signal selection, and an optional synchronous
`on_force` notification immediately before the existing graceful cancellation
handler requests hard termination. Both retain the original default behavior.
The public outcome records `force_requested`, alongside the actual child wait
status; it does not infer the cause of death from a timer or from stdout.

The retained signal fixtures acknowledge their initialized or configured handler
stage before cancellation. Their original finalizer and termination assertions
remain intact. The retained basic-wait case uses a child blocked on an explicit
release and checks that the real wait is pending before release and returns its
actual status afterward. These declared test-only adaptations remove cold-start
sleep assumptions; readiness waits have a real timeout. They do not modify the
published runtime or application protocol.

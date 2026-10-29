# Tests

This unpublished workspace module contains acceptance tests and domain laws.
Its suites exercise the public notebook APIs migrated from Moonbase, the
configuration core, and the sync and async mediators.

| Suite | Coverage | Targets |
| --- | --- | --- |
| `actors-acceptance` | Actor scenarios of `add-typed-actors`: the counter, concurrent producers, independent actors, finite actors, FIFO and selective receive, time limits, bounded and unbounded admission, reenqueue order, the receive test runner, request races and destinations, close, drain, cancel, startup and cleanup, child ownership, services and responders, names and directories, and topics. `mise run check:actors` fails when a target runs zero tests | wasm, JavaScript, native |
| `actors-bench` | Local benchmark program of the actor receive shapes. Only the manual task `mise run bench:actors` runs it; it is not a test | wasm, JavaScript, native |
| `config-acceptance` | Merge, get/show/path helpers, and a complete pure load across all file formats, environment and overrides | All four |
| `browser-parity`, `browser-parity-reference` | Shared explicit cases (the core fixture, a parse error, a binding error) and their reference observation; `mise run test:browser` compares it with the browser result | All four |
| `browser-fixture`, `browser-consumer`, `browser/` | Browser acceptance application, headless consumer guide and Playwright suites; see [the browser guide](browser/README.md) | JavaScript in Chromium, Firefox and WebKit |
| `config-conventions-preset` | The Morphir preset of the configuration conventions, made from public parts, and its cases | All four |
| `config-conventions-acceptance` | Morphir's `config.feature` discovery, precedence, member and ambiguity cases, and merge-rule cases, as Gherkin scenarios over the preset | JavaScript, native |
| `config-conventions-laws` | The same preset cases as snapshot tests | All four |
| `config-fixture`, `config-parity` | Shared explicit builder and file tree; complete value, provenance and report observations compared by `mise run check:config` | All four |
| `formats-default`, `formats-toml`, `formats-custom` | Default and overridden format sets, parser execution and linked output trimming | All four |
| `hosting-argparse-acceptance` | Argument-first driver, standard discovery flags, shared matches and usage reports; native subprocess checks that help and version return code 0 from `run` and that usage errors write to standard error | JavaScript, native |
| `console-host-scenarios`, `console-host-program`, `console-signal-acceptance` | The console test host and its scenarios, its js program, and the parent suite that starts it as a native, Node.js and Bun child: first and second signals, polling and spinning loops, piped output, open timers, help and version; `mise run check:console` also runs it from a consumer module outside the workspace | native (js children) |
| `embedded-host-program` | The embedder of `mise run check:embedded`: three runs in one instance (help, version, clean), so control must return after each; the check also reads the wasm imports for an exit import | wasm, wasm-gc |
| `mediator-acceptance` | Send, two separate senders, handler errors, publish order, one and two publish failures in one `PublishFailed`, log middleware, short-circuit, reply change, middleware order and context read; `mise run check:mediator` fails a target that runs zero of them | All four |
| `mediator-async-acceptance` | One `async test` per `mediator-async` scenario: async send and errors, sequential and concurrent publish, caller cancellation, handler timeouts, the `timeout` middleware, middleware order, `finally_` on cancellation, context read and a wrapped core sender; `mise run check:mediator` fails a target that runs zero of them | wasm, JavaScript, native |
| `formats-leaky` | Deliberately reachable YAML parser that `mise run check:formats` must reject | All four |
| `nbformat-acceptance` | Jupyter cells, outputs, attachments, extensions, cursor paths and validation errors | JavaScript, native |
| `nbformat-laws` | JSON and text round trips, traversal agreement and cursor navigation | All four |
| `notebooks-acceptance` | Shared Jupyter and DIB navigation, JSON/YAML/TOML/Ion metadata, kernel aliases, directives, specialized payloads and runtime capability inspection in mixed cell collections | JavaScript, native |
| `notebooks-laws` | Cross-format source observations, cursor paths, DIB normalization, native Ion metadata round trips, pruning, stopping and consumer-defined node types | All four |

The `config-acceptance` feature text is in its test file, because wasm and
wasm-gc have no file system. `@moonspec.run_or_fail` is async and wasm-gc has no
async test entry, so the suite runs the synchronous moonspec runner steps.

Property generators and shrinkers preserve valid inputs. Each property declares
its seed, case count, size and shrink limits. Acceptance feature paths are
relative to this module directory, the test working directory.

`mise run test` discovers all suites and the executable `examples.mbt.md`
guides in `pkgs/notebooks/`. Moon applies the acceptance packages' target
restrictions while running the laws on wasm, wasm-gc, JavaScript and native.

Run the notebook suites on one target:

```shell
mise exec -- moon test tests/nbformat-acceptance tests/nbformat-laws tests/notebooks-acceptance tests/notebooks-laws --target js
```

Run the Morphir preset suites. The acceptance suite runs on js and native, and
the laws run on all four targets:

```shell
mise exec -- moon test tests/config-conventions-acceptance --target js
mise exec -- moon test tests/config-conventions-acceptance --target native
mise exec -- moon test tests/config-conventions-laws --target all
mise exec -- moon test tests/config-conventions-preset --target all
```

The preset also exports `layered_morphir()` and `layered_formats()` for the
opt-in discovery contract. Its tested policy uses workspace-first roots,
JSON5/JSON then YAML/YML then TOML groups, supplemental
`morphir-workspace.json`, selected-file overlays, and enabled profiles. It leaves
the member walk to the application; explicit project selection remains available.
The supplemental document becomes the workspace section through a pure transform.
The original preset and snapshots retain the default-policy compatibility cases.

The layered fixture compares values, reports, control metadata, origins and root
evidence over complete and incremental trees on all four targets. It covers a
supplemental-only workspace and standard profile stems. The native and JavaScript
host tests record disk requests for a temporary member under a layered workspace
and for an empty isolated boundary, proving that discovery does not read an
ancestor above the selected workspace or boundary. The public registry consumer
also exercises workspace evidence, grouped formats, selected overlays and profile
activation from the packaged config module.

After an intended change to discovery, rewrite the preset snapshots and review
the diff:

```shell
mise exec -- moon test tests/config-conventions-laws --target native --update
```

`mise run test:node-adapter` runs the shared host tests and the
`config-host-esm` application on Node and Bun. The application verifies that the
checked-in adapter also links and reads a file in ESM output.

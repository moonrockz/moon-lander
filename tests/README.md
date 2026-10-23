# Tests

This unpublished workspace module contains acceptance tests and domain laws.
Its suites exercise the public notebook APIs migrated from Moonbase, the
configuration core, and the sync and async mediators.

| Suite | Coverage | Targets |
| --- | --- | --- |
| `config-acceptance` | Merge, get/show/path helpers, and a complete pure load across all file formats, environment and overrides | All four |
| `browser-parity`, `browser-parity-reference` | Shared explicit cases (the core fixture, a parse error, a binding error) and their reference observation; `mise run test:browser` compares it with the browser result | All four |
| `browser-fixture`, `browser-consumer`, `browser/` | Browser acceptance application, headless consumer guide and Playwright suites; see [the browser guide](browser/README.md) | JavaScript in Chromium, Firefox and WebKit |
| `config-conventions-preset` | The Morphir preset of the configuration conventions, made from public parts, and its cases | All four |
| `config-conventions-acceptance` | Morphir's `config.feature` discovery, precedence, member and ambiguity cases, and merge-rule cases, as Gherkin scenarios over the preset | JavaScript, native |
| `config-conventions-laws` | The same preset cases as snapshot tests | All four |
| `config-fixture`, `config-parity` | Shared explicit builder and file tree; complete value, provenance and report observations compared by `mise run check:config` | All four |
| `formats-default`, `formats-toml`, `formats-custom` | Default and overridden format sets, parser execution and linked output trimming | All four |
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
```

After an intended change to discovery, rewrite the preset snapshots and review
the diff:

```shell
mise exec -- moon test tests/config-conventions-laws --target native --update
```

`mise run test:node-adapter` runs the shared host tests and the
`config-host-esm` application on Node and Bun. The application verifies that the
checked-in adapter also links and reads a file in ESM output.

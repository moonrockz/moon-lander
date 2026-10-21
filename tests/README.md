# Tests

This unpublished workspace module contains acceptance tests and domain laws.
Its suites exercise the public notebook APIs migrated from Moonbase and the
configuration core.

| Suite | Coverage | Targets |
| --- | --- | --- |
| `config-acceptance` | An in-memory source merged over a TOML snapshot, read with `get_text` | All four |
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

`mise run test:node-adapter` runs the shared host tests and the
`config-host-esm` application on Node and Bun. The application verifies that the
checked-in adapter also links and reads a file in ESM output.

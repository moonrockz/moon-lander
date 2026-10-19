# Tests

This unpublished workspace module contains acceptance tests and domain laws.
Its suites exercise the public notebook APIs migrated from Moonbase.

| Suite | Coverage | Targets |
| --- | --- | --- |
| `nbformat-acceptance` | Jupyter cells, outputs, attachments, extensions, cursor paths and validation errors | JavaScript, native |
| `nbformat-laws` | JSON and text round trips, traversal agreement and cursor navigation | All four |
| `notebooks-acceptance` | Shared Jupyter and DIB navigation, JSON/YAML/TOML/Ion metadata, kernel aliases, directives, specialized payloads and runtime capability inspection in mixed cell collections | JavaScript, native |
| `notebooks-laws` | Cross-format source observations, cursor paths, DIB normalization, native Ion metadata round trips, pruning, stopping and consumer-defined node types | All four |

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

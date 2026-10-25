# Tasks: add-logging

Epic: lander-4us.41

This change adds the sixth framework module `moonrockz/moon-lander-logging` in
`pkgs/logging`. Its root package, imported as `@logging`, holds the whole API. It
depends on no other change. The module must import no module except
`moonbitlang/core`: no framework module, no `moonbitlang/async`, no host adapter.
The root package must contain no `#cfg` and no per-target file (design D8). Run each test on `wasm`,
`wasm-gc`, `js`, and `native` through `mise run test`. A test leg that runs zero
logging tests is a failure (design D8).

## 1. Tracer bullet: bring-your-own logger receives one event

Bead: lander-4us.41.1

- [x] 1.1 Create the module `pkgs/logging` (`moon.mod` with the name `moonrockz/moon-lander-logging`, the root version, no import, and `readme = "README.mbt.md"`; a root `moon.pkg` with no import beyond the core library) and add `./pkgs/logging` to `moon.work`; verify `mise run build` passes on `wasm`, `wasm-gc`, `js`, and `native`, and `mise run validate:versions` passes
- [x] 1.2 Add the module to the framework table of `scripts/validate-packages.mbtx` with no allowed framework import, and permit it as an import of config, mediator, hosting, and the umbrella module (design D8); extend the no-third-party rule of core to logging. Verify task script tests for the spec scenarios: the six modules are found, a missing `./pkgs/logging` member names the folder, an import of `moonrockz/moon-lander-core` by logging names both modules, and an import of `moonbitlang/async` by logging names the module; verify `mise run validate` passes on the tree
- [x] 1.3 Add `pkgs/logging` to the framework publish order in `scripts/publish.mbtx` (after `pkgs/core`, before `pkgs/config`) and change the module list in `AGENTS.md` (Publishing) to six modules; verify by a search that no text outside `openspec/changes/archive/` still says the framework is five modules
- [x] 1.4 Add `Level` with the six MEL levels and derived order (design D2); verify a test that `Debug < Warning` and `Critical > Error`
- [x] 1.5 Add `LogEvent` with read-only fields (design D3) and the `Logger` trait with the default `enabled` (design D1); verify a test where an application type that implements only `log` gets one event at each of the six levels
- [x] 1.6 Add `&Logger::write` and the six level methods (design D4). In this group, the event takes the template text as is, with no properties; verify a test that `warn` gives a `Warning` event with the given template, and a test that `error` with an `error=` argument keeps the error value
- [x] 1.7 Verify the level check before event construction: an application logger that enables only `Warning` and higher counts its `log` calls; a `debug` call leaves the count at zero, and an `error` call makes it one
- [x] 1.8 Add `MemoryLogger` with `new` and `events` (design D6); verify a test that two events stay in write order, and a test that one library function gives the same event to an application logger and to a `MemoryLogger`
- [x] 1.9 Write the package `README.mbt.md` with a runnable bring-your-own example: an application type that implements `log` over `println` (design D7); verify the example runs in `mise run test` on all four targets
- [x] 1.10 Answer the design open question from the compiled README example (methods on `&Logger` or free functions); record the choice in design.md D4, and verify `moon info` for the package shows the chosen form and no `raise` effect on a level method or on `log`

## 2. Message templates

Bead: lander-4us.41.2

- [x] 2.1 Add the pure template parser of design D5 (literal parts and named holes, `{{` and `}}` escapes); verify unit tests for one hole, two holes, escaped braces, an unclosed brace, an empty `{}`, a name with a space, and a single `}`
- [x] 2.2 Bind arguments to holes in order in `&Logger::write` (design D5); verify the spec scenarios: two holes bind in order, a missing argument gives no property, and an extra argument is dropped
- [x] 2.3 Verify a template with one name twice keeps both pairs and renders the first value in both holes (design D5); fix the result in a test
- [x] 2.4 Add `LogEvent::message` with the render rule of the spec (text without quotes, other values as compact JSON); verify the spec scenarios for string and number values, an object value, a missing argument, and escaped braces
- [x] 2.5 Verify property values stay `Json`: a number argument gives a JSON number, and a `derive(ToJson)` struct gives a JSON object with its fields
- [x] 2.6 Document templates in the package README with a runnable example that shows the event properties and the rendered message; verify the example runs on all four targets

## 3. Built-in loggers and combinators

Bead: lander-4us.41.3

- [x] 3.1 Add `null_logger` (design D6); verify a test that it enables no level and that a `critical` call to it raises nothing
- [x] 3.2 Add `min_level`; verify the spec scenarios: an in-memory logger behind `min_level(Warning)` keeps three of six events, and a wrapped logger that enables only `Error` gets no `Warning` event through `min_level(Debug)`
- [x] 3.3 Add `fan_out`; verify the spec scenarios: two in-memory loggers each keep one event, and a second logger behind `min_level(Error)` keeps no `Warning` event
- [x] 3.4 Add `with_category`; verify a test that the kept event has the category and the same level, template, and properties
- [x] 3.5 Verify each combinator checks `enabled` in its own `log`: a direct `log` call with a `Debug` event to `min_level(Warning)` does not reach the wrapped logger
- [x] 3.6 Verify the `|>` chain of design D6 compiles with a `MemoryLogger` as the first value; document the chain in the package README with a runnable example and verify it runs on all four targets

## 4. Text line rendering

Bead: lander-4us.41.4

- [x] 4.1 Add `LogEvent::to_line` (design D7); verify the spec scenarios: a line with a category, a line without a category, and a line with an error
- [x] 4.2 Verify each of the six level codes (`TRC`, `DBG`, `INF`, `WRN`, `ERR`, `CRT`) in one test
- [x] 4.3 Verify the error line uses the `Show` text of the error: a test error type whose `Show` output redacts a field renders the redacted text in `to_line`, not the field value
- [x] 4.4 Change the bring-your-own example of task 1.9 to print `to_line` output, and add the README warning against passing `expose()` output to a log method; verify the example runs on all four targets

## 5. Integration check, acceptance suite, and docs

Bead: lander-4us.41.5

- [x] 5.1 Add the acceptance suite `tests/logging-acceptance` in the unpublished `tests/` module for the spec scenarios: bring-your-own logger, default level check, level check before event construction, template binding and mismatches, rendering, built-in loggers and combinators, text lines. Add one test that imports `@config`, passes `Json(secret.to_string())` as an argument, and checks that the line holds the redacted text and not the exposed value; record in a comment that `Secret` has no `ToJson`. Verify `mise run test` passes on `wasm`, `wasm-gc`, `js`, and `native`
- [x] 5.2 Add the logging paths to a zero-count check: extend `scripts/check-mediator.mbtx` to a shared check over named paths, or add `scripts/check-logging.mbtx` from it; wire it as `mise run check:logging`, into `scripts/check.mbtx`, and into the target matrix of `.github/workflows/ci.yml`; verify the check fails when a target leg runs zero tests and passes on all four targets
- [x] 5.3 Run `moon info` for the root package of `pkgs/logging` and verify the generated interface is the same for `wasm`, `wasm-gc`, `js`, and `native`; verify the package source has no `#cfg`, no per-target file, and no import outside the core library, and that a consumer that imports only `moonrockz/moon-lander-logging` resolves no other module
- [x] 5.4 Add the logging module to the module and layer tables of the umbrella README (`pkgs/lander/README.mbt.md`) and the root `README.md`, and link `pkgs/logging/README.mbt.md` as the Logging chapter (and add the module to the `packages` and `api` lists of `site/site.json`), in the explainer style of the existing chapters; verify `mise run build:site` and the README example tests pass
- [x] 5.5 Run `mise run format` and `mise run check`; verify lint, workspace and version validation, all target tests, and builds pass, and commit the new `pkg.generated.mbti` files

## Workflow follow-up

- Propose host sinks (standard error on `native` and `js`, a file sink) in a later change. They belong in host adapters that use `moonbitlang/async`.
- Propose level configuration from `@config` (the `Logging:LogLevel` section, minimum levels for each category) after `add-host-lifecycle` lands.
- Propose a logging middleware for `@mediator` and a logger in the host services record after this change and `add-host-lifecycle` land.
- Consider an enricher step (timestamps, scopes) and a JSON line renderer as later slices.

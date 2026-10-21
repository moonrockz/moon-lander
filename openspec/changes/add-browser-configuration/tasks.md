# Tasks: add-browser-configuration

Epic: lander-4us.8

Each group is one AFK story and one PR. Read `design.md` and the scenarios in
`specs/browser-configuration/spec.md`. Land the planning PR before implementation. A dependency is a merge dependency:
do not start against an unlanded prerequisite. Keep tasks unchecked until verified.
Run `mise run format`, `mise run check`, and strict OpenSpec validation for each
implementation PR. Record the actual source range, PR, browser engine builds,
commands, and results in its bead before closing and syncing it.

## 1. Feasibility spike: hosted TOML in real browsers

Bead: lander-4us.8.1

- [ ] 1.1 Add an unpublished browser fixture that fetches one TOML file, runs the current pure loader with an explicit override, binds a typed section, and reports its value and origin. Keep all configuration execution inside the browser page.
- [ ] 1.2 Bundle a small TypeScript Web API adapter with the pinned Bun through a moonx script. Prove a browser-compatible generated inline FFI factory and the async promise bridge in Chromium, Firefox, and WebKit without Node shims. Record exact compilable FFI/API shapes in the design.
- [ ] 1.3 Add the narrow AGENTS.md Web API exception for browser adapters and fixtures. Keep selection UI in the unpublished fixture and automation in MoonBit task scripts.
- [ ] 1.4 Pin Playwright exactly in mise and the private harness dependency, commit the lockfile, and check version agreement. Add browsers:install and test:browser moonx tasks, bounded server/process cleanup, a documented local setup, and test:browser in mise run check.
- [ ] 1.5 Add a focused Linux browser CI category on the existing events and require it in ci-ok without removing existing needs. Build the fixture once for the three engines. Prove a deliberate failing assertion or missing engine makes the task nonzero; record setup, build, suite, and total timings.
- [ ] 1.6 Verify real-browser loading and binding, absence of Node shims in the fixture, and the explicit feasibility failure gate. The public browser-package import scenario is completed in group 2. If any required engine or the FFI bridge cannot work, record the evidence and stop dependent work for an owner decision. Do not substitute Node execution or reduce the engine matrix.

## 2. Hosted configuration with production mounts

Bead: lander-4us.8.2

- [ ] 2.1 Add the js-only config/browser package and browser TypeScript adapter using the proven FFI shape. Add opaque mounts, the version-1 URL manifest, multiple non-overlapping roots, typed BrowserError values, and the async core request loop. Verify hosted TOML, explicit overrides, typed binding, and virtual origins in all three engines.
- [ ] 2.2 Implement canonical path and mount validation, exact sorted listings, explicit run inputs, per-load answer caching, and no-progress detection. Verify the namespace and run-input scenarios, empty/duplicate/conflicting input cases, and a faulty provider that repeats an answered request.
- [ ] 2.3 Derive URL paths only from the authorized base and manifest, encode segments, omit credentials, and reject redirects. Reject a base whose parsed pathname lacks a trailing slash before any fetch; verify that an accepted directory base retains its path. Verify invalid manifest versions and shapes, listed and unlisted paths, empty directories, 404, 403/500, redirects, CORS/network failure, and encoded filenames with the real HTTP fixture server.
- [ ] 2.4 Enforce entry, streaming byte, and distinct-request limits and optional cancellation. Verify that chunked oversized responses, incorrect Content-Length, and abort stop further I/O without a partial Config. Release readers on every streaming failure, including injected read and decoding errors; cancel or abort any possibly live response before lock release. Verify upstream cancellation or connection closure in the HTTP fixture, release of already errored readers, and remaining cleanup after cancellation failure while preserving the original load error. Verify parse and binding failures keep core error types and virtual origins.
- [ ] 2.5 Add build:browser-adapter and check:browser-adapter moonx tasks, separate generated library and fixture files, and the freshness check in local checks and CI. Prove stale TypeScript is rejected without rewriting output, and browser consumers require neither Bun nor Node globals at runtime.
- [ ] 2.6 Add a runnable package guide and hosted-config example. Verify ordinary four-target checks and the required three-engine gate; do not depend on unfinished format, render, secret, or host-lifecycle stories.

## 3. Selected project files and bounded discovery

Bead: lander-4us.8.3

- [ ] 3.1 Add a selected-file mount over explicit relative-path and browser File pairs. Infer parent listings, reject duplicates and path collisions, and read File.text only for requested contents. Verify real file-input fallback in all three engines, including a large unrelated file that is never read.
- [ ] 3.2 Add the browser workspace convention helper that removes machine directories and bounds discovery to the mount root. Verify nested discovery, a narrower caller boundary, no outside listing, injected home variables, exact-name matching, and normal local/user overrides inside the mount.
- [ ] 3.3 Demonstrate one load that merges hosted defaults with selected project files in builder order. Verify values, reports, provenance, parse errors, and ambiguity without uploads or writes to selected files.
- [ ] 3.4 Add consumer examples for mapping File.name and webkitRelativePath explicitly, including directory-input fallback. Verify the selected-file and workspace discovery scenarios in required browser CI and keep all four core targets green.

## 4. Live read-only directory handles

Bead: lander-4us.8.4

- [ ] 4.1 Add a directory-handle mount using only caller-supplied handles, one-segment traversal, create:false, direct-child entries, and lazy file text reads. Verify a real directory handle with nested files in all three engines using OPFS-created test fixtures.
- [ ] 4.2 Verify equivalence with selected-file mounts, wrong-kind and missing entries, exact names, fresh content on a second load, and unchanged prior Config values. Assert that loading never creates directories or files.
- [ ] 4.3 Map denied and revoked operations to typed permission errors with no fallback to another mount or store. Use controlled denied-operation fixtures for error injection, alongside real-handle tests for successful I/O; do not claim the fixtures test native picker UI.
- [ ] 4.4 Document picker capability detection and file-input fallback in a headless consumer example. Verify that no library API opens a picker or requests permission, and run the required checks and browser gate.

## 5. Scoped OPFS persistence

Bead: lander-4us.8.5

- [ ] 5.1 Add explicit open_store(namespace, root~), write_text, and named-file remove operations under a library-owned application namespace. Require and validate the virtual root before storage access, and use it for the store read mount with the directory backend. Verify the supplied root in origins, reopening the same namespace at a different root, invalid-root rejection before OPFS access, save, awaited close, page reload on the same origin, and successful configuration load in all three engines.
- [ ] 5.2 Verify independent namespaces, relative path confinement, no writes during ordinary loads, and merging hosted defaults, a selected workspace, and stored overrides in one ordered builder.
- [ ] 5.3 Verify unsupported or blocked APIs, permission denial, quota failure, and failed write/close as typed errors without false success or fallback to localStorage/IndexedDB. Use real OPFS for the successful persistence path and controlled failures for exceptional paths.
- [ ] 5.4 Document explicit persistence, site-data lifetime, and recovery ownership. Do not depend on configuration rendering or add multi-file transactions, local-file editing, or automatic reload. Run all required checks and browser CI.

## 6. Consumer parity and final landing audit

Bead: lander-4us.8.6

- [ ] 6.1 Compare one shared explicit snapshot and run context in browser js with the same inputs on wasm, wasm-gc, js on Node, and native. Assert values, provenance, reports, parse/binding errors, and source order; verify reference results come from the same fixture revision.
- [ ] 6.2 Build an unrelated consumer without config/browser and verify that no browser API, generated browser bundle, or browser build tool becomes its runtime or consumer-build dependency. Verify the public browser package remains UI-free and the existing Node/Bun adapter tests still pass.
- [ ] 6.3 Audit every requirement and named scenario against actual tests and current-head CI. Verify browser task failure propagation, required ci-ok dependencies, engine availability, generated freshness, setup documentation, and no unexpected skipped baseline cases.
- [ ] 6.4 Record the support matrix using exact Playwright and browser build versions and actual job timings. State that browser execution is js output and pure-core portability is four-target coverage. Verify the consumer guides against the final API.
- [ ] 6.5 Run mise run format, mise run check, mise run test:node-adapter, and mise exec -- openspec validate --all --strict. Record current-head evidence and confirm that all preceding implementation PRs are merged. Do not publish or cut a release.

After group 6 merges, its PR maintainer owns a separate archive-only documentation
PR. Run `mise exec -- openspec archive add-browser-configuration` and strict
validation there. This maintenance PR follows the six implementation PRs; it is
not a prerequisite for merging group 6. Close the epic after the archive PR
merges. Do not leave the archive action inside a task that must be checked off
before the final implementation PR can merge.

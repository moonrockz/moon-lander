# Proposal: add-browser-configuration

## Why

The configuration core accepts file snapshots and explicit run inputs on all four
MoonBit targets. The native and Node/Bun adapters can fill these inputs from a
process. A browser application has different inputs: HTTP resources, files that
the user selects, directory handles, and storage for one web origin.

Add a browser adapter so that these inputs use the same parsing, merge,
provenance, reports, discovery, and binding rules. First prove that a compiled
MoonBit application can use the browser APIs in real browser engines.

## What Changes

- Add a browser feasibility spike that fetches TOML, applies an override, binds a
  typed section, and reports the result in Chromium, Firefox, and WebKit.
- Add `config/browser`, a js-only package. It supplies the core file request loop
  from explicit mounts. It does not import the Node adapter or read process state.
- Add URL mounts with a finite file manifest, selected-file mounts, and read-only
  directory-handle mounts. Use virtual paths and confine requests to mounted roots.
- Add explicit, scoped OPFS storage for configuration text. Loads remain read-only;
  writes happen only through the storage API that the application calls.
- Add a browser workspace convention helper that bounds discovery and removes
  machine directory sources. Preserve all core ordering and provenance rules.
- Add browser build tasks, checked-in FFI output, real-browser acceptance tests,
  and a required CI category. Each implementation story is one reviewable PR.

## Capabilities

### New Capabilities

- `browser-configuration`: configuration loading from browser-accessible inputs,
  mounted virtual paths, scoped persistence, and browser execution checks.

### Modified Capabilities

None. This change uses the existing configuration core, conventions, and binding
contracts. It adds browser I/O errors without changing `ConfigError` or `Platform`.

## Impact

- New package under `pkgs/lander/config/browser` and TypeScript browser adapters
  under `pkgs/lander/adapters/browser`.
- An unpublished browser fixture under `tests/`, with an exact Playwright version,
  a lockfile, and Chromium, Firefox, and WebKit tests.
- Moonx tasks under `scripts/`, exposed through mise. Bun remains the bundler.
- A narrow AGENTS.md exception for browser Web API access in these adapters.
  Process and filesystem automation still uses `moonbitlang/async`.
- The browser package stays UI-free. Moonbase owns selection dialogs and user
  interaction. Test pages may contain plain HTML inputs to exercise the APIs.

## Out of scope

- A browser UI package, a Moonbase implementation, or a browser command driver.
- Node shims, OS environment discovery, or access to unselected host directories.
- File watching, automatic reload, service workers, offline network caching,
  multi-file write transactions, and edits to user-selected local files.
- New formats, merge policies, secret resolution, or other unfinished core work.
- A new WebAssembly browser runtime or ABI bridge. The pure core remains portable
  and applications can continue to inject complete snapshots into their embedder.
- A release or publication to mooncakes.io.

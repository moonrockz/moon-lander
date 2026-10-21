# Browser feasibility fixture

This private harness proves task group 1 of `add-browser-configuration`. It is
not the public browser package. The fixture imports the configuration core,
TOML format, and `moonbitlang/async/js_async`; it does not import `config/host`.

From the workspace root:

```shell
mise trust
mise install
mise run browsers:install
mise run test:browser
mise run test:browser-failures
```

On Linux, use `mise run browsers:install -- --with-deps` to install browser system
dependencies too. Run installation before `mise run check`, which includes the
browser suite. The harness dependency and mise CLI are pinned to the same exact
Playwright version; `bun.lock` locks its transitive dependencies. Installation
uses `bun install --frozen-lockfile` and the suite checks the installed version.

`scripts/build-browser-fixture.mbtx` bundles the TypeScript boundary into a
checked-in inline FFI factory, compiles MoonBit to js, and bundles that application
with Bun's browser target. It rejects Node imports and forbidden runtime
references. `check:browser-fixture` checks only freshness and never rewrites the
generated file. Run `build:browser-fixture` after adapter changes.

`scripts/browser.mbtx` owns the loopback HTTP server on an OS-assigned port. The
same compiled fixture runs in all three Playwright projects. Loading, overrides,
binding, and origin inspection execute in the browser page, not in the test
runner. Tests assert `process`, `require`, and `Bun` are absent. Error cases use
HTTP 404, malformed TOML, and an invalid typed field.

`test:browser-failures` builds once, runs the successful suite, then reuses that
artifact for deliberate assertion failures and an empty browser installation
directory. It requires the specific failure messages and expected failed-test
counts, so an unrelated nonzero exit cannot satisfy those checks. No engine is
skipped or retried. This command is the browser CI job's gate.

The suite has a 120-second Playwright limit inside a 180-second MoonBit limit.
Installation has separate 5-minute dependency and 10-minute engine limits.
Structured concurrency cancels and joins the server and runner. Process
cancellation uses the async library's graceful termination with a 5-second hard
kill fallback. After each suite the task checks that its listener no longer
accepts connections. Output and test artifacts live under `_build/browser/`.

The browser API remains UI-free. The fixture page only loads the compiled
application and exports a test function. File selection UI belongs to later
unpublished fixtures or to consuming applications.

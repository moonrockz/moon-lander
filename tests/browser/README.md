# Browser feasibility fixture

This private harness exercises the production `config/browser` package and the
original feasibility proof. The fixture imports the configuration core, TOML,
the public browser package, and `moonbitlang/async/js_async`. It does not import
`config/host`. `tests/browser-consumer` is the runnable headless guide example.

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

`scripts/build-browser-adapter.mbtx` generates the production inline FFI.
`scripts/build-browser-fixture.mbtx` generates the separate fixture FFI, checks
production freshness, compiles the fixture and example to js once each, and
bundles both with Bun's browser target. It rejects Node imports and forbidden
runtime references. `check:browser-adapter` and `check:browser-fixture` never
rewrite generated files. Run their corresponding build tasks after source edits.

`scripts/browser.mbtx` owns the same-origin and cross-origin loopback servers on OS-assigned ports. The
same compiled fixture runs in all three Playwright projects. Loading, overrides,
binding, and origin inspection execute in the browser page, not in the test
runner. Tests assert `process`, `require`, and `Bun` are absent. Error cases use
HTTP statuses, redirect refusal, CORS, disconnection, malformed TOML, and typed
binding errors. Other cases exercise manifest/path policy, explicit run inputs,
quotas, caching, and no-progress through the public MoonBit API.

Real oversized, invalid UTF-8, and aborted streams must produce an observed
upstream stop. Controlled streams cover false Content-Length, errored reads,
and cleanup failures. A real compressed HTTP response proves wire size does not
bound decoded text.

`test:browser-failures` builds each application once, runs the successful suite, then reuses that
artifacts for deliberate assertion failures and an empty browser installation
directory. It requires the specific failure messages and expected failed-test
counts from the original smoke file, so an unrelated nonzero exit cannot satisfy those checks. No engine is
skipped or retried. This command is the browser CI job's gate.

The CI job runs in the pinned `mcr.microsoft.com/playwright` image, whose tag matches the Playwright
pin. The image holds the three engines and their OS packages, so CI runs `browsers:install` without
`--with-deps` and installs nothing with apt. The image has no C compiler, so CI runs the suite as
`mise run test:browser-zig -- --verify-failures`, and zig builds the native parity reference.
Change the image tag and digest in `.github/workflows/ci.yml` when you change the Playwright pin.

The suite has a 300-second Playwright limit inside a 420-second MoonBit limit.
The fixture build, with its four reference builds, has a 300-second limit.
Installation has separate 5-minute dependency and 10-minute engine limits.
Structured concurrency cancels and joins the server and runner. Process
cancellation uses the async library's graceful termination with a 5-second hard
kill fallback. After each suite the task checks that both listeners no longer
accept connections. Output and test artifacts live under `_build/browser/`.

The browser API remains UI-free. The fixture page loads the compiled
application, exports a test function, and holds plain file and directory inputs.
Playwright puts real files into these inputs; `selected.spec.ts` maps them to
selected-file mounts, records each `Blob` content read, and checks workspace
discovery. `directory.spec.ts` creates real OPFS directories and also wraps
handles to inject denied, revoked and pending operations. It uses the
`persistent.ts` fixture, a new persistent profile for each test, because WebKit
has no OPFS in an ephemeral context. `store.spec.ts` uses the same fixture to
save, reload and load an OPFS store, and injects storage failures. Both suites
first remove all OPFS entries of the test origin. Picker and selection UI
belongs to consuming applications.

`parity.spec.ts` compares the browser observation of the shared parity cases in
`tests/browser-parity` with the reference that `build:browser-fixture` makes on
wasm, wasm-gc, js on Node and native from the same checkout. Both sides start
with the same fixture revision digest. The task fails when Playwright reports a
skipped, flaky, interrupted or unrun case.

| Item | Version |
| --- | --- |
| Playwright | `1.64.1` |
| Chromium | `156.0.8078.4` (build `1248`) |
| Firefox | `157.0` (build `1555`) |
| WebKit | `27.2` (build `2370`) |

Browser execution uses js output. The pure core is portable across the four
targets, which `mise run check:config` and the parity references check.

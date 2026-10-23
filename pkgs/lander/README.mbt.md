# Moon-Lander

Moon-Lander is an application framework for MoonBit with no user interface. It
gives a MoonBit program what .NET hosting and configuration give a .NET program:
layered configuration from files, environment variables, and the command line,
typed binding, and a host that runs commands and services with clear exit codes.

The provisional module name is `moonrockz/moon-lander`, imported as `@lander`.
The module has not been published. The pure core and formats run on `wasm`,
`wasm-gc`, `js`, and `native`. File host adapters support `native` and `js`; the
browser adapter supports `js`.

## The layer stack

A run moves down this stack. Each layer uses only the layers below it. The
configuration core is pure: hosts give it files and environment values, so the
same inputs give the same configuration on every target.

```layers
Hosting | @lander, @hosting: services, lifecycle, exit codes (first slice)
Binding | @config.bind: typed values with source-aware errors
Conventions | @conventions: where configuration files are found
Configuration core | @config: sources, file tree, pure load, merge
Formats | TOML, YAML, JSON5 and Ion; linked set selected by a virtual package
```

Host adapters sit beside the core. On `native` and `js` they read the files that
a load asks for. A `wasm` host gives the files itself.

The mediator also sits beside the stack. It is pure and uses no other layer: the
parts of an application send requests and publish events through typed values,
and middleware holds the cross-cutting steps. The async mediator adds handlers
that wait, on `wasm`, `js` and `native`.

## What exists today

| Layer | Package | Status |
| --- | --- | --- |
| Configuration core | [`config`](config/README.mbt.md) | Value tree, key paths, sources (defaults, files, environment, overrides) and the builder, file tree and the pure load, merge with null rules, provenance, merge policies, lazy secrets, redaction, display helpers and typed errors |
| Formats | [`formats`](formats/README.mbt.md), `config/formats/*` | TOML, YAML with default/strict profiles, JSON/JSON5 and Ion; default and TOML-only linked sets |
| Host adapters | [`config/host`](config/host/README.mbt.md) | `native` and `js` read files and fill missing variables and the working directory |
| Browser adapter | [`config/browser`](config/browser/README.mbt.md) | js browser URL mounts with explicit manifests, run inputs, limits, cancellation, and typed boundary errors |
| Conventions | [`config/conventions`](config/conventions/README.mbt.md) | Walk-up discovery in three layouts, system and global user directories on every platform, local and user overrides, explicit project file, ambiguity, legacy fallback, stop boundary, isolated mode; workspace and environment parts come next |
| Binding | [`config`](config/README.mbt.md) | `bind`, `bind_root`, and `bind_or` over a default, with source-aware decode errors; validation comes next |
| Mediator | [`mediator`](mediator/README.mbt.md) | Typed senders, publish topics that run every handler and report every failure in one `PublishFailed`, a middleware pipeline with fixed order and short-circuit, an explicit context value and `MediatorError`; one synchronous API on all four targets |
| Async mediator | [`mediator/async`](mediator/async/README.mbt.md) | Async senders and topics with sequential and concurrent publish, caller cancellation, the `timeout` middleware, async middleware with a sync `finally_`, and `from_sync` for core values; `wasm`, `js` and `native` |
| Hosting | `hosting`, `@lander.cli` | First slice: a builder with hosted services that have `start` and `stop` hooks, a services factory, and `@hosting.run` on `native` and `js`, which gives exit code 0 or 1. Arguments, lifecycle events, signals and configuration come next |

The [Configuration](config/README.mbt.md), [Mediator](mediator/README.mbt.md) and
[Async mediator](mediator/async/README.mbt.md) chapters show the API that exists, with examples that the tests compile and run. The
[design overview](../../docs/design/overview.md) shows the full design of all
four changes. The OpenSpec changes in `openspec/changes/` hold the requirements.

## Use the module

Add the module, then import the packages that you use in `moon.pkg`:

```moonbit notest
import {
  "moonrockz/moon-lander/config" @config,
  "moonrockz/moon-lander/config/formats/toml" @toml,
}
```

The root package exports `version()`, which gives the module version.

## Run a host

`@lander.cli(name, args)` starts a host builder for an application. Each step
of the pipeline gives a new builder:

| Step | What it does |
| --- | --- |
| `@lander.cli("acme", args)` | Starts the builder with the application name and the arguments |
| `@hosting.service(name, start=.., stop=..)` | Adds a hosted service. Both hooks are optional and can wait |
| `@hosting.build(factory)` | Gives the `Host`. It does no I/O, so a host can run more than one time |

```mbt check
///|
/// The host of the application `acme`. Its one service writes each hook call
/// into `log`.
fn acme_host(log : Array[String]) -> @hosting.Host[Unit] {
  @lander.cli("acme", ["greet"])
  |> @hosting.service(
    "greeter",
    start=_ => log.push("greeter started"),
    stop=_ => log.push("greeter stopped"),
  )
  |> @hosting.build(_ => ())
}

///|
test "build the acme host" {
  let log = []
  ignore(acme_host(log))
  // The build runs no hook.
  assert_eq(log, [])
}
```

On `native` and `js`, `@hosting.run(host, command)` runs the host and gives a
`RunOutcome`. It does not end the process. The run calls the factory one time,
runs the `start` hooks in registration order, runs the command, and runs the
`stop` hooks in reverse order:

| Result | Exit code |
| --- | --- |
| All hooks and the command succeed | 0 |
| The factory, a hook or the command raises an error | 1, and `failures` holds each error |

A failed `start` hook skips the command and the other `start` hooks. The
services that started still get their `stop` hooks. The test `cli_test.mbt`
runs `acme_host` this way. A later version adds a run function for every
target, so this example can run there too.

## Choose which parsers the executable links

Import `formats` to use the default set, or select `formats/toml` with one
`overrides` entry in the executable's `moon.pkg`. The caller keeps the same
`@formats.formats()` call. MoonBit virtual packages let the executable replace
the default implementation at build time, so unused parsers can be omitted.

The [format selection guide](formats/README.mbt.md) explains the language
feature, shows the registration loop and a custom TOML/YAML implementation,
and describes how the output-size and parser-marker checks verify trimming.

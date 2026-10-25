# Moon-Lander

Moon-Lander is an application framework for MoonBit with no user interface. It
gives a MoonBit program what .NET hosting and configuration give a .NET program:
layered configuration from files, environment variables, and the command line,
typed binding, and a host that runs commands and services with clear exit codes.

The provisional module name is `moonrockz/moon-lander`, imported as `@lander`.
The module has not been published. The configuration packages are in the module
[`moonrockz/moon-lander-config`](../config/README.mbt.md): its pure core and
formats run on `wasm`, `wasm-gc`, `js`, and `native`, its file host adapters
support `native` and `js`, and its browser adapter supports `js`.

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

Logging sits at the bottom, beside core. Each part writes structured events
through one `Logger` trait, and the application brings the backend that gets them.
It uses only the MoonBit core library, so each module above can take a `&Logger`.

## What exists today

| Layer | Package | Status |
| --- | --- | --- |
| Configuration core | [`moonrockz/moon-lander-config`](../config/README.mbt.md) | Value tree, key paths, sources (defaults, files, environment, overrides) and the builder, file tree and the pure load, merge with null rules, provenance, merge policies, lazy secrets, redaction, display helpers and typed errors |
| Formats | [`formats`](../config/formats/README.mbt.md), `parsers/*` in `moonrockz/moon-lander-config` | TOML, YAML with default/strict profiles, JSON/JSON5 and Ion; default and TOML-only linked sets |
| Host adapters | [`host`](../config/host/README.mbt.md) in `moonrockz/moon-lander-config` | `native` and `js` read files and fill missing variables and the working directory |
| Browser adapter | [`browser`](../config/browser/README.mbt.md) in `moonrockz/moon-lander-config` | js browser URL mounts with explicit manifests, run inputs, limits, cancellation, and typed boundary errors |
| Conventions | [`conventions`](../config/conventions/README.mbt.md) in `moonrockz/moon-lander-config` | Walk-up discovery in three layouts, system and global user directories on every platform, local and user overrides, explicit project file, ambiguity, legacy fallback, stop boundary, isolated mode; workspace and environment parts come next |
| Binding | [`moonrockz/moon-lander-config`](../config/README.mbt.md) | `bind`, `bind_root`, and `bind_or` over a default, with source-aware decode errors; validation comes next |
| Mediator | [`moonrockz/moon-lander-mediator`](../mediator/README.mbt.md) | Typed senders, publish topics that run every handler and report every failure in one `PublishFailed`, a middleware pipeline with fixed order and short-circuit, an explicit context value and `MediatorError`; one synchronous API on all four targets |
| Async mediator | [`moonrockz/moon-lander-mediator/async`](../mediator/async/README.mbt.md) | Async senders and topics with sequential and concurrent publish, caller cancellation, the `timeout` middleware, async middleware with a sync `finally_`, and `from_sync` for core values; `wasm`, `js` and `native` |
| Logging | [`moonrockz/moon-lander-logging`](../logging/README.mbt.md) (`@logging`) | The bring-your-own `Logger` trait, six levels, structured events with Serilog-style message templates, a level check before each event, the null and in-memory loggers, `min_level`, `fan_out` and `with_category`, and text lines; one API on all four targets |
| Hosting | [`moonrockz/moon-lander-hosting`](../hosting/README.mbt.md) (`@hosting`), `@lander.cli` | First slice: a builder with hosted services that have `start` and `stop` hooks, a services factory, and `@hosting.run` on `native` and `js`, which gives exit code 0 or 1. Arguments, lifecycle events, signals and configuration come next |

The [Configuration](../config/README.mbt.md), [Mediator](../mediator/README.mbt.md),
[Async mediator](../mediator/async/README.mbt.md) and [Logging](../logging/README.mbt.md) chapters show the API that exists, with examples that the tests compile and run. The
[design overview](../../docs/design/overview.md) shows the full design of all
four changes. The OpenSpec changes in `openspec/changes/` hold the requirements.

## Use the module

Add the modules, then import the packages that you use in `moon.pkg`. The
configuration packages are in the module `moonrockz/moon-lander-config`:

```moonbit notest
import {
  "moonrockz/moon-lander-config" @config,
  "moonrockz/moon-lander-config/parsers/toml" @toml,
}
```

The root package exports `version()`, which gives the module version.

## Run a host

`@lander.cli(name, args)` starts a host builder for an application. Each step
of the pipeline gives a new builder:

| Step | What it does |
| --- | --- |
| `@lander.cli(name, args)` | Starts the builder with an `AppName` and the arguments |
| `@hosting.service(name, start=.., stop=..)` | Adds a hosted service. `name` is a `ServiceName` or a `String` that the step parses. Both hooks are optional and can wait. A second service whose name equals another or differs from it only in letter case raises `DuplicateService` |
| `@hosting.build(factory)` | Gives the `Host`. It does no I/O, so a host can run more than one time |

Names and exit codes are types, not raw strings and numbers. Each type has one
smart constructor, which is the only way to make a value, so a value that breaks
its rule cannot exist:

| Type | Parse | Rule |
| --- | --- | --- |
| `AppName` | `AppName::parse("acme")` | Starts with an ASCII letter; then only ASCII letters, digits, `-` and `_` |
| `ServiceName` | `ServiceName::parse("db")` | Safe as one file path component: starts with a Unicode identifier start character (`XID_Start`, letters and letter numbers); then identifier characters (`XID_Continue`: letters, combining marks, digits, `_` and a few connectors), `-` and `.`; no invisible character; does not end with `.`; is not a Windows device name such as `CON` or `com1`; at most 128 bytes in UTF-8 |
| `ExitCode` | `ExitCode::from_int(3)`, or `ExitCode::success()` and `ExitCode::failure()` | 0 to 255 |

A parse that fails raises an error with the text and the broken rule:
`AppNameError` for `AppName`, and `HostError` for the other types. `AppName`,
`AppNameError` and `AppNameRule` come from `moonrockz/moon-lander-core`, and
`@lander` re-exports them. A
program parses its names one time, where they are written. `cli` takes the name
first, so the text can flow through the parse into the pipeline, as in
`"acme" |> @lander.AppName::parse |> @lander.cli(args)`. A program whose
`main` can raise, `fn main raise { ... }`, lets a bad name stop the program at
start.

With no `command` step the host accepts no arguments.

```mbt check
///|
/// The host of the application `acme`. Its one service writes each hook call
/// into `log`.
fn acme_host(log : Array[String]) -> @hosting.Host[Unit] raise {
  "acme"
  |> @lander.AppName::parse
  |> @lander.cli([])
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
| An argument that the command does not define | 2, `UsageError` |

A failed `start` hook skips the command and the other `start` hooks. The
services that started still get their `stop` hooks. The test `cli_test.mbt`
runs `acme_host` this way. A later version adds a run function for every
target, so this example can run there too.

## Choose which parsers the executable links

Import `moonrockz/moon-lander-config/formats` to use the default set, or select
`moonrockz/moon-lander-config/formats/toml` with one
`overrides` entry in the executable's `moon.pkg`. The caller keeps the same
`@formats.formats()` call. MoonBit virtual packages let the executable replace
the default implementation at build time, so unused parsers can be omitted.

The [format selection guide](../config/formats/README.mbt.md) explains the language
feature, shows the registration loop and a custom TOML/YAML implementation,
and describes how the output-size and parser-marker checks verify trimming.

Starting settings can supply the variable set and absolute working directory on
any target. Later hosting steps replace them before the run. An environment name
is a parsed `@lander.EnvironmentName` default. Parse it with
`@lander.EnvironmentName::parse`. A flag or the run's prefixed environment
variable takes precedence. The default enables the environments part. Files need
a primary part such as `@hosting.app_dirs()`. The factory and command read the resolved name
through `environment.environment_name` on their contexts.

```mbt check
///|
test "explicit starting settings" {
  let host = @lander_core.AppName::parse("acme")
    |> @lander.cli([], env_vars={ "ACME_PORT": "8080" },
      working_dir=@lander_core.AbsolutePath::parse("/work"), environment=@lander.EnvironmentName::parse("Staging"))
    |> @hosting.env_vars(({ "ACME_PORT": 9090, "ACME_DEBUG": true } : Json))
    |> @hosting.working_dir(@lander_core.AbsolutePath::parse("/other"))
    |> @hosting.build(_ => ())
  ignore(host)
}
```

The factory and command contexts expose the run variable snapshot as an immutable
`@immut/sorted_map.SortedMap[String, String]` in deterministic key order. Builder
and `env_vars` steps snapshot their inputs when applied. A missing native or js
process working directory ends the run with code 1 before any file read or hook.

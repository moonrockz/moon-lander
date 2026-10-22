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
Hosting | @lander: arguments, lifecycle, exit codes (planned)
Binding | @config.bind: typed values with source-aware errors
Conventions | @conventions: where configuration files are found
Configuration core | @config: sources, file tree, pure load, merge
Formats | TOML, YAML, JSON5 and Ion; linked set selected by a virtual package
```

Host adapters sit beside the core. On `native` and `js` they read the files that
a load asks for. A `wasm` host gives the files itself.

The mediator also sits beside the stack. It is pure and uses no other layer: the
parts of an application send requests and publish events through typed values,
and middleware holds the cross-cutting steps.

## What exists today

| Layer | Package | Status |
| --- | --- | --- |
| Configuration core | [`config`](config/README.mbt.md) | Value tree, key paths, sources (defaults, files, environment, overrides) and the builder, file tree and the pure load, merge with null rules, provenance, merge policies, lazy secrets, redaction, display helpers and typed errors |
| Formats | [`formats`](formats/README.mbt.md), `config/formats/*` | TOML, YAML with default/strict profiles, JSON/JSON5 and Ion; default and TOML-only linked sets |
| Host adapters | [`config/host`](config/host/README.mbt.md) | `native` and `js` read files and fill missing variables and the working directory |
| Browser adapter | [`config/browser`](config/browser/README.mbt.md) | js browser URL mounts with explicit manifests, run inputs, limits, cancellation, and typed boundary errors |
| Conventions | [`config/conventions`](config/conventions/README.mbt.md) | Walk-up discovery in three layouts, system and global user directories on every platform, local and user overrides, explicit project file, ambiguity, legacy fallback, stop boundary, isolated mode; workspace and environment parts come next |
| Binding | [`config`](config/README.mbt.md) | `bind`, `bind_root`, and `bind_or` over a default, with source-aware decode errors; validation comes next |
| Mediator | [`mediator`](mediator/README.mbt.md) | Typed senders, publish topics, a middleware pipeline with fixed order and short-circuit, an explicit context value and `MediatorError`; one synchronous API on all four targets |
| Hosting | `@lander` | Planned |

The [Configuration](config/README.mbt.md) and [Mediator](mediator/README.mbt.md)
chapters show the API that exists, with examples that the tests compile and run. The
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

## Choose which parsers the executable links

Import `formats` to use the default set, or select `formats/toml` with one
`overrides` entry in the executable's `moon.pkg`. The caller keeps the same
`@formats.formats()` call. MoonBit virtual packages let the executable replace
the default implementation at build time, so unused parsers can be omitted.

The [format selection guide](formats/README.mbt.md) explains the language
feature, shows the registration loop and a custom TOML/YAML implementation,
and describes how the output-size and parser-marker checks verify trimming.

# Moon-Lander

Moon-Lander is an application framework for MoonBit with no user interface. It
gives a MoonBit program what .NET hosting and configuration give a .NET program:
layered configuration from files, environment variables, and the command line,
typed binding, and a host that runs commands and services with clear exit codes.

The provisional module name is `moonrockz/moon-lander`, imported as `@lander`.
The module has not been published. Every package runs on `wasm`, `wasm-gc`, `js`,
and `native`.

## The layer stack

A run moves down this stack. Each layer uses only the layers below it. The
configuration core is pure: hosts give it files and environment values, so the
same inputs give the same configuration on every target.

```layers
Hosting | @lander: arguments, lifecycle, exit codes (planned)
Binding | typed values with source-aware errors (planned)
Conventions | where configuration files are found (planned)
Configuration core | @config: sources, file tree, pure load, merge
Formats | TOML today; YAML, JSON5 and Ion later
```

Host adapters sit beside the core. On `native` and `js` they read the files that
a load asks for. A `wasm` host gives the files itself.

## What exists today

| Layer | Package | Status |
| --- | --- | --- |
| Configuration core | [`config`](config/README.mbt.md) | Value tree, key paths, sources and the builder, file tree and the pure load, merge, typed errors |
| Formats | `config/formats/toml` | TOML strings, numbers, Booleans, arrays, and tables |
| Configuration core, rest | `config` | Environment variables, provenance, merge policies, secrets, redaction, and helpers come next |
| Host adapters | `config/host` | Planned |
| Conventions | | Planned |
| Binding | | Planned |
| Hosting | `@lander` | Planned |

The [Configuration](config/README.mbt.md) chapter shows the API that exists, with
examples that the tests compile and run. The
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

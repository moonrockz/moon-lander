# Select configuration formats at build time

Moon-Lander lets an application choose which configuration parsers it links.
The default is TOML, YAML, JSON/JSON5 and Ion. One override in the executable's
`moon.pkg` selects TOML only, without changing the application source. An
application can also supply its own format set.

This reduces the output size of applications that need fewer formats. The
selection uses MoonBit virtual packages: callers depend on one interface, and
the executable chooses its implementation when it builds.

## Use the linked format set

Import the core and the virtual package in the caller's `moon.pkg`:

```moonbit notest
///|
import {
  "moonrockz/moon-lander-config" @config,
  "moonrockz/moon-lander-config/formats",
}
```

`@formats.formats()` returns the selected format descriptors. Register them with
the configuration builder. This example supplies the file text itself, so it
runs on wasm, wasm-gc, js and native:

```mbt check
///|
test "load a file with the linked configuration formats" {
  let mut builder = @config.builder()
  for format in @formats.formats() {
    builder = @config.format(builder, format)
  }
  builder = builder
    |> @config.working_dir("/app")
    |> @config.file("settings.toml")
  let files = @config.FileTree::new(complete=true).with_file(
    "/app/settings.toml", "[server]\nport = 8080",
  )
  guard @config.load(builder, files) is Done(config) else {
    fail("a complete file tree must finish loading")
  }
  assert_eq(@config.get_text(config, "server.port"), "8080")
}
```

With no override, the returned formats have this order:

| Format | Extensions |
| --- | --- |
| TOML | `toml` |
| YAML | `yaml`, `yml` |
| JSON5 | `json`, `json5` |
| Ion | `ion` |

The JSON5 parser handles both JSON extensions. The pure `config` package does
not import `formats`; callers opt into this linked set. An application can
continue to import individual format packages and register them directly.

## Ship a TOML-only executable

Add the shipped implementation to the main executable's `moon.pkg`:

```moonbit notest
import {
  "moonrockz/moon-lander-config" @config,
  "moonrockz/moon-lander-config/formats",
}

pkgtype(kind: "executable")

options(
  overrides: [ "moonrockz/moon-lander-config/formats/toml" ],
)
```

The application still imports `formats` and calls `@formats.formats()`. It now
gets one descriptor, TOML, and the builder example above stays the same. Files
with other extensions raise `UnsupportedFormat` unless the application registers
another parser itself.

The override changes the implementation selected for the executable, including
calls through packages that depend on the virtual interface. Filtering the
default array at runtime does not provide this build-time selection. A direct
import that keeps another parser reachable can still link that parser even when
the virtual package selects TOML only.

Trimming applies to the executable's linked code. The module may still declare
and download dependencies used by its other packages.

## Supply your own combination

For TOML and YAML, create a package such as `my-formats` in your application
module. Its `moon.pkg` names the virtual package it implements:

```moonbit notest
import {
  "moonrockz/moon-lander-config" @config,
  "moonrockz/moon-lander-config/parsers/toml",
  "moonrockz/moon-lander-config/parsers/yaml",
}

virtual(implement: "moonrockz/moon-lander-config/formats")
```

Its `formats.mbt` supplies the function:

```moonbit notest
///|
pub fn formats() -> Array[@config.Format] {
  [@toml.format(), @yaml.format()]
}
```

For a module named `acme/myapp`, select that package in the main executable:

```moonbit notest
options(
  overrides: [ "acme/myapp/my-formats" ],
)
```

The caller keeps the same import and builder loop. Moon checks each
implementation against the virtual package's interface. The repository's
`tests/formats-mix` and `tests/formats-custom` packages exercise this arrangement
with a consumer-defined TOML/YAML implementation.

## How MoonBit virtual packages enable this

A virtual package declares a public contract that different packages can
implement. Moon selects an implementation at build time. Callers import the
virtual package, so choosing another implementation does not change their code.
See the [MoonBit virtual-package guide](https://docs.moonbitlang.com/en/latest/language/packages.html#virtual-packages).

Moon-Lander's `formats/moon.pkg` declares a default implementation:

```moonbit notest
virtual(has_default: true)
```

The hand-written `formats/pkg.mbti` defines its contract:

```moonbit notest
package "moonrockz/moon-lander-config/formats"

import {
  "moonrockz/moon-lander-config",
}

fn formats() -> Array[@config.Format]
```

The interface imports the module root without an alias, because the `pkg.mbti`
syntax does not accept one. It names the type with `@config`, the alias that
the package gives the import in its `moon.pkg`.

The interface uses `fn` without `pub`. Implementations provide a matching
`pub fn`; the `Format` type stays in the configuration core,
`moonrockz/moon-lander-config` (`@config`). MoonBit's
current virtual-package interface supports plain functions, which is why this
contract is a function returning descriptors.

| MoonBit declaration | Role in Moon-Lander |
| --- | --- |
| `virtual(has_default: true)` | Uses the four-format implementation when the executable supplies no override |
| `pkg.mbti` | Defines the `formats()` function that every implementation must supply |
| `virtual(implement: "moonrockz/moon-lander-config/formats")` | Marks the shipped TOML package or a consumer package as an implementation |
| `options(overrides: ["…"])` | Selects that implementation from the executable's package manifest |

The selected implementation determines the parser functions made reachable by
`formats()`. A build can omit unused parser code when no other code references
it. The configuration builder then registers the returned descriptors at
runtime, and file extensions choose among those registered formats.

MoonBit currently documents virtual packages as experimental. These examples
use Moon-Lander's pinned toolchain. The [package configuration reference](https://docs.moonbitlang.com/en/latest/toolchain/moon/package.html#virtual-package)
describes the declarations; `pkgtype(kind: "executable")` and `virtual(...)`
are the forms used by the repository's current manifests.

## What the checks prove

Run `mise run check:formats` to build and run the default, TOML-only and custom
applications on wasm, wasm-gc, js and native. The default and TOML-only
applications have identical source. The check requires every trimmed release
output to be smaller and contain no selected YAML, JSON5 or Ion parser
diagnostic marker. It scans UTF-8 and UTF-16LE strings and first requires those
markers to exist in the default output. It also proves that a reachable YAML
import fails the trimming check.

Run `mise run check:formats-registry` before publication. It packages the
candidate, serves the checksummed archive from a loopback registry, and repeats
the checks in an isolated consumer outside `moon.work`. This verifies registry
resolution and the installed virtual interface on all four targets. Its
third-party archives come from the pinned registry cache populated by the
preceding workspace checks.

After an authorized candidate upload, `mise run check:formats-published` uses
the public registry with an isolated cache. It reports the archive checksum and
checks the published virtual interface against the candidate. A missing version
fails the command. Record the candidate source SHA, checksum and results in
release gate `lander-4us.9`; that gate must close before the Moon-Lander GitHub
release or candidate promotion. Publication still requires owner approval.

# Linked configuration formats

Import `moonrockz/moon-lander/formats` and register each value returned by
`formats()` with `@config.format`. The default implementation returns TOML,
YAML, JSON5 and Ion in that order. JSON5 handles both `.json` and `.json5`;
YAML handles `.yaml` and `.yml`.

To link only TOML, add one override to the application's main `moon.pkg`:

```moonbit notest
options(
  "is-main": true,
  overrides: [ "moonrockz/moon-lander/formats/toml" ],
)
```

The application source stays the same. The `config` package does not import
this virtual package. An application that registers individual formats directly
can continue to do so.

For another format set, create an implementation package:

```moonbit notest
import {
  "moonrockz/moon-lander/config",
  "moonrockz/moon-lander/config/formats/toml",
  "moonrockz/moon-lander/config/formats/yaml",
}

options("implement": "moonrockz/moon-lander/formats")
```

Its `formats.mbt` supplies the interface:

```moonbit notest
pub fn formats() -> Array[@config.Format] {
  [@toml.format(), @yaml.format()]
}
```

Select that package with the main package's `overrides` entry. The executable
fixtures under `tests/formats-*` verify the default, shipped TOML override, and
application-defined TOML/YAML override on all four targets.

Run `mise run check:formats` to compare release output sizes, check that the
trimmed output contains no YAML, JSON5 or Ion parser diagnostic markers, and
prove that a reachable YAML import fails the trimming check. The scan checks
both UTF-8 and UTF-16LE strings and requires every marker to exist in the default
output, so a missing marker cannot silently weaken the check.

Run `mise run check:formats-registry` before publication. It packages the current
candidate with `moon package`, serves that archive from a loopback registry,
and runs the same checks in a temporary consumer outside the workspace. Moon
resolves the module from a registry index and downloads the checksummed archive
into an isolated cache. The test requires an actual candidate download and the
installed hand-written virtual interface. Third-party archives come from the
pinned registry cache populated by the preceding workspace checks. No module is
published. Publishing to mooncakes.io still requires the owner's approval.

After an authorized candidate upload, `mise run check:formats-published` repeats
the consumer checks using the public registry and an isolated cache. It reports
the downloaded archive checksum and checks the published virtual interface
against the candidate. A missing version fails the command. Record the candidate
source SHA, checksum and results in release gate `lander-4us.9`; the gate must
close before the Moon-Lander GitHub release or candidate promotion.

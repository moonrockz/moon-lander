# Moon-Lander library

The provisional module name is `moonrockz/moon-lander`, imported as `@lander`.
This module has not been published. The root package exports `version()` to verify
the workspace builds and tests on `wasm`, `wasm-gc`, `js`, and `native`.

## Configuration core

The configuration core is in progress. The OpenSpec change
`openspec/changes/add-configuration-core` holds its design and requirements.

| Package | Contents |
| --- | --- |
| `config` (`@config`) | `ConfigValue` over Ion, `KeyPath`, in-memory sources, the default merge, `Config::get`, and `get_text` |
| `config/formats/toml` | The TOML format: strings, integers, floats, Booleans, arrays, and tables |

The sources merge in list order, so a later source wins. Two structs merge field
by field, and a list replaces a list:

```moonbit nocheck
let config = @config.build([
  @config.in_memory(@toml.parse(text, origin="app.toml"), name="app.toml"),
  @config.in_memory_pairs([("project.name", @config.string("demo"))]),
])
@config.get_text(config, "project.name") // "demo"
```

All packages are pure and run on all four targets. They do not read files or the
process environment.

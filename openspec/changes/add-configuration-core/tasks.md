# Tasks: add-configuration-core

Epic: lander-4us.2

Each group is one story. The design is in `design.md`. The requirements are in
`specs/configuration-core/spec.md`. Run `mise run check` at the end of each group.
Run `mise run format` before each commit.

## 1. Infrastructure: Windows CI leg and Bun pin

Bead: lander-4us.2.1

- [x] 1.1 Add a windows-latest leg to `.github/workflows/ci.yml` that builds and tests the native and js targets, with the MoonBit core library installed by the Windows installer; verify that the leg passes on the current code.
- [x] 1.2 Pin Bun in `.config/mise/config.toml` with a comment that says the js host adapter build uses it; verify that `mise install` installs it on Linux, macOS, and Windows CI.

## 2. Tracer bullet: in-memory and TOML sources, merge, get

Bead: lander-4us.2.2

- [x] 2.1 Add `moonrockz/ion@0.6.0` and `moonbit-community/toml@0.5.0` to `pkgs/lander/moon.mod`, create the packages `config` and `config/formats/toml`, and verify that `mise run validate` and `mise run build` pass.
- [x] 2.2 Add a minimal `ConfigValue` over `@ion.Ion` with a struct-root check, a dotted `KeyPath::parse` without quoting, and `Config::get`; verify with unit tests for a hit and a miss.
- [x] 2.3 Add an in-memory source from a value tree and from flat key-path pairs; verify the "Flat key-path pairs" and "Later pair wins" scenarios with unit tests.
- [x] 2.4 Add the TOML format for strings, integers, floats, Booleans, arrays, and tables, with `ConfigError::Parse`; verify with unit tests.
- [x] 2.5 Add the default merge (overlay wins, structs merge, lists replace) and `build` over an ordered list of sources; verify the "Later source wins" and "Structs merge and arrays replace" scenarios.
- [x] 2.6 Add a `get_text` helper and one moonspec acceptance scenario in `tests/` that merges an in-memory source over a TOML snapshot and gets `project.name`; verify that the scenario passes on all four targets.

## 3. Value tree and key path rules

Bead: lander-4us.2.3

- [x] 3.1 Enforce the `ConfigValue` invariants (text field names, unique fields, struct root), keep field order, and add `from_json` and `to_ion`; verify the "Root is not a struct" and "Field order stays" scenarios.
- [x] 3.2 Complete `KeyPath`: quoted names, escapes, `to_string` round trip, and `ConfigError::InvalidKeyPath`; verify the key path scenarios and a parse/print round-trip property test.
- [x] 3.3 Treat `sexp` as a list and apply the struct annotation rule (design D2); verify with unit tests.

## 4. Complete merge rules and provenance

Bead: lander-4us.2.4

- [x] 4.1 Add null-overlay handling and null-field removal from the result; verify the "Null does not unset" and "Null with no base value" scenarios.
- [x] 4.2 Make merge copy only changed paths and keep inputs unchanged; verify "Inputs do not change" and "New keys follow base keys", plus an associativity property test over generated trees in which no path is a struct in one tree and a leaf in another (design D8).
- [x] 4.3 Add the provenance map and stale-record removal ported from morphir-moonbit `merge`, over the `Origin` type that group 14 declares; verify the "Winning origins" and "Stale records go" scenarios, the origin part of "Defaults from JSON", and that excluded values have no provenance record.
- [x] 4.4 Add the Morphir kind names (`SourceKind::report_name`) and `local-override` to the `SourceReport` that group 5 adds (kind, name, priority, path, candidates, status, and warnings); verify the "Report order and status" and "File role names" scenarios.

## 5. Source model: selection, file source, ambiguity, exclusion

Bead: lander-4us.2.5

- [x] 5.1 Add `SourceSelection[T]`, `ConfigBuilder`, `add`, `SourceReport`, and the defaults source, over the `SourceKind` and `FileRole` (with `LocalOverride`) types that group 14 declares; verify "Skip a source" with a skipped environment source, "Same kind at two positions", and the value and report of "Defaults from JSON" (4.3 verifies its origin).
- [x] 5.2 Add display priorities with the defaults by kind and role (local override 390), the in-memory rule, and `ConfigError::SourceOrder`; verify the "Default priorities", "Override file priorities", and "Decreasing priority" scenarios.
- [x] 5.3 Add `FileTree` (with `with_listing`, `with_file`, and `with_missing`), `FileRequest`, `LoadStep[T]`, and the pure `@config.load(builder, tree)`; verify the "Incomplete tree asks for files", "Complete tree never asks", "Absence record answers a request", and "Missing directory answers its children" scenarios.
- [x] 5.4 Add `Platform`, `LoadContext` (with `env_vars` and `working_dir`), `@config.env_vars`, `@config.working_dir`, `Expansion`, `SourceProvider`, `@config.provider`, `@config.platform`, and `ConfigWarning::Note`, and expand providers in place during `@config.load`; verify the three source provider scenarios.
- [x] 5.5 Add `Format`, the builder format registry (`format`, `formats`, `parse_file`), and the explicit file source over a `FileTree` that joins a relative path to the working directory; verify the format registry scenarios, "Extension selects the format", "Missing explicit file", "Unregistered extension", and "Relative path joins the working directory".
- [x] 5.6 Add the candidate-list file source and the exact-name existence check over listings, and raise the `ConfigError::Ambiguous(display~, location~, candidates~)` case that group 14 declares when more than one candidate exists; verify the candidate ambiguity scenarios and "Name match is exact".
- [x] 5.7 Add `ConfigSource::exclude(paths, warn~)`, `ConfigWarning::KeyRemoved`, and `SourceReport.warnings`; verify the three source subtree exclusion scenarios.
- [x] 5.8 Document the source model in the `config` package guide `pkgs/lander/config/README.mbt.md`, linked from `pkgs/lander/README.md`, with examples that run as doc tests; verify with `mise run test`.

## 6. Environment and overrides sources

Bead: lander-4us.2.6

- [x] 6.1 Port the environment key mapping (prefix in any case, leading `_`, `__`, lowercase, empty segment error) and reserved names; verify all environment name and reserved name scenarios.
- [x] 6.2 Port value typing and the shorter-path-wins order from morphir-moonbit; verify the "Typed values", "JSON list value", "Invalid JSON stays text", "Integer out of range", and both shorter-path scenarios, the last with two input orders.
- [x] 6.3 Record the variable name in each environment origin, support `Explicit` variables, read `Discover` variables from the builder variable set (`@config.env_vars`), and give a skipped source for `Skip`; verify "Environment origin names the variable", "Explicit environment variables", "Discover environment with no host", "Skip a source" with the environment selection, and the environment-source parts of "Host adapter fills the inputs" and "Adapter uses the given values".
- [x] 6.4 Add the overrides source; verify the "Overrides beat the environment" scenario.

## 7. TOML date and time mapping

Bead: lander-4us.2.7

- [x] 7.1 Map TOML date-time values as `pkgs/notebooks` does and keep `Int64` exact; verify the "TOML date and time values" and "Large TOML integer" scenarios.

## 8. YAML format with default and strict profiles

Bead: lander-4us.2.8

- [x] 8.1 Add `moonbit-community/yaml@0.0.8` and the `config/formats/yaml` package with an event-based builder that keeps line and column; verify "Core schema scalars" and that the builder matches `Yaml::load_from_string` on the library examples.
- [x] 8.2 Add the default profile rules (one document, aliases expanded, no merge keys, no duplicate keys, string keys, empty document); verify the YAML format scenarios and "Default profile accepts an alias".
- [x] 8.3 Add the strict profile; verify "Strict profile rejects an alias", "Strict profile rejects null", and one test for each other strict rule.

## 9. JSON and JSON5 formats

Bead: lander-4us.2.9

- [x] 9.1 Add `moonbitlang/x` and the `config/formats/json5` package for `.json` and `.json5`, with the number rule and positioned errors; verify "JSON with comments", "JSON number types", and "JSON syntax error has a position".
- [x] 9.2 Document the JSON precision and duplicate-key limits in the package README; verify the README examples run as doc tests.

## 10. Ion format

Bead: lander-4us.2.10

- [x] 10.1 Add the `config/formats/ion` package for Ion text with one top-level struct and a repeated-field check; verify "Ion keeps exact values", "Ion repeated field", and "Ion with two top-level values".
- [x] 10.2 Add a cross-format test that parses one configuration in TOML, YAML, JSON, and Ion; verify the "All formats give the same tree" scenario.

## 11. Merge policies

Bead: lander-4us.2.11

- [x] 11.1 Add `MergePolicy` with `Append` and per-source and per-key-path scope; verify "Append lists" and "Key path policy beats source policy".
- [x] 11.2 Add `MergeByKey` and `ConfigError::MergeKey`; verify "Merge by key" and "Merge-by-key item without the key".
- [x] 11.3 Record all contributing origins for merged lists and keep every origin list non-empty; verify "Appended list has all contributors" and a property test that no provenance entry is empty.

## 12. Secret references and lazy resolution

Bead: lander-4us.2.12

- [x] 12.1 Add `SecretRef` recognition, `SecretSyntax`, the payload check, and leaf merge; verify "Two secret references do not merge" and "Invalid reference payload".
- [x] 12.2 Add `Secret`, `SecretResolver`, `SecretError` classes, `Config::secret`, and `env_resolver`; verify the lazy secret resolution scenarios, including a resolver spy for "Load does not resolve".
- [x] 12.3 Pass the leaf origin to the resolver; verify "Resolver gets the origin".

## 13. Redaction and command helpers

Bead: lander-4us.2.13

- [x] 13.1 Add `redact` with the Morphir fragment list; verify the four display redaction scenarios.
- [x] 13.2 Add `get_text` and `get_json` over redacted values with the key-not-found message; verify the four get helper scenarios.
- [x] 13.3 Add `show` for TOML, JSON, and Ion with the render mapping and `ConfigError::Render`; verify the three show helper scenarios.
- [x] 13.4 Add `path_text`, `path_json`, and `explain`; verify the path helper and explain helper scenarios.
- [x] 13.5 Add moonspec acceptance scenarios in `tests/` for get, show, and path, ported from Morphir `config.feature`; verify that they pass on all four targets.

## 14. Typed errors

Bead: lander-4us.2.14

- [x] 14.1 Declare all 20 `ConfigError` cases of design D12 with labelled fields, including the conventions and binding cases (`OutsideBoundary`, `InvalidEnvironmentName`, `UnknownProject`, `AmbiguousProject`, `Decode`, `Validation`) and `Ambiguous` (pulled forward from 5.6). Declare `Origin`, `SourceKind`, and `FileRole` as plain data (pulled forward from 4.3 and 5.1; groups 4 and 5 add the behavior), and the types `BindFailure`, `Located`, `Blame`, `DecodePath`, and `DecodeStep` with the shapes of the binding design, with the `DecodePath` text form (`targets[1].level`, quoted names, `(root)`); verify "Binding failure is a configuration error" and that `moon info` shows the types in `pkg.generated.mbti`.
- [x] 14.2 Review every `ConfigError` case for origin and position, and give `message()` text for each of the 20 cases. `Decode` and `Validation` use the binding D5 text: one line `<path>: <detail> (<blame text>)` for each located path, with the core origin text (file role name and path, `environment <VAR>`, else the kind name) and the blame text for `Set`, `Table` (an empty table gives `empty table, no source sets keys in it`), `Unset`, and `Default`. `message()` does not convert paths; the host adapter gives the `/` form (15.2). Verify "Parse error with origin" and "Match an error by case", plus one message test for each case.

## 15. Native host adapter

Bead: lander-4us.2.15

- [x] 15.1 Add the `config/host` package with the native `load(builder)` request loop over `moonbitlang/async` `fs`. It uses the variable set and the working directory of the builder, and reads a value from `moonbitlang/core/env` only when the builder holds none. Verify "Host adapter fills the inputs" and "Adapter uses the given values" with native tests over a temporary directory, with a provider that records the load context (6.3 verifies the environment-source part of both scenarios).
- [x] 15.2 Convert Windows paths to the `/` form at the adapter boundary and back for file-system calls; verify "Windows path in a report" in the windows-latest CI leg.
- [x] 15.3 Document the wasm and wasm-gc path (an injected `FileTree`, a variable set, and a working directory) in the `config` package guide `pkgs/lander/config/README.mbt.md`, with the native adapter in `config/host/README.mbt.md`; verify that the examples run as doc tests.

## 16. js host adapter in TypeScript

Bead: lander-4us.2.16

- [x] 16.1 Spike: bundle a small TypeScript module over `node:fs` with Bun through a moonx task script, call it from MoonBit `extern "js"` functions, and run it on Node and Bun on Linux, macOS, and Windows; verify that a js test reads one file. If the spike fails, stop and return to the owner.
- [x] 16.2 Add `scripts/build-node-adapter.mbtx` and a mise task that bundle `pkgs/lander/adapters/node/` with Bun into the checked-in generated js file of `config/host`, and add a check to `mise run check` that the generated file is current; verify that the check fails after an edit to the TypeScript source.
- [x] 16.3 Add the js request loop of `config/host` with synchronous `node:fs` reads and only `node:*` APIs that Node and Bun both support; verify "Host adapter fills the inputs" and "Adapter uses the given values" on the js target on Linux and Windows CI.
- [x] 16.4 Add a narrow AGENTS.md exception: js file access uses the TypeScript adapter over `node:fs`, built with Bun through a moonx task script; verify that `mise run check` passes.

## 17. Integration check

Bead: lander-4us.2.17

- [ ] 17.1 Run the full acceptance suite with the same inputs on wasm, wasm-gc, js, and native and compare values, provenance, and reports; verify the "Same result on all targets" scenario on Linux, macOS, and Windows CI and that `mise run check` passes.

## 18. Format trimming with a virtual package

Bead: lander-4us.2.18

- [x] 18.1 Create the virtual package `moonrockz/moon-lander/formats` with `options("virtual": { "has-default": true })`, the hand-written `pkg.mbti` of design D15 with `fn formats() -> Array[@config.Format]`, and a default implementation that gives the `toml`, `yaml`, `json5` and `ion` formats; verify the "Default linked formats" scenario on all four targets and that the hand-written interface with the `@config.Format` type builds
- [x] 18.2 Add the implementation package `moonrockz/moon-lander/formats/toml` with `options("implement": "moonrockz/moon-lander/formats")` and TOML only; verify the "Trim to TOML with one line" and "Own format mix" scenarios with test applications in `tests/` whose main `moon.pkg` has an `overrides` entry
- [x] 18.3 Add a moonx script in `scripts/*.mbtx` and a mise task in `mise run check` that builds a default application and a trimmed application on wasm, wasm-gc, js and native, and fails when a trimmed output is not smaller or holds a marker string of the YAML, JSON5 or Ion parser; verify the "Unused parsers are not linked" scenario in CI, and verify that the check fails when the trimmed application imports the YAML package
- [x] 18.4 Pre-publish check: before the first publish to mooncakes.io, build a consumer module that gets `moonrockz/moon-lander` from a registry and not from a `moon.work` workspace, override `formats` with `formats/toml`, and verify the trimmed result on all four targets. Ask the owner before any publish. If the override fails, record it in the bead and tell the owner

## Verification evidence

- `mise run check:config` runs the core and format tests and the acceptance
  suite on all four targets. It compares complete values, provenance and reports
  with `tests/config-fixture/expected.txt`, the same expected result on each OS.
- `mise run check:formats` runs the unchanged application with default, TOML-only
  and consumer-defined TOML/YAML implementations. It checks release sizes and
  real parser markers in UTF-8 and UTF-16LE, and rejects a reachable YAML import.
- `mise run check:formats-registry` packages the candidate and downloads it through
  a loopback registry into an isolated consumer outside `moon.work`. Registry
  checksum validation and all four target checks pass before public publication.
- Linux CI runs all three checks in the existing task-script job. The macOS job
  and the Windows native job run core observation and workspace trimming checks
  for all four targets. The existing aggregate requires these jobs to pass.

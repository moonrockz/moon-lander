# Tasks: add-configuration-core

Epic: lander-4us.2

Each group is one story. The design is in `design.md`. The requirements are in
`specs/configuration-core/spec.md`. Run `mise run check` at the end of each group.
Run `mise run format` before each commit.

## 1. Infrastructure: Windows CI leg and Bun pin

Bead: lander-4us.2.1

- [ ] 1.1 Add a windows-latest leg to `.github/workflows/ci.yml` that builds and tests the native and js targets, with the MoonBit core library installed by the Windows installer; verify that the leg passes on the current code.
- [ ] 1.2 Pin Bun in `.config/mise/config.toml` with a comment that says the js host adapter build uses it; verify that `mise install` installs it on Linux, macOS, and Windows CI.

## 2. Tracer bullet: in-memory and TOML sources, merge, get

Bead: lander-4us.2.2

- [ ] 2.1 Add `moonrockz/ion@0.6.0` and `moonbit-community/toml@0.5.0` to `pkgs/lander/moon.mod`, create the packages `config` and `config/formats/toml`, and verify that `mise run validate` and `mise run build` pass.
- [ ] 2.2 Add a minimal `ConfigValue` over `@ion.Ion` with a struct-root check, a dotted `KeyPath::parse` without quoting, and `Config::get`; verify with unit tests for a hit and a miss.
- [ ] 2.3 Add an in-memory source from a value tree and from flat key-path pairs; verify the "Flat key-path pairs" and "Later pair wins" scenarios with unit tests.
- [ ] 2.4 Add the TOML format for strings, integers, floats, Booleans, arrays, and tables, with `ConfigError::Parse`; verify with unit tests.
- [ ] 2.5 Add the default merge (overlay wins, structs merge, lists replace) and `build` over an ordered list of sources; verify the "Later source wins" and "Structs merge and arrays replace" scenarios.
- [ ] 2.6 Add a `get_text` helper and one moonspec acceptance scenario in `tests/` that merges an in-memory source over a TOML snapshot and gets `project.name`; verify that the scenario passes on all four targets.

## 3. Value tree and key path rules

Bead: lander-4us.2.3

- [ ] 3.1 Enforce the `ConfigValue` invariants (text field names, unique fields, struct root), keep field order, and add `from_json` and `to_ion`; verify the "Root is not a struct" and "Field order stays" scenarios.
- [ ] 3.2 Complete `KeyPath`: quoted names, escapes, `to_string` round trip, and `ConfigError::InvalidKeyPath`; verify the key path scenarios and a parse/print round-trip property test.
- [ ] 3.3 Treat `sexp` as a list and apply the struct annotation rule (design D2); verify with unit tests.

## 4. Complete merge rules and provenance

Bead: lander-4us.2.4

- [ ] 4.1 Add null-overlay handling and null-field removal from the result; verify the "Null does not unset" and "Null with no base value" scenarios.
- [ ] 4.2 Make merge copy only changed paths and keep inputs unchanged; verify "Inputs do not change" and "New keys follow base keys", plus an associativity property test over generated trees.
- [ ] 4.3 Add `Origin`, the provenance map, and stale-record removal ported from morphir-moonbit `merge`; verify the "Winning origins" and "Stale records go" scenarios.
- [ ] 4.4 Add `SourceReport` with kind, name, priority, path, candidates, status, and warnings, the Morphir kind names, and `local-override`; verify the "Report order and status" and "File role names" scenarios.

## 5. Source model: selection, file source, ambiguity, exclusion

Bead: lander-4us.2.5

- [ ] 5.1 Add `SourceSelection[T]`, `SourceKind`, `FileRole` (with `LocalOverride`), `ConfigBuilder`, `add`, and the defaults source; verify the "Skip a source", "Same kind at two positions", and "Defaults from JSON" scenarios.
- [ ] 5.2 Add display priorities with the defaults by kind and role (local override 390), the in-memory rule, and `ConfigError::SourceOrder`; verify the "Default priorities", "Override file priorities", and "Decreasing priority" scenarios.
- [ ] 5.3 Add `FileTree` (with `with_listing`, `with_file`, and `with_missing`), `FileRequest`, `LoadStep[T]`, and the pure `@config.load(builder, tree)`; verify the "Incomplete tree asks for files", "Complete tree never asks", "Absence record answers a request", and "Missing directory answers its children" scenarios.
- [ ] 5.4 Add `Platform`, `LoadContext` (with `env_vars` and `working_dir`), `@config.env_vars`, `@config.working_dir`, `Expansion`, `SourceProvider`, `@config.provider`, `@config.platform`, and `ConfigWarning::Note`, and expand providers in place during `@config.load`; verify the three source provider scenarios.
- [ ] 5.5 Add `Format`, the builder format registry (`format`, `formats`, `parse_file`), and the explicit file source over a `FileTree` that joins a relative path to the working directory; verify the format registry scenarios, "Extension selects the format", "Missing explicit file", "Unregistered extension", and "Relative path joins the working directory".
- [ ] 5.6 Add the candidate-list file source, the exact-name existence check over listings, and `ConfigError::Ambiguous(display~, location~, candidates~)` with its message; verify the candidate ambiguity scenarios and "Name match is exact".
- [ ] 5.7 Add `ConfigSource::exclude(paths, warn~)`, `ConfigWarning::KeyRemoved`, and `SourceReport.warnings`; verify the three source subtree exclusion scenarios.
- [ ] 5.8 Document the source model in `pkgs/lander/README.md` with an example that runs as a doc test; verify with `mise run test`.

## 6. Environment and overrides sources

Bead: lander-4us.2.6

- [ ] 6.1 Port the environment key mapping (prefix in any case, leading `_`, `__`, lowercase, empty segment error) and reserved names; verify all environment name and reserved name scenarios.
- [ ] 6.2 Port value typing and the shorter-path-wins order from morphir-moonbit; verify the "Typed values", "JSON list value", "Invalid JSON stays text", "Integer out of range", and both shorter-path scenarios, the last with two input orders.
- [ ] 6.3 Record the variable name in each environment origin, support `Explicit` variables, and read `Discover` variables from the builder variable set (`@config.env_vars`); verify "Environment origin names the variable", "Explicit environment variables", and "Discover environment with no host".
- [ ] 6.4 Add the overrides source; verify the "Overrides beat the environment" scenario.

## 7. TOML date and time mapping

Bead: lander-4us.2.7

- [ ] 7.1 Map TOML date-time values as `pkgs/notebooks` does and keep `Int64` exact; verify the "TOML date and time values" and "Large TOML integer" scenarios.

## 8. YAML format with default and strict profiles

Bead: lander-4us.2.8

- [ ] 8.1 Add `moonbit-community/yaml@0.0.8` and the `config/formats/yaml` package with an event-based builder that keeps line and column; verify "Core schema scalars" and that the builder matches `Yaml::load_from_string` on the library examples.
- [ ] 8.2 Add the default profile rules (one document, aliases expanded, no merge keys, no duplicate keys, string keys, empty document); verify the YAML format scenarios and "Default profile accepts an alias".
- [ ] 8.3 Add the strict profile; verify "Strict profile rejects an alias", "Strict profile rejects null", and one test for each other strict rule.

## 9. JSON and JSON5 formats

Bead: lander-4us.2.9

- [ ] 9.1 Add `moonbitlang/x` and the `config/formats/json5` package for `.json` and `.json5`, with the number rule and positioned errors; verify "JSON with comments", "JSON number types", and "JSON syntax error has a position".
- [ ] 9.2 Document the JSON precision and duplicate-key limits in the package README; verify the README examples run as doc tests.

## 10. Ion format

Bead: lander-4us.2.10

- [ ] 10.1 Add the `config/formats/ion` package for Ion text with one top-level struct and a repeated-field check; verify "Ion keeps exact values", "Ion repeated field", and "Ion with two top-level values".
- [ ] 10.2 Add a cross-format test that parses one configuration in TOML, YAML, JSON, and Ion; verify the "All formats give the same tree" scenario.

## 11. Merge policies

Bead: lander-4us.2.11

- [ ] 11.1 Add `MergePolicy` with `Append` and per-source and per-key-path scope; verify "Append lists" and "Key path policy beats source policy".
- [ ] 11.2 Add `MergeByKey` and `ConfigError::MergeKey`; verify "Merge by key" and "Merge-by-key item without the key".
- [ ] 11.3 Record all contributing origins for merged lists and keep every origin list non-empty; verify "Appended list has all contributors" and a property test that no provenance entry is empty.

## 12. Secret references and lazy resolution

Bead: lander-4us.2.12

- [ ] 12.1 Add `SecretRef` recognition, `SecretSyntax`, the payload check, and leaf merge; verify "Two secret references do not merge" and "Invalid reference payload".
- [ ] 12.2 Add `Secret`, `SecretResolver`, `SecretError` classes, `Config::secret`, and `env_resolver`; verify the lazy secret resolution scenarios, including a resolver spy for "Load does not resolve".
- [ ] 12.3 Pass the leaf origin to the resolver; verify "Resolver gets the origin".

## 13. Redaction and command helpers

Bead: lander-4us.2.13

- [ ] 13.1 Add `redact` with the Morphir fragment list; verify the four display redaction scenarios.
- [ ] 13.2 Add `get_text` and `get_json` over redacted values with the key-not-found message; verify the four get helper scenarios.
- [ ] 13.3 Add `show` for TOML, JSON, and Ion with the render mapping and `ConfigError::Render`; verify the three show helper scenarios.
- [ ] 13.4 Add `path_text`, `path_json`, and `explain`; verify the path helper and explain helper scenarios.
- [ ] 13.5 Add moonspec acceptance scenarios in `tests/` for get, show, and path, ported from Morphir `config.feature`; verify that they pass on all four targets.

## 14. Typed errors

Bead: lander-4us.2.14

- [ ] 14.1 Declare the conventions and binding cases of `ConfigError` (`OutsideBoundary`, `InvalidEnvironmentName`, `UnknownProject`, `AmbiguousProject`, `Decode`, `Validation`) and the types `BindFailure`, `Located`, `Blame`, `DecodePath`, and `DecodeStep` with the shapes of the binding design; verify "Binding failure is a configuration error" and that `moon info` shows the types in `pkg.generated.mbti`.
- [ ] 14.2 Review every `ConfigError` case for origin, position, `/` paths, and `message()` text; verify "Parse error with origin" and "Match an error by case", plus one message test for each case.

## 15. Native host adapter

Bead: lander-4us.2.15

- [ ] 15.1 Add the `config/host` package with the native `load(builder)` request loop over `moonbitlang/async` `fs`. It uses the variable set and the working directory of the builder, and reads a value from `moonbitlang/core/env` only when the builder holds none. Verify "Host adapter fills the inputs" and "Adapter uses the given values" with native tests over a temporary directory.
- [ ] 15.2 Convert Windows paths to the `/` form at the adapter boundary and back for file-system calls; verify "Windows path in a report" in the windows-latest CI leg.
- [ ] 15.3 Document the wasm and wasm-gc path (an injected `FileTree`, a variable set, and a working directory) in `pkgs/lander/README.md`; verify that the README example runs as a doc test.

## 16. js host adapter in TypeScript

Bead: lander-4us.2.16

- [ ] 16.1 Spike: bundle a small TypeScript module over `node:fs` with Bun through a moonx task script, call it from MoonBit `extern "js"` functions, and run it on Node and Bun on Linux, macOS, and Windows; verify that a js test reads one file. If the spike fails, stop and return to the owner.
- [ ] 16.2 Add `scripts/build-node-adapter.mbtx` and a mise task that bundle `pkgs/lander/adapters/node/` with Bun into the checked-in generated js file of `config/host`, and add a check to `mise run check` that the generated file is current; verify that the check fails after an edit to the TypeScript source.
- [ ] 16.3 Add the js request loop of `config/host` with synchronous `node:fs` reads and only `node:*` APIs that Node and Bun both support; verify "Host adapter fills the inputs" and "Adapter uses the given values" on the js target on Linux and Windows CI.
- [ ] 16.4 Add a narrow AGENTS.md exception: js file access uses the TypeScript adapter over `node:fs`, built with Bun through a moonx task script; verify that `mise run check` passes.

## 17. Integration check

Bead: lander-4us.2.17

- [ ] 17.1 Run the full acceptance suite with the same inputs on wasm, wasm-gc, js, and native and compare values, provenance, and reports; verify the "Same result on all targets" scenario on Linux, macOS, and Windows CI and that `mise run check` passes.

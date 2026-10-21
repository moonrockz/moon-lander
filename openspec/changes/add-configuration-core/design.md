# Design: add-configuration-core

## Context

See `proposal.md` for the motivation. The requirements are in
`specs/configuration-core/spec.md`.

Current state:

- `pkgs/lander` (`moonrockz/moon-lander`, imported as `@lander`) holds only a
  `version()` smoke export.
- `pkgs/notebooks` already depends on `moonrockz/ion@0.6.0`,
  `moonbit-community/toml@0.5.0`, and `moonbit-community/yaml@0.0.8`. Its
  `dib/metadata_codec.mbt` maps TOML and YAML values to `@ion.Ion`. This design
  reuses that TOML date-time mapping so that the repository has one rule.
- `tests/` is an unpublished module. It already uses `moonrockz/moonspec` for
  acceptance suites and `moonbitlang/async@0.22.5`.
- morphir-moonbit `pkgs/morphir-engine/config/config.mbt` holds the merge,
  provenance, and environment code that this design ports. Its tests
  (`config_test.mbt`) and the Morphir `config.feature` cases are the source of
  most spec scenarios.

Constraints: all code builds and tests on wasm, wasm-gc, js, and native, on Linux,
macOS, and Windows. Domain code is pure over explicit inputs and immutable public
values. Only host adapters do I/O: `moonbitlang/async` on native, a TypeScript
adapter over `node:fs` on js, and `moonbitlang/core/env` for environment variables
and the working directory.

Labels in this document:

- **Owner**: the project owner made the decision.
- **Call**: the designer made the decision in the design conversation. The owner
  did not reject it.
- **Call (this change)**: the author of this change made the decision. The owner
  did not review it yet. Each one is in the list at the end of "Decisions".

Decisions from the reconciliation addendum of 2026-10-20 show their item number:
**Owner (O2)** for an owner answer, **Call (R1)** for a reconciliation call. The
addendum replaces earlier text where they disagree.

**Owner (2026-10-20)** marks later owner decisions: the local override layer (D4),
one variable set and one working directory for each run (D4a, D13), and format
trimming with a virtual package (D15).

## Goals / Non-Goals

**Goals:**

- One value model and one merge engine for all formats and sources.
- A pure build: the same inputs give the same `Config` on all four targets.
- Morphir behaviour as the default, so the Morphir preset in
  `add-configuration-conventions` can reproduce Morphir without special code in
  the core.
- Typed errors that a host can map to exit codes without string compares.

**Non-Goals:**

- File discovery, layouts, and environment names (`add-configuration-conventions`).
- Binding to typed values (`add-configuration-binding`).
- The host, commands, and exit codes (`add-host-lifecycle`).
- Exact preservation of source text (comments, whitespace) for round trips.

## Decisions

### D1. Package layout

**Call** (shared names). All packages are in module `moonrockz/moon-lander`:

| Package | Contents | Targets |
| --- | --- | --- |
| `config` (`@config`) | `ConfigValue`, `KeyPath`, sources, merge, provenance, secrets, errors, render helpers | all |
| `config/formats/toml` | TOML format | all |
| `config/formats/yaml` | YAML format, default and strict profiles | all |
| `config/formats/json5` | `.json` and `.json5` format | all |
| `config/formats/ion` | Ion text format | all |
| `config/host` | the request loop: read files; fill a missing variable set or working directory from the process | native, js |
| `formats` (virtual) | `formats()`: the linked format set; the default implementation links the four format packages (D15) | all |
| `formats/toml` | an implementation of `formats` with TOML only (D15) | all |

**Call (R1)**: `config/host` is the one configuration adapter package, with one
file for each target. Conventions has no host package of its own. The adapter
answers every `FileRequest` that `@config.load` returns, both for explicit files
and for conventions discovery. wasm and wasm-gc have no adapter. They take an
injected `FileTree` (D13).

Each format package depends on `@config`. `@config` depends on no format package.
On the bare path, an application imports and registers only the formats it uses
(Call). Under the `@lander` entry of `add-host-lifecycle`, the `formats` virtual
package gives the linked set, and the application trims it with one override (D15).

### D2. Value tree: `ConfigValue` over `@ion.Ion`

**Call**: one shared Ion-based value tree. Every format parses into it before the
merge.

`ConfigValue` is an opaque struct that wraps `@ion.Ion`. The constructors check
the invariants once, so the merge does not check them again:

- every struct field name has text (no unresolved symbol IDs);
- field names are unique in each struct;
- the root of a source tree is a struct.

`ConfigValue::from_ion` checks the invariants. `ConfigValue::to_ion` gives the
Ion value. `ConfigValue::from_json` converts `Json` through `@ion.ToIon`.

**Call (this change)**: `from_ion` raises `DuplicateKey` for a repeated field name
and `Parse` with the format `Ion` for a field name with no text. The key path of a
field in a list item holds only the struct field names. The `fields` constructor
does not raise: when a name occurs more than once, the last value wins at the
position of the first.

Why Ion and not `Json` or `TomlValue`: Ion holds every type of the five formats
without loss (decimals, timestamps, big integers, symbols, annotations). JSON
loses big integers and timestamps. `TomlValue` has no null and no decimal.
morphir-moonbit used `TomlValue` and had to reject JSON nulls and dates.

**Call (this change)**: an Ion `sexp` behaves as a list in merge and render.
Annotations stay on scalars and lists. When two structs merge, the result keeps the
overlay annotations if the overlay has any, else the base annotations.

### D3. `KeyPath`

`KeyPath` holds a non-empty `Array[String]` of non-empty names. `KeyPath::parse`
reads the dotted text form. `KeyPath::to_string` writes it.

**Call (this change)**:

- A name with `.` or `"` uses TOML-style double quotes: `servers."eu.west".port`.
- In a quoted name, `\"` gives `"` and `\\` gives `\`. Other escapes, a missing
  closing quote, text after a closing quote, and a `"` inside a bare name raise
  `InvalidKeyPath`. `KeyPath::from_names` builds a key path from names and checks
  the same rules.
- Name compare is exact and case-sensitive. The environment source writes
  lowercase names, so environment keys still match lowercase file keys.
- A key path does not index into lists. Morphir `config get` does not index lists,
  and provenance treats a list as one leaf.

**Call (R5)**: these rules are the one `KeyPath` for all four changes. A key path
is never empty and never indexes a list. Binding uses `bind_root(config)` for the
root. A decode error inside a value uses `DecodePath` (D12): a `KeyPath` plus a
suffix of field names and list indexes.

### D4. Sources, kinds, order, and selection

**Call**: sources are ordered typed values. **Call (R6)**: list order is merge
order: low first, high last, as in .NET `ConfigurationBuilder`.

```moonbit
pub(all) enum SourceSelection[T] {
  Discover
  Explicit(T)
  Skip
} derive(Eq, Debug)

pub(all) enum FileRole {
  Explicit
  System
  Global
  Workspace
  Member
  EnvironmentFile
  LocalOverride
  UserOverride
  Legacy
} derive(Eq, Debug)

pub(all) enum SourceKind {
  Defaults
  InMemory
  File(FileRole)
  Environment
  Overrides
} derive(Eq, Debug)
```

**Call (R4)**: `SourceKind` and `FileRole` are the shared kinds of all four
changes. Reports and `path_json` show Morphir's kind names through the role:

| Kind | Report name |
| --- | --- |
| `Defaults` | `defaults` |
| `InMemory` | `in-memory` |
| `File(System)` | `system` |
| `File(Global)` | `global` |
| `File(Workspace)`, `File(Explicit)`, `File(Legacy)` | `project` |
| `File(Member)` | `workspace-member` |
| `File(EnvironmentFile)` | `environment-file` |
| `File(LocalOverride)` | `local-override` |
| `File(UserOverride)` | `user-override` |
| `Environment` | `environment` |
| `Overrides` | `overrides` |

**Call (this change)**: `File(Explicit)` and `File(Legacy)` show `project`, because
Morphir loads `--config` and its legacy file as the project layer. `in-memory` and
`overrides` have no Morphir name. These report names are final for all four
changes. They match the serialized names of the Morphir Rust loader.

**Owner (2026-10-20)**: `File(LocalOverride)` is the local override layer. A local
file is for one checkout and git ignores it. A user override is the preference of
one person. The report name is `local-override`. Morphir has no local layer, so
this name has no Morphir equivalent, and the Morphir preset does not use the role.

**Call (R2)**: `SourceSelection[T]` stays in core. It keeps one name for the Morphir
`Discover | Explicit(path) | Skip` and `Process | Explicit(vars) | Skip` choices.

- A file location uses `SourceSelection[String]`. The conventions change resolves
  `Discover` into file sources (R2). Core gives the file sources that it resolves
  to: `file(path)` for one explicit file and `candidates(paths, display~)` for an
  explicit candidate list at one location. `Skip` gives a source with no input
  and the status `skipped`.
- An environment source uses `SourceSelection[Map[String, String]]`. `Discover`
  means the variable set of the builder, which the host supplies (D13).
  `Explicit(vars)` uses only `vars`.

`ConfigSource` is an immutable struct: kind, display name, priority, an optional
list `MergePolicy`, key filters (R9, below), and the input. Constructors use
labelled and optional arguments:

```moonbit
let builder = @config.builder()
  |> @config.format(@toml.format())
  |> @config.defaults(Defaults::default().to_json())
  |> @config.file("conf/app.toml", name="project")
  |> @config.env(prefix="MORPHIR", reserved=["MORPHIR_HOME", "MORPHIR_LOG_DIR"])
  |> @config.overrides([("ir.layout", @config.string("single-file"))])
let step = builder |> @config.load(tree)  // LoadStep[Config], raise ConfigError
```

`ConfigBuilder` is an immutable list of sources and a list of registered formats
(D7). Each function returns a new builder. `@config.add(builder, source)` adds a
source that another package built, for example a conventions file source. The
hosting change can wrap these functions for `HostBuilder[S]`.

**Call (R6)**: each source has an `Int` priority for display. The merge never reads
it. The builder raises `ConfigError::SourceOrder` when a priority is lower than the
priority of the source before it. Equal priorities are allowed. The shared values
are:

| Source | Priority |
| --- | --- |
| Defaults | 0 |
| System file | 100 |
| Global user file | 200 |
| Workspace primary, explicit file, legacy file | 300 |
| Member primary | 350 |
| Environment file | 375 |
| Local override (Owner (2026-10-20)) | 390 |
| User override | 400 |
| Environment variables | 600 |
| Overrides (argparse) | 700 |

**Call (this change)**: each constructor takes `priority?`. When it is absent, the
value comes from the kind and role in the table. An in-memory source has no row: it
takes the priority of the source before it, or 0 when it is first, so it can be at
any position. The conventions parts set the same values for generic apps (R6).

**Call (R2)**: the ambiguity rule over an explicit candidate list is in core.
Zero existing candidates gives `not-found`, one gives `loaded`, more gives
`ConfigError::Ambiguous(display~, location~, candidates~)`. A candidate exists when
the listing of its directory in the `FileTree` holds its exact name as a file
(D13). The conventions change applies the same rule during discovery, with its own
skip rules for ancestors.

**Call (this change)**, from the source model task group (5):

- Source values come from constructors on `ConfigSource`: `defaults(json)`,
  `defaults_value(value)`, `file(path, role~)`, `candidates(paths, display~)`,
  and `skipped(kind)`, plus the existing `in_memory` and `in_memory_pairs`. Each
  takes `name?` and `priority?`. A provider returns these values. The builder
  pipes `@config.defaults(builder, json)` and `@config.file(builder, path)` add
  one source each; `@config.add` adds any other source.
- `@config.load` checks the priorities, not `add`, because a provider expands only
  during the load. The check runs over the expanded list before any file request,
  so the builder functions do not raise for the order.
- `build(sources)` loads value sources over a complete empty `FileTree`.
  `Config::reports()` gives the reports in merge order, and `Config::warnings()`
  gives the provider warnings, then the report warnings in merge order.
- The location of `Ambiguous` is the longest directory that holds every
  candidate. The load raises `Ambiguous` as soon as two candidates exist, also
  when the tree does not yet know the other candidates.
- The source model types derive `Debug`, not `Show`, because `derive(Show)` is
  deprecated.

**Call (R9)**: key filters. `ConfigSource::exclude(self, paths, warn~ : Bool)`
gives a source a list of key paths to remove. Core applies the filters after the
parse and before the merge, inside the build. When `warn` is true, each removed key
that existed adds `ConfigWarning::KeyRemoved(path, origin)` to
`SourceReport.warnings`. When `warn` is false, the removal is silent. Removed values
have no provenance. The conventions change declares the filters: member-layer
removal with a warning (the Rust loader drops `workspace.out_dir`) and
inherited-layer removal without a warning (morphir-moonbit `Document::shared()`).

```moonbit
pub(all) enum ConfigWarning {
  KeyRemoved(KeyPath, Origin)
  Note(source~ : String, message~ : String)   // provider warnings (D4a)
} derive(Eq, Debug)
```

### D4a. Source providers and the load context

**Call (R1, R2)**: conventions discovery plugs into the core builder as a source
provider. The pure `@config.load` runs each provider at its position in the list.
The provider gives the file sources that it resolved from `Discover`, or the file
requests that it still needs.

```moonbit
pub(all) enum Platform {
  Linux
  MacOs
  Windows
} derive(Eq, Debug)

pub(all) struct LoadContext {
  tree : FileTree
  platform : Platform?               // None when no host gave it
  env_vars : Map[String, String]     // the variable set of the run, else empty
  working_dir : String?              // the working directory of the run
  formats : Array[Format]            // the registry (R11)
}

pub(all) struct Expansion {
  sources : Array[ConfigSource]      // in merge order
  warnings : Array[ConfigWarning]
}

pub(all) struct SourceProvider {
  name : String
  expand : (LoadContext) -> LoadStep[Expansion] raise ConfigError
}

pub fn provider(builder : ConfigBuilder, p : SourceProvider) -> ConfigBuilder
```

- `@conventions.add(...)` calls `@config.provider` with a provider that runs pure
  discovery. The core does not know conventions rules.
- `@config.load` collects the `Need` requests of all providers and file sources in
  one pass and gives them in one `Need`. With a complete tree, a provider must give
  `Done`.
- The sources of an `Expansion` take the place of the provider in merge order. The
  core then checks priorities (`SourceOrder`) over the expanded list. A provider can
  give `skipped` and `not-found` sources (`@config.skipped`, candidate lists with no
  existing file), so every location has a report.
- Expansion warnings go to `Config::warnings()`. **Call (this change)**:
  `ConfigWarning` has a second case, `Note(source~ : String, message~ : String)`,
  for provider warnings such as a skipped workspace member glob.
- **Call (this change)**: `Platform` is in core, so that the load context can carry
  it as an explicit input for pure discovery. `@config.platform(builder, p)` sets
  it. `config/host` detects it (native: the target operating system; js:
  `process.platform` in the TypeScript adapter). A wasm or wasm-gc host gives it.
  With no value, a provider decides its own fallback.
- Other discovery results (the environment name, the workspace root, the member
  root) belong to the conventions change. The core does not model them.
- **Owner (2026-10-20)**: each run has one variable set and one working directory.
  `@config.env_vars(builder, vars)` and `@config.working_dir(builder, dir)` set them.
  The load context gives the same values to every provider. A provider reads
  variables only from `env_vars` and starts its search at `working_dir`. It never
  reads the process.

### D5. In-memory, defaults, and overrides sources

**Owner**: an in-memory source like .NET `AddInMemoryCollection`. **Call**: it
takes a value tree or flat key-path pairs and can be at any position.

**Call (this change)**: pairs apply in list order with the merge rules, so a later
pair wins. Pair values keep their type. There is no string type inference, because
the caller already has typed values. Only the environment source infers types.

**Call (this change)**: the overrides source has the same input forms as the
in-memory source. It has its own kind so that `config path` and provenance show
`overrides` (for example, CLI flags). The argparse adapter in `add-host-lifecycle`
gives typed values. Its default priority is 700 (R6).

### D6. Environment source

**Call**: prefix, `__` nesting, Morphir typing rules, and a reserved-name list.

Ported from morphir-moonbit `environment` and the Morphir merge-rules spec:

1. Keep a variable when its name, in uppercase, starts with `PREFIX_` and the name
   is not reserved. Reserved names compare in uppercase (**Call (this change)**,
   because Windows variable names ignore case).
2. Skip all `_` after the prefix. Split the rest at `__`. Write each segment in
   lowercase. An empty segment raises `ConfigError::InvalidEnvKey`.
3. Type the value: `true`/`false` in any case to Bool; `[+-]?[0-9]+` that fits
   `Int64` to Int (leading zeros allowed: `+003` is 3); text that starts with `[`
   or `{` and parses as JSON to a list or a struct; else String. `1.5` stays a
   string, as in Morphir.
4. Sort the keys by depth, deepest first, then by name. Merge each one-key tree in
   that order. This makes "shorter path wins" independent of iteration order.
5. Each leaf origin holds the variable name.

The JSON value in step 3 uses `@json.parse` from `moonbitlang/core`. Its numbers
keep their source text (`repr`), so the conversion to Ion keeps integers exact.

**Call (this change)**, from task group 6: `ConfigSource::env(prefix~, reserved?,
selection?)` and the pipe `@config.env(builder, prefix~, ...)` give the source;
`selection` defaults to `Discover`. The load keeps one tree for each variable, so
each leaf origin holds its variable name, and an exclusion warning names the
variable that held the key. Keys with equal depth sort by key text, then by
variable name, so two variables that differ only in case give the same result on
every run. `ConfigSource::overrides(pairs)`, `overrides_value(value)`, and the pipe
`@config.overrides(builder, pairs)` give the overrides source.

**Call (this change)**: a variable named only `PREFIX_` (empty key) is an error, as
in morphir-moonbit. An environment source with no matching variables reports
`loaded`, because the source was read.

**Call (this change)**: a `Discover` environment source reads the variable set of
the builder (`@config.env_vars(builder, vars)`, D4a). When the builder holds no
variable set (for example on wasm with no hosting), the source adds no key and
reports `not-found`.

**Call (R8)**: the core takes the reserved-name list as an input. Hosting composes
the environment source by default, with the uppercase application name as the
prefix, and adds `<PREFIX>_ENVIRONMENT` and `<PREFIX>_HOME` to the list.

### D7. Formats and type mapping

**Owner**: formats JSON, TOML, YAML, JSON5, and Ion. `.json` files use
`moonbitlang/x/json5` so that JSON files can hold comments.

Each format package exports one `Format` value:

```moonbit
pub(all) struct Format {
  name : String
  extensions : Array[String]
  parse : (String, origin~ : String) -> ConfigValue raise ConfigError
}
```

The application registers the formats it uses on the builder with
`|> @config.format(...)`, or the `@lander` entry registers the linked set of the
`formats` virtual package (D15). The file extension selects the format, compared in
lowercase.

**Call (R11)**: the builder is the format registry for all changes.
`ConfigBuilder::formats()` gives the registered formats in registration order.
`@config.parse_file(formats, path, text)` selects the format by extension and
parses. The conventions change reads `formats()` to derive its candidate extension
lists, and parses ancestor candidates with `parse_file` and `merge` to find
`[workspace]` tables. So conventions depends on core only, and format packages
come in through the registry. A preset chooses its formats when it registers them.

**Call (this change)**: the YAML format registers `.yaml` and `.yml`. The JSON5
package exports one format for `.json` and `.json5`. The Ion format reads `.ion`
text only.

Type mapping and precision issues:

| Format | Input | Tree value | Notes |
| --- | --- | --- | --- |
| TOML | integer (`Int64`) | Int | exact |
| TOML | float | Float | `inf` and `nan` stay floats |
| TOML | offset date-time | Timestamp with offset | fraction kept as Ion decimal |
| TOML | local date-time | Timestamp, offset unknown (`-00:00`) | Ion has no "local" timestamp; unknown offset is the closest |
| TOML | local date | Timestamp, day precision | |
| TOML | local time | String with annotation `toml_local_time` | Ion has no time-only type; same rule as `pkgs/notebooks` |
| YAML | plain integer | Int | **Call (this change)**: integers above `Int64` become exact Int; the library gives a lossy Double |
| YAML | plain float | Float | text such as `1.10` loses its trailing zero |
| YAML | `yes`, `no`, `on`, `off` | String | YAML 1.2 core schema, as the library does |
| YAML | date-like plain text | String | no implicit timestamps |
| YAML | `~`, `null`, empty | Null | strict profile rejects it |
| YAML | quoted scalar | String | |
| JSON/JSON5 | number | Int when integral and `abs <= 2^53`, else Float | `json5` gives `Double` only, with no source text. Integers above 2^53 lose precision. `Infinity` and `NaN` become floats |
| JSON/JSON5 | duplicate key | last value wins | `json5` keeps no duplicate information; the core cannot detect it |
| Ion | decimal | Decimal | exact |
| Ion | timestamp | Timestamp | precision and offset kept |
| Ion | symbol | Symbol | renders as a string in JSON and TOML; binding decides decode |
| Ion | annotations | kept | dropped in JSON and TOML render |
| Ion | blob, clob | Blob, Clob | render: base64 text in JSON and TOML |
| Ion | repeated field | error | Ion allows it; configuration does not |
| Ion | more than one top-level value | error | |

Parse errors and positions:

- TOML 0.5.0 `parse` raises an untyped error. Its message holds the token
  location as text. `ConfigError::Parse` keeps the message. Line and column are
  `None`.
- YAML 0.0.8 raises `YamlError` with a `Marker` (line, column). The format keeps
  them.
- `json5` raises `ParseError` with `Position` (line, column) for most cases.
  `InvalidEof` has no position.
- Ion text raises `IonError::Syntax(String)` with no structured position.

YAML implementation: the format reads events with `Parser::load` and a
`MarkedEventReceiver`, and builds the tree from the events. Reasons: the strict
profile needs anchors, aliases, tags, and document events, which the
`Yaml` tree hides (the library expands aliases silently); each error needs a
line and a column; and integers above `Int64` stay exact. Scalar resolution
copies the library rules for plain scalars.

**Call (this change)**: the default YAML profile also accepts only one document,
because more than one document has no defined merge. It rejects merge keys (`<<`)
because the library does not apply them. Without this, `<<` becomes a literal key
with no warning.

**Reference** (Morphir spec): the strict profile: one document, no
anchors/aliases/merge keys/custom tags/duplicate keys, no null, mapping root. The
YAML format takes `profile=Strict` as an option. The default is `Default`.

### D8. Merge

**Owner**: the Morphir merge rules are the default. The owner believes they are
HOCON-like. The one HOCON difference: in HOCON a null replaces the value and
Typesafe Config treats the key as missing. Morphir ignores a null overlay. This
design follows Morphir.

`merge(base, overlay, policy)` is a pure function over `ConfigValue`:

1. Overlay field is null: keep the base value and its provenance.
2. Base or overlay is a secret reference: overlay replaces.
3. Both are structs: merge field by field. Base field order first, new overlay
   fields after.
4. Both are lists and a policy applies: use the policy.
5. Else the overlay replaces.

The merge copies only the changed path. It shares unchanged subtrees. Inputs do not
change.

**Call (this change)**: the merge is associative only when no path is a struct in
one tree and a leaf in another. With `{x = {y}}`, `{x = 2}` and `{x = {z}}`, the
left grouping gives `{x = {z}}` and the right grouping gives `{x = {y, z}}`,
because a struct replaces a scalar. Load order is fixed, so this does not change a
result; the property test generates trees whose names keep one shape.

**Call**: `MergePolicy` selects list behaviour per source or per key path:

```moonbit
pub(all) enum MergePolicy {
  Replace         // default
  Append          // like HOCON +=
  MergeByKey(String)
} derive(Eq, Show)
```

A key-path policy beats a source policy. `MergeByKey(name)`: each item must be a
struct with a scalar field `name`. Items with equal key values deep-merge in base
position. Other overlay items append. A missing key field or a repeated key value
in one list raises `ConfigError::MergeKey`. **Call**: no .NET index-based list
merge and no explicit unset.

**Call (this change)**: the build removes null struct fields from the result, also
in structs inside lists. So `Config` never holds a null field, and a single source
with `a = null` gives no `a`. A null list item stays.

### D9. Provenance

**Call**: per-leaf provenance and a per-source report.

```moonbit
pub(all) struct Origin {
  kind : SourceKind
  source : String        // display name
  priority : Int
  location : String?     // file path or variable name
} derive(Eq, Debug)
```

`Config` holds `Map[KeyPath, Array[Origin]]`. The map uses the same update rules as
morphir-moonbit `merge`: a new leaf removes records at, below, and above its path,
then adds its own. After the merge, records for paths that are not in the tree go.

**Call (R10)**: the value is an array of origins and is never empty. It has one
origin for a replaced leaf or a replaced list. An `Append` or `MergeByKey` list has
every contributing origin in merge order. Binding shows this array as its blame for
a list (`Set(Array[Origin])`). A struct has no record of its own, as in the Morphir
spec. An empty struct therefore has no origin.

**Call (this change)**: `Config::origins(key)` gives the origins of the leaf at
`key`, and an empty array for a struct or a missing key. `Config::provenance()`
gives every leaf with its origins, in tree order. Both return copies.
`SourceKind::report_name()` gives the report names of D4.

`SourceReport` holds `kind`, `name`, `priority`, `path : String?`,
`candidates : Array[String]`, `status : SourceStatus` (`Loaded`, `NotFound`,
`Skipped`), and `warnings : Array[ConfigWarning]` (R9). The build gives the reports
in merge order (R6).

### D10. Secrets

**Call**: secret references are leaves. A host-supplied resolver resolves them
lazily. Morphir shapes: `{ env = "NAME" }`, `{ file = "path" }`,
`{ command = ["argv", ...] }`, `{ keyring = { service = "...", account = "..." } }`.

- Recognition: a struct with exactly one field from that list (morphir-moonbit
  rule). `SecretSyntax::standard()` is the default. `SecretSyntax::none()` turns
  recognition off (**Call (this change)**, because an app can have a real key
  named `env` in a one-field table).
- **Call (this change)**: the build checks the payload shape. A wrong shape raises
  `ConfigError::InvalidSecret` at load time, not at resolve time.
- `SecretResolver` is a trait with one method:
  `resolve(Self, SecretRef, Origin) -> Secret raise SecretError`. The origin lets a
  file resolver anchor a relative path to the directory of the declaring file.
- `Config::secret(key, resolver)` resolves one key. A plain string at the key is a
  literal secret. The resolver is not called.
- `Secret` is opaque. `Show` writes `<redacted>`. Only `Secret::expose()` gives the
  text.
- `SecretError` classes (from Morphir `config.feature`): `MissingConfigKey`,
  `EmptyEnvironment`, `FileRead`, `InvalidSecretValue`, `CommandFailed`,
  `KeyringLookupFailed`. Messages never hold the secret or backend output.
- **Call (this change)**: the core ships one resolver, `env_resolver(vars)`, over an
  explicit variable map. File, command, and keyring resolvers do I/O, so they are
  host adapters in a later change.
- **Call (this change)**: display shows a secret reference as the reference, for
  example `{env = "TOKEN"}`, because the reference holds no secret. Key-name
  redaction still applies on top.

The Morphir spec also lists "a secret string" (a schema `secretValue` position)
as a leaf. Morphir schema version 1 uses no such position. This design does not
model it. Binding can add it.

### D11. Redaction and command helpers

**Call**: helpers for `config get`, `config show`, and `config path`, with
redaction. All are pure functions that return `String` or `Json`. The host change
prints them.

- `redact(value)` follows Morphir `redact_secrets`: lowercase, `-` to `_`,
  substring match on the nine fragments, replace the whole subtree with
  `<redacted>`. The fragment list is a parameter with the Morphir list as default
  (**Call (this change)**).
- `get_text(config, key)` and `get_json(config, key)` redact first, then look up,
  as Morphir does, so a get on a parent struct is safe too.
- `show(config, format)` with `ShowFormat` `Toml`, `Json`, or `Ion`.
  **Call (this change)**: Ion is added because it is the native tree and loses
  nothing. TOML render converts to `@toml.TomlValue` and uses its writer.
- `path_text(reports)` and `path_json(reports)` follow the Morphir layout:
  heading `Configuration sources (in priority order):`, highest priority first,
  `[✓]` for loaded and `[✗]` for others, then `Path:`, `Status:`, `Priority:`
  lines. JSON lists sources in ascending priority. Priorities never decrease along
  the list (R6), so the text form is the reverse merge order and the JSON form is
  the merge order. Each report shows its kind name from the table in D4 (R4) and
  its warnings.
- `explain(config, key)` gives `Array[(KeyPath, Array[Origin])]`.

Render mapping for JSON and TOML: Int and Decimal keep their exact text, Timestamp
becomes ISO 8601 text (TOML: a date-time value), Symbol becomes a string, Blob and
Clob become base64 text, annotations go. A null in a list raises
`ConfigError::Render` for TOML. NaN and infinity raise `ConfigError::Render` for
JSON.

### D12. Errors

**Reference** (morphir-moonbit pain point): it has one `Invalid(String)` error and
maps exit codes by string compare.

**Call (R3)**: `ConfigError` is one `suberror` in core. It holds every
configuration case of the four changes, so a host matches one type. Core declares
all cases. The conventions and binding changes raise their cases and do not add
error types. Each case uses labelled fields:

| Case | Data | Raised by |
| --- | --- | --- |
| `Parse` | format, origin, message, line?, column? | core formats |
| `UnsupportedYaml` | origin, feature, line, column | core YAML format |
| `InvalidRoot` | origin, found type | core formats |
| `DuplicateKey` | origin, key path | core formats, `ConfigValue::from_ion` |
| `FileNotFound` | path | core explicit file |
| `UnsupportedFormat` | path, registered extensions | core registry |
| `Ambiguous` | `display~`, `location~`, `candidates~` | core and conventions (R2) |
| `InvalidKeyPath` | text, reason | core |
| `InvalidEnvKey` | variable name | core environment source |
| `MergeKey` | key path, item index, source | core merge |
| `InvalidSecret` | key path, origin, reason | core secrets |
| `KeyNotFound` | key path | core helpers |
| `Render` | format, key path, reason | core helpers |
| `SourceOrder` | source, priority, previous source, previous priority | core builder (R6) |
| `OutsideBoundary` | start directory, boundary | conventions |
| `InvalidEnvironmentName` | name, reason | conventions |
| `UnknownProject` | selector, workspace | conventions |
| `AmbiguousProject` | selector, matches | conventions |
| `Decode` | `failure~ : BindFailure` | binding |
| `Validation` | `failures~ : Array[BindFailure]` | binding |

The `Ambiguous` message is `Ambiguous <display> configuration; found: <paths>`, so
the Morphir preset keeps `Ambiguous Morphir configuration`.

**Call (R3)**: core declares `BindFailure` and the types in it, so `ConfigError`
is complete in the first change. The binding change fills the values and owns
their meaning:

```moonbit
pub(all) enum DecodeStep {
  Field(String)
  Index(Int)
} derive(Eq, Debug)

pub(all) struct DecodePath {
  key : KeyPath?               // None: the root of the bound tree (bind_root)
  suffix : Array[DecodeStep]   // empty, or starts with Index
} derive(Eq, Debug)            // renders as text, for example targets[1].level

pub(all) enum Blame {
  Set(Array[Origin])     // the sources that set this leaf or list; never empty (R10)
  Table(Array[Origin])   // the key is a table; the sources that set keys in it
  Default                // the value came from the bind default
  Unset                  // no source sets this key
} derive(Eq, Debug)

pub(all) struct Located {
  path : DecodePath
  blame : Blame
} derive(Eq, Debug)

pub(all) struct BindFailure {
  at : Array[Located]    // one or more paths; never empty
  detail : String
} derive(Eq, Debug)
```

**Call (R3, R5, R10)**: these names and shapes match the
`add-configuration-binding` design exactly. `key` holds the leading names up to the
first list index; `suffix` holds the steps from that index on. Core declares the
types and renders `DecodePath` as text. If the binding change refines a field, it
records the change in its own design, and the core task that declares the types
follows it.

`ConfigError::message()` gives text for people. It shows paths as the error holds
them and does not convert them; the host adapter gives them in the `/` form (D13).
For `Decode` and `Validation` it gives the binding D5 text: one line
`<path>: <detail> (<blame text>)` for each `Located`, and `Validation` joins its
failures with a newline. The origin text is the role name and the path for a
file, `environment <VAR>` for the environment source, and else the kind name.
The blame text is `set in <origins>`, `table set in <origins>`, `not set by any
source`, or `from the bind default`. An empty `Table` gives `empty table, no
source sets keys in it`. **Call (this change)**: `Origin`, `SourceKind`,
`FileRole`, and the `Ambiguous` case are declared with the errors (task 14.1),
before the provenance and source model groups add their behavior. These types
derive `Debug`, not `Show`, because `derive(Show)` is deprecated.
Hosting owns `UsageError` for CLI misuse, for example an empty `--environment`
value (R3). Every `ConfigError` is a usage error; `add-host-lifecycle` maps it to
exit code 2 (**Call**).

### D13. Pure load, file tree, and host adapter

**Call**: pure core over explicit inputs (morphir-moonbit ADR 0002: sync core,
async hosts prepare snapshots).

**Call (R1)**: core defines the one snapshot type, `FileTree`. Explicit file
sources and conventions discovery both read it.

```moonbit
pub(all) enum EntryKind { File; Directory; Other } derive(Eq, Debug)

pub(all) struct DirEntry { name : String; kind : EntryKind } derive(Eq, Debug)

// Opaque and immutable: directory listings, file text, and a `complete` flag.
pub struct FileTree { .. }

pub(all) enum FileRequest {
  ListDir(String)
  ReadFile(String)
} derive(Eq, Hash, Show)

pub(all) enum LoadStep[T] {
  Need(Array[FileRequest])
  Done(T)
} derive(Eq, Debug)
```

- `FileTree` holds listings with the real names and file text, keyed by path.
  `FileTree::with_listing` and `FileTree::with_file` return a new tree.
- **Call (review)**: `FileTree::with_missing(path)` returns a new tree that records
  `path` as absent. The host adapter uses it when a read or a listing finds no file
  or directory. A path under a missing directory is also absent. An absence record
  answers a request, so the next round does not ask for that path again, and the
  tree can stay incomplete for paths that later rounds find.
- **Call (this change)**: `FileTree::new(complete?)` makes an empty tree.
  `FileTree::file(path)`, `FileTree::listing(dir)`, and `FileTree::is_file(path)`
  give `Lookup[T]` (`Found(T)`, `Missing`, or `Unknown`), so a provider reads the
  tree with the same three states as the load. `is_file` applies the exact-name
  rule over the listing of the parent directory.
- A path is in one of three states: held (listing or file text), missing (an
  absence record, or any path when `complete` is true), or unknown. The load asks
  only for unknown paths.
- **Call (R1)**: a complete tree never gives `Need`.
- **Call (this change)**: the existence check for a candidate reads the listing of
  its directory and compares exact names. A probe on a case-insensitive file system
  would find `App.toml` for `app.toml`. The conventions change uses the same rule.

**Call (R1)**: entry points.

- `@config.load(builder, tree) -> LoadStep[Config] raise ConfigError` is pure and
  runs on all targets. It asks for the listings and files that its file sources
  need and that the tree does not hold, all in one `Need`. With all inputs present,
  it builds and gives `Done(config)`. The same inputs give the same result on every
  target.
- `@config/host.load(builder) -> Config raise` is `async` and runs on native and
  js. It uses the variable set and the working directory that the builder holds.
  **Call**: only when the builder holds no variable set does the adapter read the
  process variables, and only when it holds no working directory does it read the
  process working directory. It sets the `Platform` (`platform`), and then
  runs the request loop: call `@config.load`, answer each `Need`, add the answers
  to the tree, and call again. When a read or a listing finds no file or directory,
  the loop adds `with_missing(path)`, so each round makes progress and never asks
  for the same path twice.
- Hosting `run` calls these entry points. A wasm or wasm-gc host gives the tree
  with `|> @hosting.files(tree)` and gets the result from `@config.load` with a
  complete tree.

**Call (this change)**: a relative explicit path joins the working directory of the
builder (`@config.working_dir`). With no working directory, the path stays as given.
Reports and origins show the joined path.

**Owner (2026-10-20)**: one variable set and one working directory for each run.
Nothing reads the process environment or the process working directory, except
where a host fills a value that nobody gave. In a hosted run, hosting fills both
values one time and gives them to the builder, so `config/host` reads nothing from
the process. **Call (R1)**: a process read uses `moonbitlang/core/env`
(`get_env_vars`, `current_dir`) on native and js, because `moonbitlang/async` has no
environment API.

| Target | Files | Variable set and working directory |
| --- | --- | --- |
| native | `moonbitlang/async` `fs` | the builder values, else `moonbitlang/core/env` |
| js | TypeScript adapter over `node:fs` (O2) | the builder values, else `moonbitlang/core/env` |
| wasm, wasm-gc | injected `FileTree` | the builder values from the host |

**Owner (O2)**: js file access uses a TypeScript adapter against `node:fs`,
`node:path`, and `node:process`, built and bundled with Bun. Bun is pinned in
`.config/mise/config.toml`. A moonx task script runs the build, as AGENTS.md
requires. MoonBit `extern "js"` functions call the bundled module. The js console
lifetime of `add-host-lifecycle` (signals through `process.on`) lives in the same
TypeScript adapter.

**Call (O2)**: the TypeScript uses only `node:*` APIs that both Node and Bun
support, so the bundle runs on Node (the js tests use the pinned Node) and on Bun.

**Call (this change)**, native adapter (task group 15): `ConfigBuilder` gives
`given_env_vars()`, `given_working_dir()`, and `given_platform()`, so the adapter
fills only what nobody gave. The platform comes from `@async.platform`, so no C
stub is needed. A listing includes hidden entries, and an entry kind follows
symbolic links. A path that does not exist, or that is not a file (for a read) or
a directory (for a listing), becomes an absence record. Other file-system errors
pass out of `load`. `config/host` supports only `native` until the js adapter
(task group 16) lands.

**Call (this change)**: the adapter uses the synchronous `node:fs` calls
(`readdirSync`, `readFileSync`, `statSync`). The MoonBit side then needs no promise
bridge, and one loop round reads all requests at once. Configuration files are
small, so blocking reads are acceptable.

**Call (this change)**: the TypeScript source is in `pkgs/lander/adapters/node/`.
The moonx task script bundles it and writes the bundle as a generated MoonBit js
file in `config/host`, which is checked in. So `moon build` and `moon test` do not
need Bun, and CI checks that the generated file is current. Feasibility of this
link step is not verified yet; the first js adapter task is a spike that proves it.

**Owner (O2)**: AGENTS.md says to use `moonbitlang/async` for file-system work. A
task adds a narrow exception for the TypeScript adapter on js (R12).

**Owner (O3)**: Windows has full support in the first stories. A windows-latest CI
leg builds and tests native and js. The native adapter is tested on Windows.

**Call (O3)**: `FileTree`, reports, origins, and errors use paths with `/` on every
platform, Windows included. An absolute path starts with `/`, a drive prefix
(`C:/`), or a UNC prefix (`//server/share`). The Windows adapter converts `\` to `/`
when it reads the working directory, listings, and paths, and converts back only
for file-system calls. The Morphir Rust loader shows native separators on Windows;
this is a known display difference.

### D14. Morphir code worth keeping

From morphir-moonbit `config.mbt`:

- `merge_value` and the provenance update in `merge` (rules D8 and D9).
- `secret` recognition (D10).
- `environment` and `environment_value` (D6), including the sort that makes the
  shorter path win and the `+003` integer rule.
- `Document::shared` as the generic exclude list (D4).
- The tests "merge replaces arrays and secrets, preserving winning provenance",
  "environment preserves underscores and shorter paths win", and "environment
  conversions follow upstream mapping" become spec scenarios.

Not kept: `TomlValue` as the model, `Document::text/strings/boolean` lookups with
fallbacks (binding replaces them), and `Invalid(String)`.

### D15. Format trimming with a virtual package (Owner (2026-10-20); verified by probe)

Owner: formats must be trimmable "in a minimal manner". A program that uses only TOML
must not link the YAML, JSON5 and Ion parsers.

- The virtual package `moonrockz/moon-lander/formats` has
  `options("virtual": { "has-default": true })` in its `moon.pkg` and a hand-written
  `pkg.mbti`:

  ```moonbit
  package "moonrockz/moon-lander/formats"

  import {
    "moonrockz/moon-lander/config",
  }

  // Values
  fn formats() -> Array[@config.Format]
  ```

- The default implementation imports `config/formats/toml`, `config/formats/yaml`,
  `config/formats/json5` and `config/formats/ion`, and gives their formats in that
  order. Call (this change): these four packages cover the five formats, because the
  JSON5 package gives one format for `.json` and `.json5` (D7). The order sets only
  the order of candidates in reports (conventions D3).
- The shipped implementation package `moonrockz/moon-lander/formats/toml` has
  `options("implement": "moonrockz/moon-lander/formats")` and gives TOML only. For
  another mix, the application writes a small implementation package of its own.
- An application trims with one line in its own main `moon.pkg` and no code change:

  ```moonbit
  options(
    "is-main": true,
    overrides: [ "moonrockz/moon-lander/formats/toml" ],
  )
  ```

- `@config` does not import `formats`. Only the `@lander` entry of
  `add-host-lifecycle` imports it. The bare path stays as in D1.

Probe evidence (`moonc v0.10.15`, scratchpad, 2026-10-20). A library package called
the virtual package. The probe interface gave `Array[String]` with three stand-in
parsers:

- The default app printed three formats. The trimmed app printed one.
- Output sizes, default and trimmed: wasm 6018 and 5649 bytes, wasm-gc 2233 and 1982
  bytes, js 1934 and 1210 bytes, native 284880 and 284400 bytes.
- Unique marker strings of the unused parsers were absent from all four trimmed
  outputs.
- A separate consumer module in a `moon.work` workspace overrode the virtual package
  of the library module on all four targets.

Not verified:

- An override from a consumer that gets `moonrockz/moon-lander` from mooncakes.io and
  not from a workspace. A pre-publish task checks it (see Risks).
- A hand-written `pkg.mbti` that names a type of another package
  (`@config.Format`). The probe used `Array[String]`. The first task of the story
  checks it.

### Decisions made in this change (not in the brief)

1. `SourceSelection[T]` with a type parameter (D4).
2. Default priority from the kind and role; an in-memory source takes the priority
   before it (D4).
3. `File(Explicit)` and `File(Legacy)` show the report name `project` (D4).
4. In-memory pairs: list order, no type inference (D5).
5. Reserved environment names compare without case (D6).
6. Empty-key environment variable is an error; an empty environment reports
   `loaded`; a `Discover` environment with no variable set reports `not-found`
   (D6).
7. KeyPath quoting and exact case (D3).
8. Sexp as list; annotation rule for merged structs (D2).
9. Format selection by extension; `.yml` accepted; Ion text only (D7).
10. YAML default profile: one document and no merge keys (D7).
11. YAML integers above `Int64` stay exact (D7).
12. JSON integral numbers up to 2^53 become Int (D7).
13. Null struct fields removed from the result (D8).
14. `SecretSyntax::none()`; payload check at load; only an env resolver in core;
    references shown as references (D10).
15. Configurable redaction fragments; Ion as a show format (D11).
16. Source providers as the discovery entry point; `Platform` in core and in the
    load context; `ConfigWarning::Note` for provider warnings (D4a).
17. Candidate existence from exact names in directory listings (D13).
18. Synchronous `node:fs` calls in the TypeScript adapter; source in
    `pkgs/lander/adapters/node/`; checked-in generated bundle (D13).
19. A relative explicit path joins the working directory of the builder (D13).
20. The default `formats` implementation links the four format packages in the order
    TOML, YAML, JSON5, Ion (D15).

## Risks / Trade-offs

- [The one-field secret rule treats a real table such as `[deploy] env = "prod"`
  as a secret reference] → `SecretSyntax::none()` turns it off; the payload check
  gives an early, clear error.
- [`json5` numbers are `Double`; integers above 2^53 lose precision with no
  error] → document it; tell users to use TOML or Ion, or a string, for such
  values. Revisit if `moonbitlang/x` adds source text to numbers.
- [`json5` cannot report duplicate keys] → document it as a known difference from
  TOML, YAML, and Ion.
- [TOML 0.5.0 and Ion errors have no structured position] → keep the library
  message, which holds the location as text. Add a position when the libraries
  give one.
- [A custom YAML event builder can drift from the library scalar rules] → test the
  builder against `Yaml::load_from_string` on the library examples.
- [The Ion tree is larger than a plain JSON tree] → configuration files are small.
  Merge shares unchanged subtrees.
- [`moonbitlang/async` has no js `fs`] → the TypeScript adapter over `node:fs`
  reads files on js (O2). It is a second I/O stack to keep in step with the native
  adapter → one request-loop contract and one acceptance suite run on both.
- [The link from MoonBit js externs to a Bun bundle is not verified] → the first js
  adapter task is a spike. If it fails, stop and return to the owner.
- [Windows path forms (drive, UNC, `\`) can leak into reports] → the adapter
  converts at the boundary (O3), and the windows-latest CI leg tests it.
- [The `formats` override is verified only inside a `moon.work` workspace. A
  consumer that gets `moonrockz/moon-lander` from mooncakes.io may not be able to
  override it] → A pre-publish task checks the override from a registry consumer.
  If it fails, tell the owner before the first publish. The fallback is the bare
  path: the application registers its formats itself.
- [A hand-written `pkg.mbti` can drift from the default implementation] → The build
  checks each implementation against the interface. The CI size and marker
  check builds both a default app and a trimmed app on all four targets.
- [Substring redaction hides some safe keys, for example `tokenizer_mode`] →
  this matches Morphir and errs on the safe side.

## Migration Plan

This change adds packages and changes no current API. morphir-moonbit moves later:

1. Replace `@config.Document` with `@config.Config`, keeping the TOML model only in
   the TOML format package.
2. Replace `Document::text/strings/boolean` calls with binding
   (`add-configuration-binding`).
3. Replace `Invalid(String)` matches with `ConfigError` cases.

Rollback: remove the new packages. No current consumer depends on them.

## Open Questions

- Should the Ion format read Ion binary later? This needs no spec change for text.

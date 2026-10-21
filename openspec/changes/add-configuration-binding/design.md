# Design: add-configuration-binding

## Context

See `proposal.md` for the reason for this change. Binding uses these names from
`add-configuration-core`: `Config` (the merged tree with provenance), `ConfigValue`
(the Ion-based tree), `KeyPath`, `Origin` (one provenance record), `SourceKind`,
`FileRole`, `SecretRef`, `ConfigError`, and `BindFailure` with the types that it
holds (`DecodePath`, `DecodeStep`, `Located`, `Blame`). Binding lives in the same
package, `moonrockz/moon-lander/config` (`@config`).

Labels in this document:

- **Owner**: the project owner made the decision.
- **Call**: the designer made the decision in the design brief, and the owner did
  not reject it.
- **Call (Rn)**: a reconciliation call from the addendum of 2026-10-20. The
  addendum overrides the brief and the first drafts of the four changes.
- **Call (O3)**: a designer call inside owner answer O3 of the same addendum.
- **Call (this change)**: the author of this change made the decision. The brief
  and the addendum do not cover it. The owner must review it.

### Observed `FromJson` behavior

A throwaway project tested `@json.from_json` and `derive(FromJson)` with the pinned
toolchain: `moon 0.1.20261012 (748b63c)`, `moonc v0.10.15+943464bfa`. Results:

| Case | Observed result |
| --- | --- |
| Signature | `from_json[T : FromJson](Json, path? : JsonPath) -> T raise JsonDecodeError` |
| Error type | `suberror JsonDecodeError { JsonDecodeError((JsonPath, String)) }` |
| Path type | `JsonPath` is an abstract type outside `moonbitlang/core/json`. Its constructors (`Root`, `Key`, `Index`) are not public. Public operations: `add_key`, `add_index`, `to_string`, `to_json`, `Eq`. |
| Path text | `to_string` gives an RFC 6901 JSON Pointer: `/inner/level`, `/1/level`, empty text for the root. `~` becomes `~0` and `/` becomes `~1`. `to_json` gives the same text as a JSON string. |
| Missing required field | Error at the parent path. Example: path root, message `Missing field strict`. The missing field name is only in the message text. |
| Missing nested field | Path `/inner`, message `Missing field level`. |
| Unknown field | Ignored without an error, at all levels. |
| `Option` field absent | Decodes to `None`. |
| `Option` field set to `null` | Fails: path `/tag`, message `String::from_json: expected string`. |
| `Option[T]` decoded alone from `null` | Decodes to `None`. |
| Wrong type | Path to the leaf, message such as `Int::from_json: expected number`. |
| Element in a list | Path includes the index: `/1/level`. |
| `Int` from `1.5` | Decodes to `1`. The fraction is lost without an error. |
| `Int` from `3000000000` | Fails: `Int::from_json: overflow`. |
| `Int64` from a JSON number | Fails: `Int64::from_json: expected number in string representation`. `Int64` decodes only from a JSON string, and `ToJson` for `Int64` writes a string (`"42"`). |
| `Double` or `Bool` from text | Fails (`expected number`, `expected boolean`). There is no text coercion. |
| Not an object | Root path, message `Expected object to deserialize Opts`. |
| Enum | Unit constructor as `"SingleFile"`, payload constructor as `["Split",2]`. The text `"single-file"` fails. |
| `Map[String, T]` | Decodes each key. Error path includes the key, for example `/a~1b`. |
| `ToJson` of a `None` field | The field is not written. |
| `derive(FromJson(fields(b(default=7))))` | Works, with the warning `The syntax derivation argument default for advanced layout tweaking is deprecated`. |
| `rename_fields="kebab-case"`, `fields(x(rename="y"))` | Work with no warning on this toolchain. |

The probe also compiled the API shapes in this document: a generic return type
inferred through `|>` (`let ir : Ir = config |> bind("ir")`), a trait method with a
default implementation (`validate(Self) -> ... = _`), and
`impl[T : Validate] Validate for Map[String, T]`.

### Ion to Json conversion

`moonrockz/ion@0.6.0` (`pkgs/json/to_json.mbt`) converts Ion to `Json` as follows:
an `int` becomes a number and keeps all digits in `repr`; a `decimal` becomes a
number with its exact text in `repr` (`1.50` stays `1.50`); a `timestamp` becomes
its Ion text; a symbol becomes a string; a blob becomes base64 text; NaN and
infinity become `null`; annotations are removed. `Json` decoders read only the
`Double` of a number, so the `repr` text does not help `FromJson`. Ion has no
`FromIon` trait. `@ion.Decimal` has `coefficient : BigInt` and `exponent : Int`.
`@ion.Timestamp` has precision, optional fraction (a `Decimal`) and offset.

### Current lookups in morphir-moonbit

At commit `32ab9d7`, morphir-moonbit reads configuration through `Document`
methods with dotted text keys. A search of `pkgs/` and `apps/` (tests excluded)
finds 64 such calls. They have four shapes:

| Shape | Examples | Count |
| --- | --- | --- |
| `text(key, fallback)` | `ir.mode`, `ir.layout`, `ir.format`, `pipeline.target`, `pipeline.build_timeout`, `workspace.out_dir`, `project.name` | 34 |
| `strings(key)` | `workspace.members`, `workspace.exclude`, `project.exposed_modules`, `pipeline.components` | 9 |
| `boolean(key, fallback)` | `ir.strict_mode`, `pipeline.strict_naming` | 4 |
| `get(key)` and a match on the TOML value | `metadata.provider`, `frontend.provider`, `ir.format_version`, `workspace.output_dir` | 17 |

Each call repeats its fallback. A type mismatch raises `Invalid("Expected string at
ir.layout")` with no source. Only `config/metadata_provider.mbt` adds the source: it
reads `Document.provenance` and raises
`Invalid("metadata.invalid_configuration: <key> <detail> (set in <file>)")`. Its
`MetadataPath { path, origin }` keeps the file that set a path so that the host can
resolve it. This change makes that error model the default for all keys.

## Goals / Non-Goals

**Goals:**

- One typed read for each section, with defaults in one place.
- Each error names a full decode path and a source, or says why there is no source.
- Validation reports all failures in one error.
- Exact values for decimals, timestamps and large integers when the application
  asks for them.
- Pure functions that work on the four targets and in `|>` pipelines.

**Non-Goals:**

- Text coercion (for example `"true"` to `Bool`). The environment source in the
  core already types values.
- Collection of more than one decode failure in one instance. `FromJson` stops at
  the first failure.
- Field name conversion (for example kebab-case keys). Types can use derive
  arguments or a manual `FromJson`.
- A derive macro for `FromConfig`. MoonBit has no user derive.
- A binding error type of its own. Binding raises the core `ConfigError` only.

## Decisions

### D1. Bind to concrete values (Owner)

The application reads typed values, like .NET `Get<T>`, `Bind` and the Options
pattern. MoonBit values are immutable, so there is no `Bind(instance)` that
changes an object. `bind_or` with a default value has the same function.

### D2. `bind` and `bind_root` for `T : FromJson` (Call; `bind_root` is Call (R5))

`bind` selects the section, converts it to `Json`, and calls `@json.from_json`. It
depends only on the `FromJson` trait, not on derive arguments (see D10).

```moonbit
pub fn[T : FromJson] bind(config : Config, key : String) -> T raise ConfigError

pub fn[T : FromJson] Config::bind(self : Config, key : String) -> T raise ConfigError

pub fn[T : FromJson] bind_root(config : Config) -> T raise ConfigError
```

```moonbit
struct IrOptions {
  layout : String
  strict_mode : Bool
} derive(FromJson, ToJson, Debug)

let ir : IrOptions = ctx.config |> @config.bind("ir")
let same : IrOptions = ctx.config.bind("ir")
let app : AppConfig = ctx.config |> @config.bind_root()
```

The `key` argument is the dotted text form of a core `KeyPath`. The core parses it
with `KeyPath::parse`, so a name with `.` or `"` uses TOML-style quotes
(`servers."eu.west".port`). A `KeyPath` is not empty and has no list index
(Call (R5)). Empty text, or text that does not parse, raises the core
`InvalidKeyPath` error. To decode the full configuration, the application calls
`bind_root(config)`.

### D3. `bind_or` merges configuration over a default (Call, name refined in this change)

The brief wrote `bind("ir", default=IrOptions::default())`. That shape cannot
compile with a `FromJson`-only `bind`: an optional argument `default? : T` needs
`T : ToJson` in the signature, so every `bind` would need `ToJson`. This change
uses a second function, `bind_or`. It keeps `bind` free of `ToJson`.

```moonbit
pub fn[T : FromJson + ToJson] bind_or(
  config : Config,
  key : String,
  default : T,
  unknown? : UnknownKeys = Allow,
) -> T raise ConfigError
```

Steps: write `default` with `ToJson`, place it as the only field of a synthetic
root struct, place the section under the same field of a second synthetic root,
merge the two roots with the core merge function, take the field back out, then
decode. **Call (review)**: the synthetic roots keep the core rule that a tree root
is a struct, so a scalar or list default works: `bind_or(config, "mode", "safe")`
and `bind_or(config, "targets", ["js"])` are valid. A configured scalar or list
replaces the default; an absent or `null` section keeps it. The core
rules apply: tables merge, lists replace, a `null` overlay does not change the
default. Leaves that come from the default get the blame `Default` (D4). A `None`
field in the default is not written (observed), so a configured value fills it.

```moonbit
let ir : IrOptions = ctx.config
  |> @config.bind_or("ir", { layout: "single-file", strict_mode: false })
```

Alternatives: (a) `ToJson` on all `bind` calls (rejected: the owner sketch derives
only `FromJson`); (b) a wrapper `Seed[T]` made by `@config.seed(value)` so that
`bind` can keep a `default?` argument (rejected: more words at each call).

### D4. Source-aware typed errors (Call (R3), Call (R5), Call (R10); field details in this change)

**Call (R3)**: one `ConfigError` suberror in the core holds every configuration
case. The core declares `Decode(BindFailure)` and `Validation(Array[BindFailure])`,
and it declares `BindFailure` and the types that it holds. Binding fills these
values and raises them. Binding adds no case to `ConfigError` and has no error type
of its own. The host maps every `ConfigError` to exit code 2.

The shapes that binding needs (the core change owns the declarations):

```moonbit
pub(all) enum DecodeStep {
  Field(String)
  Index(Int)
} derive(Eq, Debug)

pub(all) struct DecodePath {
  key : KeyPath?               // None: the root of the bound tree
  suffix : Array[DecodeStep]   // empty, or starts with Index
} derive(Eq, Debug)

pub(all) enum Blame {
  Set(Array[Origin])     // the sources that set this leaf or list; never empty
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

**Call (R5)**: a decode error carries a `DecodePath`, not a `KeyPath`, because a
decoder can fail inside a list. `key` holds the leading names up to the first list
index. `suffix` holds the steps from the first list index on. The provenance of the
core has no list index, so binding looks up blame at `key`.

Path translation: `JsonPath` is abstract, so binding reads `path.to_string()`,
splits the JSON Pointer at `/`, and replaces `~1` with `/` and `~0` with `~`. A
segment that is a list index in the tree becomes `Index`. Other segments become
`Field`. The section key plus these steps gives the full `DecodePath`. For
`bind_root`, the steps start at the root.

Text form: `key` uses the core `KeyPath` text. `Index(n)` gives `[n]`. `Field(name)`
after an index gives `.name`, with the same quote rule as `KeyPath`. A path with no
`key` and no `suffix` gives `(root)`. Examples: `ir.strict_mode`, `targets[1].level`,
`servers."eu.west".port`. The core implements this text form; binding fills the
`DecodePath` and does not render it.

Blame: binding looks up the provenance record at `key`. A list has one record for
the whole list, so an error inside a list gets the blame of the list.
**Call (R10)**: a list record gives `Set(Array[Origin])`. The array is never empty.
It has one origin for a replaced list, and every contributing origin, in merge
order, for an appended or merged list. If `key` is a table, the blame is `Table`
with the distinct origins of its leaves in merge order. The array is empty only for
an empty table. If nothing sets the key, the blame is `Unset`. When `bind_or` gives
the tree, a leaf that the default supplied gets `Default`.

**Call (this change)**: merge order for `Table` origins is the order of the source
reports; an origin matches the report with the same kind, name, priority, and
path. A path with no key (the root of `bind_root`) gets `Table` with the origins of
every leaf. A value with no JSON form fails as `Decode` at the section, with the
conversion message as its detail.

### D5. Origin text in errors (Call (R4), Call (O3); format in this change)

Rendering follows `metadata_provider.mbt`: `<path>: <detail> (<blame text>)`. The
core `ConfigError::message()` implements this format; binding fills the values.

```text
ir.strict_mode: Bool::from_json: expected boolean (set in user-override /repo/morphir.user.toml)
ir: Missing field layout (table set in user-override /repo/morphir.user.toml, environment MORPHIR_IR__STRICT_MODE)
targets[1].level: Int::from_json: expected number (set in workspace-member /repo/app/morphir.toml)
server.port: no value (not set by any source)
ir.layout: must be one of single-file, split (from the bind default)
```

**Call (R4)**: the text of an `Origin` comes from the core. For a file source it is
the Morphir name of its `FileRole` (for example `user-override`) and the file path.
For the environment source it is `environment` and the variable name. Other kinds
use their kind name. `Set` with more than one origin lists them, separated by
commas, in merge order.

**Call (O3)**: errors show file paths with `/` on every platform, also on Windows.
The core host adapter converts paths at the boundary, so the `Origin` already holds
`C:/repo/morphir.toml`. Binding does not convert paths.

Binding never puts a configured value in the text. Decoder messages from core
`FromJson` do not include values (observed).

### D6. `Validate` trait (Call, shape in this change)

```moonbit
pub(all) struct Violation {
  at : Array[Array[DecodeStep]]   // paths relative to the bound section; empty = section
  detail : String
} derive(Eq, Debug)

pub(open) trait Validate {
  validate(Self) -> Array[Violation] = _
}

impl Validate with validate(_) { [] }

pub fn violation(fields : Array[String], detail : String) -> Violation
pub fn nested(field : String, found : Array[Violation]) -> Array[Violation]
```

`validate` is pure and returns all violations. It does not raise. `violation` makes
one relative path for each field name. Binding joins the section key and each
relative path into a full `DecodePath`, finds the blame (D4), turns each
`Violation` into a `BindFailure`, and raises `Validation` with all of them. The
package supplies `impl[T : Validate] Validate for Map[String, T]`, `Array[T]` and
`T?`. The map adds `Field(key)` in front of the child paths, and the array adds
`Index(i)`. `nested` adds `Field(field)` in front of the paths of a nested value:

```moonbit
impl @config.Validate for PipelineOptions with validate(self) {
  let found = []
  if self.target == "" {
    found.push(@config.violation(["target"], "must not be empty"))
  }
  if !["strict", "lenient"].contains(self.validation) {
    found.push(@config.violation(["validation"], "must be strict or lenient"))
  }
  found.append(@config.nested("ir", @config.Validate::validate(self.ir)))
  found
}
```

Alternative: a mutable collector argument (`validate(Self, Checks) -> Unit`).
Rejected: the pure result is easier to test and fits the immutable-value rule.

### D7. `Options[T]` and named options (Call, shape in this change)

```moonbit
pub struct Options[T] {
  value : T
  key : KeyPath
  name : String?
}

pub struct NamedOptions[T] { /* private: Map[String, Options[T]] */ }

pub fn[T] NamedOptions::get(self : NamedOptions[T], name : String) -> Options[T]?
pub fn[T] NamedOptions::names(self : NamedOptions[T]) -> Array[String]

pub fn[T : Validate] validated(
  value : T,
  config : Config,
  key : String,
  name? : String,
) -> Options[T] raise ConfigError

pub fn[T : FromJson + Validate] options(config : Config, key : String) -> Options[T] raise ConfigError

pub fn[T] named(
  config : Config,
  key : String,
  bind_one : (Config, String) -> Options[T] raise ConfigError,
) -> NamedOptions[T] raise ConfigError
```

`validated` takes the value first, so it closes a pipeline. `options` is the short
form of `bind` then `validated`. Options always have a section key, because a
`KeyPath` is not empty (D2). `named` calls `bind_one` for each child key of the
section, collects all `Decode` and `Validation` failures, and raises one
`Validation` if there are any. Because `bind_one` is a function, `named` works with
`bind`, `bind_or` and `bind_with`.

```moonbit
let ir : Options[IrOptions] = ctx.config
  |> @config.bind_or("ir", IrOptions::default())
  |> @config.validated(ctx.config, "ir")

let backends : NamedOptions[BackendOptions] = ctx.config
  |> @config.named("backends", fn(config, key) {
    config
    |> @config.bind_or(key, BackendOptions::default())
    |> @config.validated(config, key)
  })
```

Options values go into the application services record `S` of `Host[S]`. There is
no options monitor or snapshot, because the configuration does not reload.

### D8. `FromConfig` trait and `bind_with` (Call, shape in this change)

```moonbit
pub struct ConfigNode { /* private: config, decode path, value or absent, blame */ }

pub fn ConfigNode::path(self : ConfigNode) -> DecodePath
pub fn ConfigNode::value(self : ConfigNode) -> ConfigValue?
pub fn ConfigNode::blame(self : ConfigNode) -> Blame
pub fn ConfigNode::child(self : ConfigNode, name : String) -> ConfigNode
pub fn ConfigNode::children(self : ConfigNode) -> Array[(String, ConfigNode)]
pub fn ConfigNode::items(self : ConfigNode) -> Array[ConfigNode]
pub fn[T : FromConfig] ConfigNode::get(self : ConfigNode, name : String) -> T raise ConfigError
pub fn[T : FromJson] ConfigNode::json(self : ConfigNode) -> T raise ConfigError
pub fn[T] ConfigNode::fail(self : ConfigNode, detail : String) -> T raise ConfigError

pub(open) trait FromConfig {
  from_config(ConfigNode) -> Self raise ConfigError
}

pub fn[T : FromConfig] bind_with(config : Config, key : String) -> T raise ConfigError
```

A node in a list has a `DecodePath` with an index suffix. `items` gives the
elements of a list, and each element node carries the blame of the list.

The package supplies `FromConfig` for `String`, `Bool`, `Int`, `Int64`, `UInt64`,
`Double`, `@bigint.BigInt`, `@ion.Decimal`, `@ion.Timestamp`, `SecretRef`, `T?`,
`Array[T]`, `Map[String, T]` and `Sourced[T]`. `Int` and `Int64` reject a fraction
and a value out of range. `ConfigNode::json` lets a `FromConfig` type decode one
part with `FromJson`, with the same error translation as `bind`.

```moonbit
struct Billing {
  rate : @ion.Decimal
  starts : @ion.Timestamp
  max_items : Int64
  lock : @config.Sourced[String]
  layout : IrOptions            // FromJson part
}

impl @config.FromConfig for Billing with from_config(node) {
  {
    rate: node.get("rate"),
    starts: node.get("starts"),
    max_items: node.get("max_items"),
    lock: node.get("lock"),
    layout: node.child("layout").json(),
  }
}

let billing : Billing = ctx.config |> @config.bind_with("billing")
```

`Sourced[T]` replaces `MetadataPath`:

```moonbit
pub struct Sourced[T] {
  value : T
  blame : Blame
}
```

Alternative: a `FromIon` trait in `moonrockz/ion`. Rejected for now: the node needs
provenance from `Config`, which Ion does not know.

### D9. Absent section decodes as `null` (Call (this change))

`bind` gives `Json::null()` to `from_json` when no source sets the key. Observed:
`Option[T]` decodes `null` to `None`, and other types fail. Binding then reports
blame `Unset`. Alternative: decode an empty object. Rejected: it hides a missing
scalar and gives a less clear error.

### D10. Secret references (Call (this change))

The core keeps a secret reference as a leaf. The `Json` view of a section does
not write a secret reference as an object. When the decode path meets a secret
leaf, binding raises `Decode` with the detail
`is a secret reference; bind it as SecretRef with bind_with`. `bind_or` does the
same check before it merges. Only `FromConfig for SecretRef` accepts the leaf, and
it returns the unresolved reference. Binding never calls the `SecretResolver`.

### D11. Depend only on the `FromJson` trait (Call, caveat from the brief)

MoonBit marks the derive argument `default` as deprecated (observed warning).
Binding does not use derive arguments, and its documentation does not recommend
them. Defaults come from `bind_or`.

### D12. Optional unknown-key check (Call (this change))

`FromJson` ignores unknown keys (observed), so a misspelled key has no effect. For
`T : ToJson + FromJson`, `bind_or` takes `unknown? : UnknownKeys = Allow`, where
`UnknownKeys = Allow | Reject | RejectExcept(Array[String])`. With `Reject`,
binding writes the decoded value back with `ToJson` and compares the key sets.

**Call (review)**: `Reject` is correct only when `ToJson` writes every key that
`FromJson` accepts, under the same name. A derived `FromJson` and `ToJson` pair with
the same arguments meets this. A hand-written pair may not: a decoder can accept an
alias (`port`) that the encoder writes as another name (`endpoint`), or accept a
key that the encoder leaves out. For such a type, the application uses
`RejectExcept(keys)`, which also accepts the listed relative key paths (for
example `"port"` or `"server.port"`). The package documentation states this
precondition. A configured key that is not in the result is a failure with its blame. All
unknown keys are reported in one `Validation` error. The default is `Allow`, to match
`FromJson`. A `None` field is not written by `ToJson`, but a configured value
makes it `Some`, so the check stays correct.

### D13. Purity and targets (Call (this change), from the project rules)

All binding functions are synchronous and pure over `Config`. They use no
`moonbitlang/async`, no files, no environment and no clock. One set of sources
serves all four targets. The windows-latest CI leg from `add-configuration-core`
runs the binding tests for `native` and `js` on Windows.

## Risks / Trade-offs

- [`Int` fields truncate fractions through `FromJson` (`1.5` gives `1`)] →
  Document it. Recommend `bind_with` for keys where this matters. `FromConfig for
  Int` rejects fractions.
- [`Int64` fields fail through `FromJson` with a TOML or JSON integer, because core
  `Int64::from_json` reads only text] → Document it. Use `FromConfig for Int64`.
  An acceptance test shows both results.
- [`Option` field set to `null` fails through derived `FromJson`] → The core does
  not let a `null` overlay change a value. Strict YAML and TOML have no `null`.
  A JSON source with an explicit `null` leaf gets a clear `Decode` error with blame.
- [A missing-field error names the parent table, and the field name is only in the
  message text] → Blame `Table` lists the sources of the table. Binding does not
  parse the message text, so a change to that text does not break binding.
- [`JsonPath` text format can change in core] → One function translates it. A test
  covers keys with `/` and `~`, and list indexes.
- [The core change declares `BindFailure`, `DecodePath`, `DecodeStep`, `Located`
  and `Blame` (Call (R3))] → Binding depends on these shapes. The first binding
  story checks that the core declarations match D4 before it adds code.
- [An error inside a list gets the blame of the whole list] → The core provenance
  has no list index. For an appended list, the blame names every contributing
  source, so the user still sees all candidates.
- [The round trip through `Json` costs time for each bind] → Configuration is
  small and binding runs once at start.

## Migration Plan

morphir-moonbit moves in its own repository after this change ships:

1. Define one record for each table (`IrOptions`, `PipelineOptions`,
   `WorkspaceOptions`, `ProjectOptions`, `FrontendOptions`, `MetadataOptions`) with
   `derive(FromJson, ToJson)` and a `default()` that holds the current fallbacks.
2. Replace each group of `text`, `boolean`, `strings` and `get` calls with one
   `bind_or` and `validated` call in the host build step. Put the options in the
   services record.
3. Move rules such as "Only ir.mode = classic is supported" into `Validate`.
4. Replace `MetadataPath` with `Sourced[String]` and `metadata_invalid` with
   `ConfigNode::fail`.

```moonbit
// Before (projects.mbt)
if effective.text("ir.layout", "single-file") != "single-file" ||
  effective.text("ir.format", "json") != "json" { raise Invalid("...") }

// After
let ir : Options[IrOptions] = config
  |> @config.bind_or("ir", IrOptions::default())
  |> @config.validated(config, "ir")
```

Rollback: binding adds API only. An application can keep its current reads.

## Open Questions

- Root forms of `bind_or`, `bind_with` and `options`. This change adds only
  `bind_root`. A later change can add the other root forms if an application
  needs them.

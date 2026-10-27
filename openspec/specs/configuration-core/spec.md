# configuration-core Specification

## Purpose
Configuration core gives MoonBit applications one layered, hierarchical
configuration: typed sources in a known order, format parsers into one value tree,
a deterministic merge, provenance for each value, safe secret handling, and pure
helpers to get, show, and explain the result.

## Requirements

### Requirement: Single value tree

The system SHALL parse each source into one Ion-based value tree before the merge.
The root of a source tree MUST be a struct. Field names MUST be text and MUST be
unique in each struct. The tree MUST keep the field order of its input. A tree
MUST NOT change after the system creates it.

#### Scenario: All formats give the same tree

- **WHEN** a TOML source, a YAML source, a JSON source, and an Ion source each hold `ir.layout` as the string `single-file` and `ir.strict_mode` as `true`
- **THEN** the system gives four equal value trees

#### Scenario: Root is not a struct

- **WHEN** a JSON source holds the array `[1, 2]` at its root
- **THEN** the system raises an invalid-root configuration error that names the source

#### Scenario: Field order stays

- **WHEN** a TOML source holds the keys `b`, `a`, `c` in that order
- **THEN** the struct in the value tree lists `b`, `a`, `c` in that order

### Requirement: Key paths

The system SHALL identify a value by a key path. A key path is a non-empty list of
non-empty field names. The text form joins names with `.`. A name that contains
`.` or `"` MUST use double quotes in the text form, with `\"` and `\\` as escapes.
Name matches MUST be exact and case-sensitive. Key paths do not select list items.

#### Scenario: Parse a dotted key

- **WHEN** the text `ir.strict_mode` is parsed as a key path
- **THEN** the key path holds the names `ir` and `strict_mode`

#### Scenario: Parse a quoted name

- **WHEN** the text `servers."eu.west".port` is parsed as a key path
- **THEN** the key path holds the names `servers`, `eu.west`, and `port`

#### Scenario: Reject an empty name

- **WHEN** the text `ir..layout` or the empty text is parsed as a key path
- **THEN** the system raises an invalid-key-path configuration error that holds the text

#### Scenario: Look up a missing key

- **WHEN** a configuration holds `project.name` and a caller looks up `project.missing`
- **THEN** the lookup gives no value and raises no error

### Requirement: Ordered typed sources

The system SHALL merge sources in the order that the application gives them. A
later source has higher precedence. Each source MUST have a kind (defaults,
in-memory, file with a file role, environment, or overrides), a display name, and
an integer display priority. The merge MUST NOT read the priority.

#### Scenario: Later source wins

- **WHEN** an application adds a defaults source with `ir.layout = "tree"` and then an in-memory source with `ir.layout = "single-file"`
- **THEN** the merged configuration holds `ir.layout = "single-file"`

#### Scenario: Same kind at two positions

- **WHEN** an application adds an in-memory source first and a second in-memory source last, and both set `a = 1` and `a = 2`
- **THEN** the merged configuration holds `a = 2`

### Requirement: Source priority

When the application gives no priority, the priority SHALL come from the kind and
file role: defaults 0, system 100, global 200, workspace, explicit, and legacy
files 300, member 350, environment file 375, local override 390, user override 400,
environment variables 600, and overrides 700. An in-memory source with no priority
MUST take the priority of the source before it, or 0 when it is first.

#### Scenario: Default priorities

- **WHEN** an application adds a defaults source, an explicit file source, an in-memory source, an environment source, and an overrides source, with no priorities
- **THEN** the source reports show the priorities 0, 300, 300, 600, and 700

#### Scenario: Override file priorities

- **WHEN** an application adds an environment file source, a local override file source, and a user override file source, with no priorities
- **THEN** the source reports show the priorities 375, 390, and 400

### Requirement: Source order check

The builder SHALL raise a source-order error when the priority of a source is lower
than the priority of the source before it. Equal priorities MUST be allowed.

#### Scenario: Decreasing priority

- **WHEN** an application adds an environment source and then a file source with the priority 300
- **THEN** the builder raises a source-order configuration error that names both sources and their priorities

### Requirement: Source selection

Each file source and each environment source SHALL have a selection: `Discover`,
`Explicit` with a value, or `Skip`. `Skip` MUST load nothing and MUST report the
status `skipped`. `Explicit` MUST use only the given value. `Discover` MUST use the
values that the host or the conventions supply.

#### Scenario: Skip a source

- **WHEN** an environment source has the selection `Skip` and the variable set of the builder holds `APP_IR__LAYOUT=tree`
- **THEN** the merged configuration does not hold `ir.layout` and the source report shows the status `skipped`

#### Scenario: Explicit environment variables

- **WHEN** an environment source has the selection `Explicit` with the variables `APP_A=1`, and the variable set of the builder holds `APP_B=2`
- **THEN** the merged configuration holds `a = 1` and does not hold `b`

### Requirement: Source providers

The builder SHALL accept a source provider at any position. During the load, the
system MUST call each provider with a load context that holds the file tree, the
platform when known, the variable set, the working directory, and the registered
formats. The provider MUST give either file requests or a list of sources, and
those sources MUST take the place of the provider in merge order.

#### Scenario: Provider sources take its position

- **WHEN** an application adds a defaults source, a provider that gives one file source with priority 300, and an environment source
- **THEN** the reports list the defaults source, the file source, and the environment source in that order

#### Scenario: Provider requests pass out of the load

- **WHEN** a provider needs the listing of `/w` and the tree is not complete and does not hold it
- **THEN** the pure load gives a file request for the listing of `/w` and no configuration

#### Scenario: Provider gets the platform

- **WHEN** the builder holds the platform Windows and a provider reads the load context
- **THEN** the provider gets the platform Windows

### Requirement: Defaults source

The system SHALL accept a defaults source from a value tree or from a value that
converts to JSON. A defaults source MUST be usable at any position in the list.

#### Scenario: Defaults from JSON

- **WHEN** an application adds defaults from the JSON object `{"ir": {"layout": "tree"}}` and no other source sets `ir.layout`
- **THEN** the merged configuration holds `ir.layout = "tree"` and its origin names the defaults source

### Requirement: In-memory source

The system SHALL accept an in-memory source from a value tree or from a list of
key-path and value pairs. The system MUST apply pairs in list order with the merge
rules. The system MUST NOT convert the type of a pair value. An in-memory source
MUST NOT need a filesystem.

#### Scenario: Flat key-path pairs

- **WHEN** an in-memory source holds the pairs `ir.layout => "single-file"` and `ir.strict_mode => true`
- **THEN** the merged configuration holds the struct `ir` with `layout = "single-file"` and `strict_mode = true`

#### Scenario: Later pair wins

- **WHEN** an in-memory source holds the pairs `a.b => 1` and then `a => "x"`
- **THEN** the merged configuration holds `a = "x"`

#### Scenario: String value keeps its type

- **WHEN** an in-memory source holds the pair `port => "8080"` with a string value
- **THEN** the merged configuration holds `port` as the string `8080`

#### Scenario: No filesystem

- **WHEN** a test builds a configuration from defaults and in-memory sources only, on the wasm target
- **THEN** the build gives the merged configuration and reads no file

### Requirement: File source at an explicit path

The system SHALL load a file source with the selection `Explicit(path)` from the
text that the file tree holds for that path. A relative path MUST join the working
directory of the builder when one is set. The file extension MUST select the
format from the formats that the application registers. A missing explicit file
MUST be an error.

#### Scenario: Extension selects the format

- **WHEN** an application registers the TOML and YAML formats and adds the explicit file `conf/app.yaml`
- **THEN** the system parses the file with the YAML format

#### Scenario: Missing explicit file

- **WHEN** an explicit file source names `conf/app.toml` and the complete file tree does not hold that path
- **THEN** the system raises a file-not-found configuration error that names `conf/app.toml`

#### Scenario: Unregistered extension

- **WHEN** an application registers only the TOML format and adds the explicit file `app.ion`
- **THEN** the system raises an unsupported-format configuration error that names `app.ion` and the registered extensions

#### Scenario: Relative path joins the working directory

- **WHEN** the working directory of the builder is `/w` and an explicit file source names `conf/app.toml`
- **THEN** the system reads `/w/conf/app.toml` and the source report shows that path

### Requirement: Candidate ambiguity

When a source has an explicit list of candidate files at one location and more
than one candidate exists, the system SHALL raise an ambiguity error that holds a
display name, the location, and every existing candidate. The message MUST be
`Ambiguous <display> configuration; found: <paths>`. The system MUST NOT merge the
candidates or choose one by path or extension. With no existing candidate, the
source MUST report `not-found`.

#### Scenario: Two candidates exist

- **WHEN** a source with the display name `App` has the candidates `/w/app.toml` and `/w/app.yaml` and both files exist
- **THEN** the system raises an ambiguity configuration error with the location `/w`, both candidates, and a message that starts with `Ambiguous App configuration; found:`

#### Scenario: One candidate exists

- **WHEN** a source has the candidates `app.toml` and `app.yaml` and only `app.yaml` exists
- **THEN** the system loads `app.yaml` and the source report lists both candidates with the status `loaded`

#### Scenario: No candidate exists

- **WHEN** no candidate of a source exists
- **THEN** the source adds no value and the source report shows the status `not-found`

### Requirement: Candidate existence

A candidate file SHALL exist only when the directory listing in the file tree holds
its exact name as a file. The compare MUST be case-sensitive on every platform.

#### Scenario: Name match is exact

- **WHEN** a source has the candidate `/w/app.toml` and the listing of `/w` holds only `App.toml`
- **THEN** the source reports `not-found`

### Requirement: Environment variable names

The environment source SHALL use only variables whose name starts with its prefix
and `_`, in any letter case. The system MUST ignore the `_` characters that follow
the prefix, split the rest at `__`, keep a single `_` in a name, and write each
name in lowercase. A name with an empty segment MUST be an error.

#### Scenario: Double underscore nests

- **WHEN** the prefix is `MORPHIR` and the variable `MORPHIR_CODEGEN__GO__PACKAGE=foo` exists
- **THEN** the configuration holds `codegen.go.package = "foo"`

#### Scenario: Single underscore stays

- **WHEN** the variable `MORPHIR_IR_FORMAT_VERSION=3` exists
- **THEN** the configuration holds the key `ir_format_version` with the integer `3`

#### Scenario: Leading underscores after the prefix

- **WHEN** the variable `MORPHIR__IR__STRICT_MODE=TRUE` exists
- **THEN** the configuration holds `ir.strict_mode = true`

#### Scenario: Prefix in any case

- **WHEN** the prefix is `MORPHIR` and the variable `morphir_ui__color=false` exists
- **THEN** the configuration holds `ui.color = false`

#### Scenario: Other variables stay out

- **WHEN** the variables `PATH=/bin` and `MORPHIRX_A=1` exist
- **THEN** the environment source adds no key

#### Scenario: Empty segment

- **WHEN** the variable `MORPHIR_A____B=1` exists
- **THEN** the system raises an invalid-environment-key configuration error that names `MORPHIR_A____B`

### Requirement: Reserved environment names

The environment source SHALL accept a list of reserved variable names. The system
MUST NOT turn a reserved variable into a configuration key. The name compare MUST
ignore letter case.

#### Scenario: Reserved helper variables

- **WHEN** the reserved names are `MORPHIR_HOME` and `MORPHIR_LOG_DIR`, and the variables `MORPHIR_HOME=/x`, `MORPHIR_LOG_DIR=/y`, and `MORPHIR_IR__LAYOUT=tree` exist
- **THEN** the configuration holds `ir.layout = "tree"` and does not hold `home` or `log_dir`

### Requirement: Environment value types

The system SHALL give an environment value a type: `true` or `false` in any case
becomes a Boolean; an optional sign and decimal digits that fit a 64-bit integer
become an integer; text that starts with `[` or `{` and parses as JSON becomes a
list or a struct; all other text stays a string.

#### Scenario: Typed values

- **WHEN** the variables `MORPHIR_IR__STRICT_MODE=TRUE`, `MORPHIR_IR__FORMAT_VERSION=+003`, `MORPHIR_CUSTOM__FLOAT=1.5`, and `MORPHIR_CUSTOM__QUOTED="text"` exist
- **THEN** the configuration holds `ir.strict_mode = true`, `ir.format_version = 3`, `custom.float` as the string `1.5`, and `custom.quoted` as the string `"text"` with its quotes

#### Scenario: JSON list value

- **WHEN** the variable `MORPHIR_WORKSPACE__MEMBERS=["a","b"]` exists
- **THEN** the configuration holds `workspace.members` as the list `["a", "b"]`

#### Scenario: Invalid JSON stays text

- **WHEN** the variable `MORPHIR_A=[not json` exists
- **THEN** the configuration holds `a` as the string `[not json`

#### Scenario: Integer out of range

- **WHEN** the variable `MORPHIR_A=99999999999999999999` exists
- **THEN** the configuration holds `a` as the string `99999999999999999999`

### Requirement: Shorter environment path wins

When two environment variables set a path and a path below it, the system SHALL
apply the deeper variable first and the shorter variable last, with the merge
rules. The result MUST NOT depend on the iteration order of the environment.

#### Scenario: Shorter struct merges over nested values

- **WHEN** the variables `MORPHIR_PROJECT__SOURCE_DIRECTORY=lib`, `MORPHIR_PROJECT__NAME=Overridden`, and `MORPHIR_PROJECT={"name":"Short"}` exist
- **THEN** the configuration holds `project.name = "Short"` and `project.source_directory = "lib"`

#### Scenario: Shorter scalar replaces nested values

- **WHEN** the variables `MORPHIR_IR=x` and `MORPHIR_IR__STRICT_MODE=true` exist, in any order
- **THEN** the configuration holds `ir = "x"` and does not hold `ir.strict_mode`

### Requirement: Overrides source

The system SHALL accept an overrides source from a value tree or from key-path and
value pairs. The overrides source MUST report the kind `overrides`. A CLI adapter
MUST be able to put it at the highest position.

#### Scenario: Overrides beat the environment

- **WHEN** the environment source sets `ir.layout = "tree"` and a later overrides source sets `ir.layout = "single-file"`
- **THEN** the merged configuration holds `ir.layout = "single-file"` and its origin has the kind `overrides`

### Requirement: Source subtree exclusion

A source SHALL accept a list of key paths to exclude and a `warn` flag. The system
MUST remove each excluded subtree from that source after the parse and before the
merge. Excluded values MUST NOT have provenance records. When `warn` is true, each
excluded key that existed in the source MUST add a key-removed warning with the key
path and the origin to the source report. When `warn` is false, the system MUST
NOT add a warning.

#### Scenario: Inherited layer drops project identity

- **WHEN** a file source excludes `project` and `workspace` with `warn` false, and the file holds `project.name = "A"` and `ir.layout = "tree"`
- **THEN** that source adds `ir.layout`, does not add `project.name`, and its report has no warning

#### Scenario: Member layer removal warns

- **WHEN** a member file source `/w/m/app.toml` excludes `workspace.out_dir` with `warn` true, and the file holds `workspace.out_dir = "out"`
- **THEN** the merged configuration does not hold that value from the member file, and its report holds one key-removed warning for `workspace.out_dir` with the origin `/w/m/app.toml`

#### Scenario: Absent key gives no warning

- **WHEN** a source excludes `workspace.out_dir` with `warn` true and does not hold that key
- **THEN** its report has no warning

### Requirement: TOML format

The TOML format SHALL map TOML types to the value tree: string to string, integer
to integer, float to float, Boolean to Boolean, array to list, table to struct,
offset date-time to a timestamp with its offset, local date-time to a timestamp
with an unknown offset, local date to a day-precision timestamp, and local time to
a string with the annotation `toml_local_time`.

#### Scenario: TOML date and time values

- **WHEN** a TOML file holds `a = 2026-09-28T12:30:00Z`, `b = 2026-09-28T12:30:00`, `c = 2026-09-28`, and `d = 12:30:00`
- **THEN** `a` is a timestamp with offset `+00:00`, `b` is a timestamp with an unknown offset, `c` is a timestamp with day precision, and `d` is the string `12:30:00` with the annotation `toml_local_time`

#### Scenario: Large TOML integer

- **WHEN** a TOML file holds `large = 9223372036854775807`
- **THEN** `large` is the exact integer `9223372036854775807`

### Requirement: YAML format

The YAML format SHALL accept one YAML document whose root is a mapping. It MUST
expand anchors and aliases, reject merge keys (`<<`), reject duplicate keys, reject
keys that are not strings, and map an empty document to an empty struct. Plain
scalars MUST resolve with the YAML 1.2 core schema.

#### Scenario: Core schema scalars

- **WHEN** a YAML file holds `a: true`, `b: 42`, `c: 1.5`, `d: yes`, `e: "42"`, and `f: 2026-09-28`
- **THEN** `a` is a Boolean, `b` is an integer, `c` is a float, `d` is the string `yes`, `e` is the string `42`, and `f` is the string `2026-09-28`

#### Scenario: More than one document

- **WHEN** a YAML file holds two documents
- **THEN** the system raises a parse configuration error that names the file and the line of the second document

#### Scenario: Duplicate key

- **WHEN** a YAML mapping holds the key `name` two times
- **THEN** the system raises a parse configuration error that names the file, the key, the line, and the column

#### Scenario: Merge key

- **WHEN** a YAML mapping holds the key `<<`
- **THEN** the system raises an unsupported-YAML configuration error that names the file and the line

### Requirement: YAML strict profile

The YAML format SHALL have an optional strict profile. The strict profile MUST
reject anchors, aliases, merge keys, tags that are not YAML core-schema tags,
duplicate keys, null values, more than one document, and a root that is not a
mapping. Each error MUST name the file, the line, and the column.

#### Scenario: Strict profile rejects an alias

- **WHEN** the strict profile reads a file that holds `a: &x 1` and `b: *x`
- **THEN** the system raises an unsupported-YAML configuration error that names the anchor feature, the file, the line, and the column

#### Scenario: Strict profile rejects null

- **WHEN** the strict profile reads a file that holds `a: ~`
- **THEN** the system raises an unsupported-YAML configuration error that names `a`

#### Scenario: Default profile accepts an alias

- **WHEN** the default profile reads a file that holds `a: &x 1` and `b: *x`
- **THEN** the value tree holds `a = 1` and `b = 1`

### Requirement: JSON and JSON5 formats

The system SHALL parse `.json` and `.json5` files with one JSON5 parser, so JSON
files can hold comments. An integral number with a magnitude of 2^53 or less MUST
become an integer. All other numbers MUST become floats.

#### Scenario: JSON with comments

- **WHEN** a file `app.json` holds `{ // comment` on its first line and `"ir": {"layout": "tree"} }` after it
- **THEN** the value tree holds `ir.layout = "tree"`

#### Scenario: JSON number types

- **WHEN** a JSON file holds `{"a": 3, "b": 1.5, "c": 1e3}`
- **THEN** `a` is the integer `3`, `b` is the float `1.5`, and `c` is the integer `1000`

#### Scenario: JSON syntax error has a position

- **WHEN** a JSON file holds an invalid character at line 2, column 5
- **THEN** the system raises a parse configuration error that names the file, line 2, and column 5

### Requirement: Ion format

The Ion format SHALL read Ion text that holds exactly one top-level struct. It MUST
keep decimals, timestamps, symbols, annotations, and integers of any size without
loss. A struct with a repeated field name MUST be an error.

#### Scenario: Ion keeps exact values

- **WHEN** an Ion file holds `{ price: 1.10, at: 2026-09-28T12:30Z, kind: 'fast', n: 123456789012345678901234567890 }`
- **THEN** `price` is the decimal `1.10`, `at` is the timestamp with minute precision, `kind` is the symbol `fast`, and `n` is the exact integer

#### Scenario: Ion repeated field

- **WHEN** an Ion file holds `{ a: 1, a: 2 }`
- **THEN** the system raises a duplicate-key configuration error that names the file and the key path `a`

#### Scenario: Ion with two top-level values

- **WHEN** an Ion file holds `{ a: 1 } { b: 2 }`
- **THEN** the system raises an invalid-root configuration error that names the file

### Requirement: Default merge rules

The system SHALL merge an overlay tree over a base tree with these default rules:
the overlay value wins; two structs merge recursively; a list in the overlay
replaces the base value; a scalar replaces a struct and a struct replaces a scalar;
the merge MUST NOT change its inputs.

#### Scenario: Structs merge and arrays replace

- **WHEN** the base holds `project.name = "Base"` and `project.exposed_modules = ["A", "B"]`, and the overlay holds `project.exposed_modules = ["C"]`
- **THEN** the result holds `project.name = "Base"` and `project.exposed_modules = ["C"]`

#### Scenario: Scalar replaces a struct

- **WHEN** the base holds `ir.layout = "tree"` and the overlay holds `ir = "x"`
- **THEN** the result holds `ir = "x"`

#### Scenario: Inputs do not change

- **WHEN** the system merges an overlay over a base
- **THEN** the base and the overlay are equal to their values before the merge

#### Scenario: New keys follow base keys

- **WHEN** the base struct holds the keys `a`, `b` and the overlay struct holds the keys `c`, `a`
- **THEN** the result struct lists the keys `a`, `b`, `c` in that order

### Requirement: Null overlay is ignored

A null value in an overlay struct SHALL NOT change the base value, at any depth.
The merged configuration MUST NOT hold a struct field whose value is null. This
differs from HOCON, where a null overlay replaces the value.

#### Scenario: Null does not unset

- **WHEN** the base holds `ir.layout = "tree"` and the overlay holds `ir.layout` as null
- **THEN** the result holds `ir.layout = "tree"` and its origin names the base source

#### Scenario: Null with no base value

- **WHEN** only one source holds `a = null`
- **THEN** the merged configuration does not hold `a`

### Requirement: Merge policy

A source or a key path SHALL be able to select a list merge policy: `Replace`
(default), `Append`, or `MergeByKey(name)`. A key-path policy MUST take precedence
over a source policy. `Append` MUST put the overlay items after the base items.
`MergeByKey` MUST merge items with equal key values and append the other overlay
items.

#### Scenario: Append lists

- **WHEN** the policy for `plugins` is `Append`, the base holds `plugins = ["a"]`, and the overlay holds `plugins = ["b"]`
- **THEN** the result holds `plugins = ["a", "b"]`

#### Scenario: Merge by key

- **WHEN** the policy for `servers` is `MergeByKey("name")`, the base holds `[{name = "a", port = 1}, {name = "b", port = 2}]`, and the overlay holds `[{name = "b", port = 3}, {name = "c", port = 4}]`
- **THEN** the result holds `[{name = "a", port = 1}, {name = "b", port = 3}, {name = "c", port = 4}]`

#### Scenario: Merge-by-key item without the key

- **WHEN** the policy for `servers` is `MergeByKey("name")` and an overlay item has no `name` field
- **THEN** the system raises a merge-key configuration error that names `servers`, the item index, and the source

#### Scenario: Key path policy beats source policy

- **WHEN** a source has the policy `Append` and the key path `plugins` has the policy `Replace`
- **THEN** that source replaces `plugins` and appends to other lists

### Requirement: Secret references are leaves

The system SHALL treat a struct with exactly one field named `env`, `file`,
`command`, or `keyring` as a secret reference, unless the application turns the
recognition off. The merge MUST NOT merge a secret reference with a struct. An
overlay value MUST replace a secret reference, and a secret reference MUST replace
a base value.

#### Scenario: Two secret references do not merge

- **WHEN** the base holds `credentials.key = {env = "FIRST"}` and the overlay holds `credentials.key = {file = "secret"}`
- **THEN** the result holds `credentials.key = {file = "secret"}` and does not hold `credentials.key.env`

#### Scenario: Invalid reference payload

- **WHEN** a source holds `registry.token = {command = 5}`
- **THEN** the system raises an invalid-secret configuration error that names `registry.token` and the source

### Requirement: Lazy secret resolution

The system SHALL resolve a secret only when a caller asks for one key, through a
resolver that the host supplies. Load, get, show, path, and explain MUST NOT
resolve a secret. A resolved secret MUST display as `<redacted>`. A resolution
error MUST name its class and MUST NOT hold the secret or the backend output.

#### Scenario: Load does not resolve

- **WHEN** a configuration holds a secret reference and the system loads, shows, and explains it
- **THEN** the system does not call the resolver

#### Scenario: Resolve an environment reference

- **WHEN** a configuration holds `registry.token = {env = "TOKEN"}` and the caller resolves `registry.token` with an environment resolver over `TOKEN=abc`
- **THEN** the caller gets a secret that exposes `abc` and displays as `<redacted>`

#### Scenario: Plain string is a literal secret

- **WHEN** a configuration holds `registry.token = "abc"` and the caller resolves `registry.token`
- **THEN** the caller gets a secret that exposes `abc` and the system does not call the resolver

#### Scenario: Resolution failure classes

- **WHEN** a resolution fails because the key is missing, the variable is empty, the file cannot be read, the value is not valid, the command fails, or the keyring lookup fails
- **THEN** the error class is `missing-config-key`, `empty-environment`, `file-read`, `invalid-secret-value`, `command-failed`, or `keyring-lookup-failed`, and the message does not hold the secret

#### Scenario: Resolver gets the origin

- **WHEN** a file source `/w/app.toml` holds `token = {file = "s.txt"}` and the caller resolves `token`
- **THEN** the resolver receives the reference and the origin path `/w/app.toml`, so it can anchor `s.txt` to `/w`

### Requirement: Leaf provenance

The system SHALL record a non-empty list of origins for each winning leaf. A list
and a secret reference MUST each count as one leaf. A replaced leaf or list MUST
have one origin. An appended or merged-by-key list MUST have every contributing
origin in merge order. An origin MUST hold the source kind, the
source name, and the file path or the variable name when one exists. When a value
replaces a struct, the system MUST remove the records below that struct.

#### Scenario: Winning origins

- **WHEN** the source `base` sets `project.name` and `project.exposed_modules`, and the later source `user` sets only `project.exposed_modules`
- **THEN** the origin of `project.name` names `base` and the origin of `project.exposed_modules` names `user`

#### Scenario: Stale records go

- **WHEN** the base sets `ir.layout` and `ir.mode`, and the overlay sets `ir = "x"`
- **THEN** the provenance holds `ir` from the overlay and holds no record for `ir.layout` or `ir.mode`

#### Scenario: Environment origin names the variable

- **WHEN** `MORPHIR_IR__LAYOUT=tree` sets `ir.layout`
- **THEN** the origin of `ir.layout` has the kind `environment` and the variable name `MORPHIR_IR__LAYOUT`

#### Scenario: Appended list has all contributors

- **WHEN** the policy for `plugins` is `Append` and the sources `a` and `b` each add items
- **THEN** the origins of `plugins` list `a` and then `b`

### Requirement: Source report

The system SHALL give one report for each source, in merge order. Each report MUST
hold the kind, the name, the priority, the file path when one exists, the
candidate paths, the status `loaded`, `not-found`, or `skipped`, and the warnings.

#### Scenario: Report order and status

- **WHEN** an application adds defaults, an explicit file that exists, an environment source with `Skip`, and a file source with no existing candidate
- **THEN** the reports are in that order with the statuses `loaded`, `loaded`, `skipped`, and `not-found`

### Requirement: Report kind names

Reports SHALL show Morphir kind names: `defaults`, `system`, `global`, `project`
(for workspace, explicit, and legacy files), `workspace-member`,
`environment-file`, `user-override`, and `environment`. A local override file MUST
show `local-override`. In-memory and overrides sources MUST show `in-memory` and
`overrides`.

#### Scenario: File role names

- **WHEN** the sources are a member primary file, a local override file, and a user override file
- **THEN** their reports show the kind names `workspace-member`, `local-override`, and `user-override`

### Requirement: Display redaction

Before the system displays a value, it SHALL replace the whole value under each
sensitive key with the text `<redacted>`. A key is sensitive when its name, in
lowercase with `-` changed to `_`, contains `token`, `password`, `passwd`,
`secret`, `credential`, `api_key`, `apikey`, `private_key`, or `access_key`.

#### Scenario: Redact nested keys

- **WHEN** the configuration holds `registry.password = "hunter2"`, `registry.username = "alice"`, and `toolchain.elm.env.NPM_TOKEN = "x"`
- **THEN** the display shows `registry.password` and `toolchain.elm.env.NPM_TOKEN` as `<redacted>` and shows `registry.username` as `alice`

#### Scenario: Key name shapes

- **WHEN** the keys are `apiKey`, `client-secret`, `aws_access_key_id`, `credentials`, and `tokenizer_mode`
- **THEN** the system redacts all five values

#### Scenario: Safe key names

- **WHEN** the keys are `username`, `authors`, `key_bindings`, and `entry_point`
- **THEN** the system does not redact these values

#### Scenario: Redaction does not change the configuration

- **WHEN** the system redacts a configuration for display
- **THEN** the configuration keeps its values

### Requirement: Get helper

The get helper SHALL redact the configuration and then look up a key path. A
string value MUST render as its text. Other values MUST render as JSON. The JSON
form MUST be an object with the fields `key` and `value`. A missing key MUST raise
a key-not-found error with the message `Configuration key not found: <key>`.

#### Scenario: Get a string

- **WHEN** the configuration holds `project.name = "acceptance-project"` and the caller gets `project.name`
- **THEN** the text output is exactly `acceptance-project`

#### Scenario: Get as JSON

- **WHEN** the configuration holds `ir.format_version = 4` and the caller gets `ir.format_version` as JSON
- **THEN** the output is a JSON object with `key` equal to `ir.format_version` and `value` equal to `4`

#### Scenario: Get a sensitive key

- **WHEN** the configuration holds `registry.token = "top-secret-token"` and the caller gets `registry.token`
- **THEN** the output holds `<redacted>` and does not hold `top-secret-token`

#### Scenario: Get a missing key

- **WHEN** the caller gets `project.missing`
- **THEN** the system raises a key-not-found configuration error with the message `Configuration key not found: project.missing`

### Requirement: Show helper

The show helper SHALL render the redacted configuration as TOML, JSON, or Ion
text. A value that the selected format cannot hold MUST raise a render error that
names its key path.

#### Scenario: Show as JSON

- **WHEN** the configuration holds `registry.token = "top-secret-token"` and `registry.endpoint = "https://registry.example.test"`, and the caller shows it as JSON
- **THEN** the output holds `<redacted>` and `https://registry.example.test` and does not hold `top-secret-token`

#### Scenario: Show as TOML

- **WHEN** the configuration holds `ir.format_version = 3` and the caller shows it as TOML
- **THEN** the output is valid TOML that holds `format_version = 3` in the table `ir`

#### Scenario: Null in a list cannot render as TOML

- **WHEN** the configuration holds `a = [1, null]` and the caller shows it as TOML
- **THEN** the system raises a render configuration error that names `a`

### Requirement: Path helper

The path helper SHALL render the source reports as text or as JSON. The text form
MUST start with `Configuration sources (in priority order):` and list the highest
priority first. The JSON form MUST list the sources in ascending priority.

#### Scenario: Path as text

- **WHEN** a defaults source and a loaded project file source exist and the caller renders the path text
- **THEN** the text lists the project source before the defaults source, with a `[✓]` mark, the path, `Status: loaded`, and the priority for each

#### Scenario: Path as JSON

- **WHEN** the caller renders the path JSON
- **THEN** the JSON lists each source with its kind, name, priority, path, candidates, and status, in ascending priority

### Requirement: Explain helper

The explain helper SHALL give the origins of a key path. For a leaf it MUST give
the origins of that leaf. For a struct it MUST give each descendant leaf path with
its origins. A missing key MUST raise a key-not-found error.

#### Scenario: Explain a leaf

- **WHEN** the environment set `ir.format_version` over a file value and the caller explains `ir.format_version`
- **THEN** the result names the environment source and the variable `MORPHIR_IR__FORMAT_VERSION`

#### Scenario: Explain a struct

- **WHEN** the caller explains `project` and two sources set `project.name` and `project.version`
- **THEN** the result lists `project.name` and `project.version`, each with its own origin

### Requirement: Typed configuration errors

The system SHALL raise one typed configuration error with a separate case for each
failure class. The same error type MUST hold the cases that the conventions and
binding capabilities raise: outside-boundary, invalid-environment-name,
unknown-project, ambiguous-project, decode with one bind failure, and validation
with a list of bind failures. Each case MUST hold the source name or path and,
when the parser gives them, the line and column. Each case MUST give a message for
people.

#### Scenario: Parse error with origin

- **WHEN** the file `/w/app.toml` holds the invalid text `a = `
- **THEN** the system raises a parse configuration error whose format is TOML, whose origin is `/w/app.toml`, and whose message names the file

#### Scenario: Match an error by case

- **WHEN** a caller catches a configuration error from an ambiguous location
- **THEN** the caller can match the ambiguity case and read the candidate paths without a string compare

#### Scenario: Binding failure is a configuration error

- **WHEN** a binding decode fails at `targets[1].level`
- **THEN** the caller catches a configuration error, matches the decode case, and reads a bind failure whose decode path renders as `targets[1].level`

### Requirement: Pure core with explicit inputs

The system SHALL load a configuration from explicit inputs only: the builder with
its sources, formats, variable set, and working directory, and a file tree. The
load MUST give the same result for the same inputs on the wasm, wasm-gc, js, and
native targets. The core MUST NOT read files, the process environment, or the
process working directory. Host adapters do that.

#### Scenario: Same result on all targets

- **WHEN** the same builder and file tree are loaded on wasm, wasm-gc, js, and native
- **THEN** each target gives equal merged values, provenance, and source reports

### Requirement: File tree load protocol

The file tree SHALL hold directory listings, file text, and a `complete` flag. The
pure load MUST give either a list of file requests (directory listings and files
that the tree does not hold) or the configuration. With a complete tree, the pure load MUST NOT give file requests and MUST treat a path that the tree
does not hold as absent.

#### Scenario: Incomplete tree asks for files

- **WHEN** an explicit file source names `/w/app.toml` and the tree is not complete and does not hold that path
- **THEN** the pure load gives a file request for `/w/app.toml` and no configuration

#### Scenario: Complete tree never asks

- **WHEN** the tree is complete and does not hold a candidate directory
- **THEN** the pure load gives the configuration and treats the directory as absent

#### Scenario: Host adapter fills the inputs

- **WHEN** a native or js application uses the host adapter with an explicit file and a `Discover` environment source, and the builder holds no variable set and no working directory
- **THEN** the adapter reads that file, the process environment, and the process working directory, and the configuration holds the values from both sources

#### Scenario: Discover environment with no host

- **WHEN** a wasm application loads an environment source with `Discover` and gives no variable set
- **THEN** the source adds no key and reports `not-found`

### Requirement: Host adapter uses the given run values

When the builder holds a variable set, the host adapter SHALL use only that set and
MUST NOT read the process environment. When the builder holds a working directory,
the host adapter SHALL use only that directory and MUST NOT read the process
working directory.

#### Scenario: Adapter uses the given values

- **WHEN** a native application uses the host adapter with a `Discover` environment source with the prefix `APP`, the builder holds the variable set `APP_A=1` and the working directory `/w`, and the process environment holds `APP_B=2`
- **THEN** the configuration holds `a = 1` and does not hold `b`, and a relative explicit file joins `/w`

### Requirement: File tree absence records

The file tree SHALL record a path as missing on request. A missing directory MUST
make every path under it missing. The pure load MUST NOT ask for a held path or a
missing path.

#### Scenario: Absence record answers a request

- **WHEN** the tree is not complete, an explicit file source names `/w/app.toml`, and the tree records `/w/app.toml` as missing with `with_missing`
- **THEN** the pure load gives no file request for `/w/app.toml` and raises the file-not-found error for the explicit file

#### Scenario: Missing directory answers its children

- **WHEN** the tree is not complete and records the directory `/w/.config` as missing
- **THEN** the pure load gives no request for `/w/.config` or for any path under it

### Requirement: Paths use forward slashes

The system SHALL show every path in file trees, reports, origins, and error
messages with `/` separators on every platform. On Windows the host adapter MUST
convert `\` to `/` when it reads paths and MUST convert back only for file-system
calls.

#### Scenario: Windows path in a report

- **WHEN** the native host adapter on Windows loads the explicit file `app.toml` and Windows gives the working directory of drive `C:`, directory `w` with backslash separators
- **THEN** the source report and the origins show the path `C:/w/app.toml`

### Requirement: Format registry

The builder SHALL hold the formats that the application registers, in registration
order, and SHALL give them to other packages. A caller MUST be able to parse a
file text with the registered formats, with the format selected by the file
extension.

#### Scenario: Registered formats are visible

- **WHEN** an application registers the TOML format and then the YAML format
- **THEN** the builder gives the TOML format and then the YAML format, with the extensions `toml`, `yaml`, and `yml`

#### Scenario: Parse with the registry

- **WHEN** a caller parses the text of `/w/app.yaml` with the registered formats
- **THEN** the system parses it with the YAML format and gives a value tree

### Requirement: Linked format set

The package `moonrockz/moon-lander-config/formats` SHALL be a virtual package with a
default implementation. Its function `formats()` MUST give the formats that the
program links. The default implementation MUST give the TOML, YAML, JSON5 and Ion
formats in that order. The JSON5 format MUST cover `.json` and `.json5`. The
configuration core package `moonrockz/moon-lander-config` MUST NOT import `formats`.

#### Scenario: Default linked formats

- **WHEN** an application does not override `formats`
- **THEN** `formats()` gives the TOML, YAML, JSON5 and Ion formats, with the extensions `toml`, `yaml`, `yml`, `json`, `json5` and `ion`

### Requirement: Trim formats with one line

The package `moonrockz/moon-lander-config/formats/toml` SHALL implement `formats` with the
TOML format only. An application MUST be able to select it with one `overrides`
entry in its main `moon.pkg` and no code change. The program MUST then link no
parser of the other formats. An application MUST be able to select its own
implementation package in the same way.

#### Scenario: Trim to TOML with one line

- **WHEN** the main `moon.pkg` of an application has `overrides: [ "moonrockz/moon-lander-config/formats/toml" ]`
- **THEN** `formats()` gives only the TOML format, and the application source has no change

#### Scenario: Unused parsers are not linked

- **WHEN** a default application and a trimmed application build on wasm, wasm-gc, js and native
- **THEN** each trimmed output is smaller than the default output of its target and holds no marker string of the YAML, JSON5 or Ion parser

#### Scenario: Own format mix

- **WHEN** an application writes an implementation package of `formats` that gives TOML and YAML, and selects it with `overrides`
- **THEN** `formats()` gives the TOML and YAML formats only

### Requirement: Host listings record inaccessible entries

A directory listing SHALL record each entry that the host lists but cannot inspect as
`Inaccessible`. The native and js host adapters MUST NOT raise an error for such an
entry when they answer a listing request. An entry that does not exist when the adapter
inspects it SHALL NOT be in the listing. An error for the listed directory itself, or
for a requested file, SHALL pass out of the load.

#### Scenario: Locked entry next to a configuration file

- **WHEN** a directory holds `acme.toml` and an entry whose inspection fails with a Windows sharing violation, and the adapter answers the listing
- **THEN** the listing holds `acme.toml` as a file and the other entry as `Inaccessible`, and the load reads `acme.toml`

#### Scenario: Entry that disappears

- **WHEN** an entry is in the directory listing and does not exist when the adapter inspects it, or is a link that points nowhere
- **THEN** the listing does not hold the entry and the adapter raises no error

### Requirement: An inaccessible entry can be a file

When the tree does not hold the text of an `Inaccessible` entry with the exact name,
`FileTree::is_file` SHALL give `Unknown`, and `FileTree::file_request` SHALL give the
file request for it. So the load asks the host for that file before it counts the
candidates, and the error of the host passes out of the load. When the tree holds the
text, or the tree is complete, the entry SHALL be a file.

#### Scenario: Inaccessible entry next to a candidate

- **WHEN** the tree is not complete, the listing of `/w` holds `acme.toml` as a file and `acme.yaml` as `Inaccessible`, and both are candidates
- **THEN** the load asks for the file `/w/acme.yaml` and does not raise an ambiguity error before the host answers

#### Scenario: Inaccessible candidate file

- **WHEN** the tree is not complete, a candidate source names `/w/acme.toml`, and the listing of `/w` holds `acme.toml` as `Inaccessible`
- **THEN** the load asks for the file `/w/acme.toml`, and the error of the host for it passes out of the load

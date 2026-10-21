# Tasks: add-configuration-binding

Epic: lander-4us.4

This change starts after `add-configuration-core` supplies `Config`, `ConfigValue`,
`KeyPath`, `Origin`, `FileRole`, `SecretRef`, the merge function, and `ConfigError`
with the `Decode` and `Validation` cases and `BindFailure` (with `DecodePath`,
`DecodeStep`, `Located` and `Blame`) in `moonrockz/moon-lander/config`. Tests use in-memory sources only. Run each test on
`wasm`, `wasm-gc`, `js` and `native` through `mise run test`.

## 1. Tracer bullet: bind one section with a source-aware error

Bead: lander-4us.4.1

- [ ] 1.1 Check that the core declares `ConfigError::Decode(failure~ : BindFailure)`, `ConfigError::Validation(failures~ : Array[BindFailure])`, `BindFailure`, `Located`, `DecodePath`, `DecodeStep` and `Blame` (`Set(Array[Origin])`, `Table`, `Default`, `Unset`) as in design D4; verify `moon info` shows them in `pkg.generated.mbti`, and stop and return to the owner if they differ
- [ ] 1.2 Add `bind` and `Config::bind` for `T : FromJson`: parse the key with `KeyPath::parse`, select the section, convert it to `Json`, decode with `@json.from_json`; verify a white-box test binds `ir` from an in-memory source into a derived record, and empty key text raises `InvalidKeyPath`
- [ ] 1.3 Add `bind_root` for `T : FromJson`; verify a test binds a record with the fields `ir` and `pipeline` and a root error names `ir.strict_mode`
- [ ] 1.4 Translate the `JsonPath` text (RFC 6901 pointer, `~0`, `~1`, list indexes) into a `DecodePath` (key path up to the first list index, then the index and field suffix), and use the core `DecodePath` text form (`targets[1].level`, quoted names, `(root)`) to show it; verify unit tests for keys with `/`, `~`, `.`, and a list index
- [ ] 1.5 Resolve blame from provenance at the key part of the `DecodePath` (`Set` with every list origin, then `Table` origins, then `Unset`); verify tests for a leaf, an element of a replaced list, an element of an appended list with two origins, a table with two sources, and an unset key
- [ ] 1.6 Decode an absent section as `null`; verify an `Option` target gives `None` and a record target gives `Decode` with blame `Unset`
- [ ] 1.7 Raise `Decode` with the values that the core `ConfigError::message()` renders as `<path>: <detail> (<blame text>)` with the core origin text (file role name and path, or variable name); verify snapshot tests over the core text for a `user-override` file origin, an environment origin, a list with two origins, `Unset`, and a Windows origin `C:/repo/morphir.toml` with no backslash
- [ ] 1.8 Add an acceptance suite in `tests/` for the spec requirements "Bind a section to a typed value", "Bind the full configuration", "Absent section", "Decode errors name the decode path and its sources" and "Origin text in errors"; verify `mise run test` passes on all four targets
- [ ] 1.9 Document `bind` and `bind_root` with a runnable example in the `config` package README; verify the README example runs in `mise run test`

## 2. Bind over a default value

Bead: lander-4us.4.2

- [ ] 2.1 Add `bind_or` for `T : FromJson + ToJson`: write the default with `ToJson`, wrap the default and the section as the field of two synthetic root structs, merge them with the core merge, take the field out, decode; verify tests for unset keys, a replaced list, a scalar default, a list default, a `null` overlay and an absent section
- [ ] 2.2 Mark leaves that the default supplies with blame `Default`; verify a bad default gives `Decode` text that says `from the bind default`
- [ ] 2.3 Add acceptance scenarios for "Bind over a default value" and "Decode errors for tables, unset and default values"; verify they pass on all four targets
- [ ] 2.4 Document `bind_or`, and the observed `FromJson` limits (`Int` truncation, `Int64` text only, `null` in an `Option` field), in the package README; verify the README examples run

## 3. Secret guard and safe error text

Bead: lander-4us.4.3

- [ ] 3.1 Detect a secret reference leaf on the decode path of `bind` and `bind_or` and raise `Decode` with the secret-reference detail; verify a test with an environment resolver stub that fails if the system calls it
- [ ] 3.2 Add a test that the text of each binding error does not contain the configured value; verify it with a value such as `42` at `service.api_token`
- [ ] 3.3 Add acceptance scenarios for "Error text does not show configured values" and the first scenario of "Secret references are not resolved by binding"; verify they pass

## 4. Validation and options values

Bead: lander-4us.4.4

- [ ] 4.1 Add `Violation` (relative `DecodeStep` paths), `violation`, `nested`, and the `Validate` trait with an empty default; add impls for `Map[String, T]` (adds `Field`), `Array[T]` (adds `Index`) and `T?`; verify unit tests for path prefixes
- [ ] 4.2 Add `validated`, which turns each violation into a core `BindFailure` with full decode paths and blames and raises the core `ConfigError::Validation`; verify a test with two failures, a cross-field failure and a failure inside a list
- [ ] 4.3 Add `Options[T]` and `options`; verify that no options value exists after a validation failure
- [ ] 4.4 Add acceptance scenarios for "Validation reports all failures with sources" and "Options value"; verify they pass on all four targets
- [ ] 4.5 Document `Validate`, `validated` and `options` with a pipeline example in the package README; verify the example runs

## 5. Named options

Bead: lander-4us.4.5

- [ ] 5.1 Add `NamedOptions[T]` and `named`, which calls the given binder for each child key and collects all `Decode` and `Validation` failures in one error; verify tests with two failing instances and an absent section
- [ ] 5.2 Add acceptance scenarios for "Named options"; verify they pass
- [ ] 5.3 Document `named` with `bind_or` as the binder in the package README; verify the example runs

## 6. Exact decoding with FromConfig

Bead: lander-4us.4.6

- [ ] 6.1 Add `ConfigNode` (decode path, value, blame, `child`, `children`, `items`, `get`, `json`, `fail`) and the `FromConfig` trait, and `bind_with`; verify a white-box test binds a hand-written `FromConfig` record
- [ ] 6.2 Add `FromConfig` impls for `String`, `Bool`, `Int`, `Int64`, `UInt64`, `Double`, `BigInt`, `@ion.Decimal`, `@ion.Timestamp`, `T?`, `Array[T]` and `Map[String, T]`; verify `Int` rejects `80.5` and `Int64` keeps `9007199254740993`
- [ ] 6.3 Add `Sourced[T]` and `FromConfig for SecretRef`; verify a relative path keeps its file origin and a secret stays unresolved
- [ ] 6.4 Make `ConfigNode::json` use the same error translation as `bind`; verify a `FromJson` part inside a `FromConfig` record reports the full decode path
- [ ] 6.5 Add acceptance scenarios for "Exact decoding from the value tree", "Value with its origin" and the second scenario of "Secret references are not resolved by binding", with Ion text sources; verify they pass on all four targets
- [ ] 6.6 Document `FromConfig`, `bind_with` and `Sourced` in the package README; verify the example runs

## 7. Unknown-key check

Bead: lander-4us.4.7

- [ ] 7.1 Add `UnknownKeys` (`Allow`, `Reject`, `RejectExcept`) and the `unknown?` argument of `bind_or`; compare configured keys with the `ToJson` form of the result plus the listed keys; verify tests for a misspelled key, a `None` field, a map field and a hand-written alias with `RejectExcept`
- [ ] 7.2 Add acceptance scenarios for "Optional unknown-key check"; verify they pass
- [ ] 7.3 Document the check in the package README, including that `Reject` needs a `ToJson` that writes every key `FromJson` accepts; verify the README example runs

## 8. Integration check

Bead: lander-4us.4.8

- [ ] 8.1 Add one acceptance test that binds the same in-memory Morphir-shaped configuration (`ir`, `pipeline`, `workspace`, `metadata`) on all four targets and compares bound values and error text; verify it passes ("Binding is pure")
- [ ] 8.2 Run `mise run format` and `mise run check`; verify both pass, and verify the windows-latest CI leg passes the binding tests for `native` and `js`
- [ ] 8.3 Run `mise exec -- openspec validate add-configuration-binding --strict`; verify it passes

# JSON and JSON5 configuration

The `config/formats/json5` package (`@json5`) parses `.json` and `.json5` files
with one JSON5 parser, so JSON files can hold comments. Import
`moonrockz/moon-lander/config/formats/json5` as `@json5`. Each `mbt check` block
on this page runs as a test with `mise run test`.

```mbt check
///|
test "parse JSON5 with a comment" {
  let text =
    #|{ // layout
    #|  "ir": { "layout": "tree" }
    #|}
  let value = @json5.parse(text, origin="app.json")
  @expect.expect(@config.get_text(
    @config.build([@config.in_memory(value)]),
    "ir.layout",
  )).to_equal("tree")
}
```

## Number precision

`moonbitlang/x/json5` gives every number as a `Double`, with no source text.
An integral number whose magnitude is at most 2^53 (9_007_199_254_740_992)
becomes an Ion integer. Every other number, including `Infinity` and `NaN`,
becomes a float. Integers above 2^53 lose precision with no error. Prefer TOML
or Ion, or a string, when a value must stay exact beyond that range.

```mbt check
///|
test "safe integers stay exact; larger magnitudes become floats" {
  let safe = @json5.parse(
    "{\"n\": 9007199254740992}",
    origin="app.json",
  )
  guard safe.to_ion().kind() is Struct(fields) else { fail("expected object") }
  guard fields[0].value().kind() is Int(_) else {
    fail("2^53 should stay an integer")
  }
  // Magnitudes above 2^53 cannot be exact in Double; 1e20 is still integral as
  // a Double but becomes a float under the configuration number rule.
  let large = @json5.parse("{\"n\": 1e20}", origin="app.json")
  guard large.to_ion().kind() is Struct(fields) else { fail("expected object") }
  guard fields[0].value().kind() is Float(_) else {
    fail("above 2^53 should become a float")
  }
}
```

## Duplicate keys

The JSON5 parser keeps no duplicate-key information: when a key occurs more
than once in one object, the last value wins. TOML, YAML, and Ion report
duplicate keys as configuration errors. Do not rely on duplicate detection for
JSON or JSON5 sources.

```mbt check
///|
test "duplicate JSON keys keep the last value" {
  let value = @json5.parse("{\"a\": 1, \"a\": 2}", origin="app.json")
  @expect.expect(value).to_equal(
    @config.fields([("a", @config.int(2))]),
  )
}
```

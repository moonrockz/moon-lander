///|
fn versioned(version : String, body : String) -> @openrpc.Document {
  @openrpc.read(
    "{\"openrpc\":\"" +
    version +
    "\",\"info\":{\"title\":\"API\",\"version\":\"1\"}," +
    body +
    "}",
  )
  .document()
  .unwrap()
}

///|
fn normative(
  report : @openrpc.ValidationReport,
) -> Array[(@exact.Code, @openrpc.Severity, Array[String])] {
  report
  .findings()
  .filter(f => f.phase() == @openrpc.Normative)
  .map(f => (f.diagnostic().code(), f.severity(), f.location().path()))
}

///|
test "resolved method names are unique" {
  let inline = @openrpc.validate(
    versioned(
      "1.4.0",
      "\"methods\":[{\"name\":\"a\",\"params\":[]},{\"name\":\"a\",\"params\":[]}]",
    ),
  )
  assert_eq(normative(inline), [
    (@exact.DuplicateName, @openrpc.Error, ["methods", "1", "name"]),
  ])
  assert_eq(inline.normative(), @openrpc.Failed)
  let referenced = @openrpc.validate(
    versioned(
      "1.4.0",
      "\"methods\":[{\"$ref\":\"#/x-m\"},{\"$ref\":\"#/x-m\"}],\"x-m\":{\"name\":\"a\",\"params\":[]}",
    ),
  )
  let duplicate = referenced
    .findings()
    .filter(f => f.diagnostic().code() == @exact.DuplicateName)
  assert_eq(duplicate.length(), 1)
  assert_eq(duplicate[0].location().path(), ["x-m", "name"])
  assert_eq(duplicate[0].chain().map(c => c.path()), [["methods", "1", "$ref"]])
}

///|
test "parameter names and error codes are unique per method" {
  let report = @openrpc.validate(
    versioned(
      "1.3.2",
      "\"methods\":[{\"name\":\"a\",\"params\":[{\"name\":\"p\",\"schema\":true},{\"name\":\"p\",\"schema\":true}],\"errors\":[{\"code\":1,\"message\":\"x\"},{\"code\":1e0,\"message\":\"y\"},{\"code\":9007199254740992,\"message\":\"z\"},{\"code\":9007199254740993,\"message\":\"w\"}]}]",
    ),
  )
  assert_eq(normative(report), [
    (@exact.DuplicateErrorCode, @openrpc.Error, [
      "methods", "0", "errors", "1", "code",
    ]),
    (@exact.DuplicateName, @openrpc.Error, ["methods", "0", "params", "1", "name"]),
  ])
  let codes = report
    .findings()
    .filter(f => f.diagnostic().code() == @exact.DuplicateErrorCode)
  assert_eq(codes[0].related().map(r => r.path()), [
    ["methods", "0", "errors", "0", "code"],
  ])
}

///|
test "links name existing resolved methods" {
  let report = @openrpc.validate(
    versioned(
      "1.4.0",
      "\"methods\":[{\"name\":\"a\",\"params\":[],\"links\":[{\"name\":\"ok\",\"method\":\"a\"},{\"name\":\"bad\",\"method\":\"missing\"}]}],\"components\":{\"links\":{\"L\":{\"name\":\"l\",\"method\":\"nope\"}}}",
    ),
  )
  assert_eq(normative(report), [
    (@exact.UnknownMethod, @openrpc.Error, ["components", "links", "L", "method"]),
    (@exact.UnknownMethod, @openrpc.Error, [
      "methods", "0", "links", "1", "method",
    ]),
  ])
}

///|
let unnamed : String = "\"servers\":[{\"url\":\"https://a.test\"}],\"methods\":[{\"name\":\"a\",\"params\":[],\"links\":[{\"method\":\"a\",\"server\":{\"url\":\"https://b.test\"}}]}]"

///|
test "1.3.2 requires server, license and link names; 1.4 does not" {
  let body = unnamed.replace(
    old="\"servers\"",
    new="\"x-l\":0,\"servers\"",
  )
  let source = "{\"openrpc\":\"1.3.2\",\"info\":{\"title\":\"API\",\"version\":\"1\",\"license\":{}}," +
    body +
    "}"
  let document = @openrpc.read(source).document().unwrap()
  let report = @openrpc.validate(document)
  assert_eq(normative(report), [
    (@exact.MissingField, @openrpc.Error, ["info", "license"]),
    (@exact.MissingField, @openrpc.Error, ["methods", "0", "links", "0"]),
    (@exact.MissingField, @openrpc.Error, [
      "methods", "0", "links", "0", "server",
    ]),
    (@exact.MissingField, @openrpc.Error, ["servers", "0"]),
  ])
  let missing = report.findings().filter(f => f.phase() == @openrpc.Normative)
  assert_true(missing.all(f => f.expected_field() == Some("name")))
  assert_eq(missing.map(f => f.discrepancy()), [
    Some(@openrpc.LicenseNameOmitted),
    None,
    Some(@openrpc.ServerNameOmitted),
    Some(@openrpc.ServerNameOmitted),
  ])
  let modern = @openrpc.read(source.replace(old="1.3.2", new="1.4.0"))
    .document()
    .unwrap()
  assert_eq(normative(@openrpc.validate(modern)), [])
}

///|
test "compatibility downgrades only the listed discrepancies" {
  assert_eq(@openrpc.compatibility_discrepancies(), [
    @openrpc.OptionalParameterBeforeRequired,
    @openrpc.ServerNameOmitted,
    @openrpc.LicenseNameOmitted,
  ])
  let document = versioned(
    "1.3.2",
    unnamed.replace(
      old="\"params\":[]",
      new="\"params\":[{\"name\":\"o\",\"schema\":true},{\"name\":\"r\",\"required\":true,\"schema\":true}],\"errors\":[{\"code\":1,\"message\":\"x\"},{\"code\":1,\"message\":\"y\"}]",
    ),
  )
  let report = @openrpc.validate(
    document,
    profile=@openrpc.MetaschemaCompatibility,
  )
  for finding in report.findings().filter(f => f.phase() == @openrpc.Normative) {
    let expected = if finding.discrepancy() is Some(_) {
      @openrpc.Warning
    } else {
      @openrpc.Error
    }
    assert_eq(finding.severity(), expected, msg=finding.to_repr().to_string())
  }
  assert_true(
    report
    .findings()
    .any(f => {
      f.diagnostic().code() == @exact.ParameterOrder &&
      f.severity() == @openrpc.Warning
    }),
  )
  assert_true(
    report
    .findings()
    .any(f => {
      f.diagnostic().code() == @exact.DuplicateErrorCode &&
      f.severity() == @openrpc.Error
    }),
  )
  assert_eq(report.normative(), @openrpc.Failed)
}

///|
test "fields outside a version's tables are normative warnings" {
  let old = @openrpc.validate(
    versioned(
      "1.3.2",
      "\"$schema\":\"https://meta.open-rpc.org/\",\"methods\":[{\"name\":\"a\",\"params\":[],\"foo\":1,\"tags\":[{\"name\":\"t\",\"summary\":\"s\"}]}],\"components\":{\"examplePairings\":{}}",
    ),
  )
  assert_eq(normative(old), [
    (@exact.UnknownField, @openrpc.Warning, ["$schema"]),
    (@exact.UnknownField, @openrpc.Warning, ["components", "examplePairings"]),
    (@exact.UnknownField, @openrpc.Warning, ["methods", "0", "foo"]),
  ])
  assert_eq(old.normative(), @openrpc.Passed)
  assert_eq(old.model(), @openrpc.Passed)
  let modern = @openrpc.validate(
    versioned(
      "1.4.0",
      "\"$schema\":\"https://meta.open-rpc.org/\",\"methods\":[{\"name\":\"a\",\"params\":[],\"tags\":[{\"name\":\"t\",\"summary\":\"s\"}]}],\"components\":{\"examplePairingObjects\":{}}",
    ),
  )
  assert_eq(normative(modern), [
    (@exact.UnknownField, @openrpc.Warning, [
      "components", "examplePairingObjects",
    ]),
    (@exact.UnknownField, @openrpc.Warning, [
      "methods", "0", "tags", "0", "summary",
    ]),
  ])
}

///|
test "reference failures cause no semantic findings" {
  let report = @openrpc.validate(
    versioned(
      "1.4.0",
      "\"methods\":[{\"name\":\"a\",\"params\":[{\"$ref\":\"#/missing\"},{\"name\":\"r\",\"required\":true,\"schema\":true}]},{\"$ref\":\"#/missing\"}]",
    ),
  )
  assert_eq(normative(report), [])
  assert_eq(report.references(), @openrpc.Failed)
}

///|
test "server variables keep their versioned field table" {
  let report = @openrpc.validate(
    versioned(
      "1.4.0",
      "\"servers\":[{\"url\":\"https://{host}\",\"variables\":{\"host\":{\"default\":\"a.test\",\"enum\":[\"a.test\"],\"foo\":1}}}],\"methods\":[]",
    ),
  )
  assert_eq(normative(report), [
    (@exact.UnknownField, @openrpc.Warning, [
      "servers", "0", "variables", "host", "foo",
    ]),
  ])
  assert_eq(artifact(report), [])
}

///|
test "component keys outside the OpenRPC grammar do not form a document" {
  let read = @openrpc.read(
    "{\"openrpc\":\"1.4.0\",\"info\":{\"title\":\"API\",\"version\":\"1\"},\"methods\":[],\"components\":{\"errors\":{\"a b\":{\"code\":1,\"message\":\"x\"}}}}",
  )
  assert_true(read.document() is None)
  assert_eq(read.diagnostics().map(d => d.path()), [
    ["components", "errors", "a b"],
  ])
}

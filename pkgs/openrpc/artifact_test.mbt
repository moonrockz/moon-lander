///|
fn artifact(
  report : @openrpc.ValidationReport,
) -> Array[(@exact.Code, Array[String], String?)] {
  report
  .findings()
  .filter(f => f.phase() == @openrpc.Artifact)
  .map(f => (f.diagnostic().code(), f.location().path(), f.expected_field()))
}

///|
test "minimal documents pass both pinned artifacts" {
  for version in ["1.3.2", "1.4.0", "1.4.12"] {
    let report = @openrpc.validate(versioned(version, "\"methods\":[]"))
    assert_eq(artifact(report), [], msg=version)
    assert_eq(report.artifact(), @openrpc.Passed, msg=version)
  }
}

///|
test "closed artifact objects reject unknown members" {
  for version in ["1.3.2", "1.4.0"] {
    let document = @openrpc.read(
      "{\"openrpc\":\"" +
      version +
      "\",\"info\":{\"title\":\"API\",\"version\":\"1\",\"foo\":1,\"x-ok\":2},\"methods\":[]}",
    )
      .document()
      .unwrap()
    let report = @openrpc.validate(document)
    assert_eq(
      artifact(report),
      [(@exact.UnknownField, ["info", "foo"], None)],
      msg=version,
    )
    assert_eq(report.artifact(), @openrpc.Failed)
    assert_eq(report.model(), @openrpc.Passed)
  }
}

///|
test "reference siblings fail only the artifact" {
  let report = @openrpc.validate(
    versioned(
      "1.3.2",
      "\"methods\":[{\"$ref\":\"#/x-m\",\"summary\":\"s\"}],\"x-m\":{\"name\":\"a\",\"params\":[]}",
    ),
  )
  assert_eq(artifact(report), [
    (@exact.UnknownField, ["methods", "0", "summary"], None),
  ])
  assert_eq(report.references(), @openrpc.Passed)
}

///|
let external_example : String = "\"methods\":[{\"name\":\"a\",\"params\":[],\"examples\":[{\"name\":\"p\",\"params\":[{\"name\":\"e\",\"externalValue\":\"https://x.test/a.json\"}]}]}]"

///|
test "external examples miss the artifact's required inline value" {
  let report = @openrpc.validate(versioned("1.3.2", external_example))
  assert_eq(artifact(report), [
    (@exact.MissingField, ["methods", "0", "examples", "0", "params", "0"], Some(
      "value",
    )),
  ])
  assert_eq(report.normative(), @openrpc.Passed)
}

///|
test "example objects may carry a reference sibling under oneOf" {
  let report = @openrpc.validate(
    versioned(
      "1.4.0",
      "\"methods\":[{\"name\":\"a\",\"params\":[],\"examples\":[{\"name\":\"p\",\"params\":[{\"name\":\"e\",\"value\":1,\"$ref\":\"#/components/examples/E\"}]}]}],\"components\":{\"examples\":{\"E\":{\"name\":\"e\",\"value\":2}}}",
    ),
  )
  assert_eq(artifact(report), [])
  assert_eq(report.references(), @openrpc.Passed)
}

///|
test "artifact tables keep their own versioned gaps" {
  let link = "\"methods\":[{\"name\":\"a\",\"params\":[],\"links\":[{\"method\":\"a\"}]}]"
  for version in ["1.3.2", "1.4.0"] {
    assert_eq(artifact(@openrpc.validate(versioned(version, link))), [])
  }
  let pairings = "\"methods\":[],\"components\":{\"examplePairingObjects\":{\"P\":{\"name\":\"p\",\"params\":[]}}}"
  assert_eq(artifact(@openrpc.validate(versioned("1.3.2", pairings))), [])
  let unnamed = "\"methods\":[],\"components\":{\"examples\":{\"E\":{\"value\":1}}}"
  assert_eq(artifact(@openrpc.validate(versioned("1.4.0", unnamed))), [
    (@exact.MissingField, ["components", "examples", "E"], Some("name")),
  ])
}

///|
/// The TSA leaf of the trusted root of the conformance case `rekor2-happy-path`.
fn tsa_leaf() -> Certificate raise {
  let text = @fixtures.conformance
    .iter()
    .find_first(file => file.0 == "rekor2-happy-path/trusted_root.json")
    .unwrap()
    .1
  guard @json.parse(text) is Object(root) &&
    root.get("timestampAuthorities") is Some(Array([Object(authority), ..])) &&
    authority.get("certChain") is Some(Object(chain)) &&
    chain.get("certificates") is Some(Array([Object(first), ..])) &&
    first.get("rawBytes") is Some(String(raw)) else {
    fail("no TSA leaf")
  }
  parse(@encoding.decode_base64(raw))
}

///|
/// The leaf with its extended key usage extension replaced.
fn with_eku(leaf : Certificate, critical : Bool, usages : Array[String]) -> Certificate {
  let extensions = leaf.extensions.map(extension => if extension.oid == "2.5.29.37" {
    { ..extension, critical }
  } else {
    extension
  })
  { ..leaf, extensions, extended_key_usage: Some(usages) }
}

///|
test "a timestamping leaf passes" {
  assert_eq(tsa_leaf().timestamp_signer_problem(), None)
}

///|
test "the timestamping EKU must be critical and hold only timeStamping" {
  let leaf = tsa_leaf()
  let eku = "the signer does not have a critical extended key usage of only timeStamping"
  assert_eq(with_eku(leaf, false, [EKU_TIME_STAMPING]).timestamp_signer_problem(), Some(eku))
  assert_eq(
    with_eku(leaf, true, [EKU_TIME_STAMPING, EKU_CODE_SIGNING]).timestamp_signer_problem(),
    Some(eku),
  )
  assert_eq(with_eku(leaf, true, [EKU_CODE_SIGNING]).timestamp_signer_problem(), Some(eku))
  assert_eq(
    { ..leaf, extensions: leaf.extensions.filter(e => e.oid != "2.5.29.37"), extended_key_usage: None }.timestamp_signer_problem(),
    Some(eku),
  )
}

///|
test "the key usage, CA flag and critical extensions of a timestamping leaf" {
  let leaf = tsa_leaf()
  // digitalSignature (bit 0) or contentCommitment (bit 1) is enough; none fails.
  assert_eq({ ..leaf, key_usage: Some(KEY_USAGE_CONTENT_COMMITMENT) }.timestamp_signer_problem(), None)
  assert_eq({ ..leaf, key_usage: None }.timestamp_signer_problem(), None)
  assert_eq(
    { ..leaf, key_usage: Some(KEY_USAGE_CERT_SIGN) }.timestamp_signer_problem(),
    Some("the signer key usage does not allow signatures"),
  )
  assert_eq(
    { ..leaf, basic_constraints: Some({ is_ca: true, path_length: None }) }.timestamp_signer_problem(),
    Some("the signer is a certificate authority"),
  )
  let unknown = { oid: "1.2.3.4", critical: true, value: b"" }
  assert_eq(
    { ..leaf, extensions: [..leaf.extensions, unknown] }.timestamp_signer_problem(),
    Some("the signer has the unknown critical extension 1.2.3.4"),
  )
}

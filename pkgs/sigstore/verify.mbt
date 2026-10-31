///|
/// Ends the pipeline at the first check that fails.
priv suberror Stop {
  Stop(Rejection)
}

///|
fn invalid(failure : Failure) -> Stop {
  Stop(Invalid(failure))
}

///|
fn unsupported(feature : Feature) -> Stop {
  Stop(Unsupported(feature))
}

///|
let in_toto_payload_type : String = "application/vnd.in-toto+json"

///|
/// The in-toto statement types that a payload can have.
let in_toto_statement_types : Array[String] = [
  "https://in-toto.io/Statement/v1", "https://in-toto.io/Statement/v0.1",
]

///|
/// The most subjects of a statement, and digests of a subject, as in sigstore-go.
let max_subjects : Int = 1024

///|
let max_subject_digests : Int = 32

///|
/// Verify a Sigstore bundle for an artifact.
///
/// The verdict passes when the bundle was logged in a transparency log of
/// `root`, its certificate chains to a certificate authority of `root` at the
/// log's integrated time, its signature covers content that names `artifact`,
/// and its certificate matches `policy` or one of `alternatives`. `now` only
/// bounds the integrated time. The function does no I/O and reads no clock.
pub fn verify(
  bundle : Bundle,
  artifact : ArtifactDigest,
  root : TrustedRoot,
  policy : Policy,
  now~ : Instant,
  alternatives? : Array[Policy] = [],
) -> Verdict {
  try run(bundle, artifact, root, [policy, ..alternatives], now) catch {
    Stop(rejection) => Rejected(rejection)
  } noraise {
    verified => Verified(verified)
  }
}

///|
/// The leaf certificate after it is parsed, and its key.
priv struct Leaf {
  certificate : @x509.Certificate
  key : @signature.PublicKey
}

///|
fn run(
  bundle : Bundle,
  artifact : ArtifactDigest,
  root : TrustedRoot,
  policies : Array[Policy],
  now : Instant,
) -> VerifiedBundle raise Stop {
  let raw_leaf = match bundle.material {
    Certificate(leaf) => leaf
    KeyHint => raise unsupported(PublicKeyMaterial)
  }
  if bundle.content is Dsse(envelope) && envelope.signatures.length() != 1 {
    raise invalid(BundleShape("a DSSE envelope must have exactly one signature"))
  }
  let leaf = read_leaf(raw_leaf)
  // Every time source must verify (design TIME-2).
  let times : Array[VerifiedTime] = []
  for entry in bundle.entries {
    let time = check_entry(entry, root, now)
    times.push({ time, source: Log(log_id=entry.log_id, log_index=entry.log_index) })
  }
  let signature = match bundle.content {
    Dsse(envelope) => envelope.signatures[0]
    Message(signature~, ..) => signature
  }
  for token in bundle.timestamps {
    times.push(check_timestamp(token, signature, root, now))
  }
  guard !times.is_empty() else {
    raise invalid(
      TransparencyLog("the bundle has no transparency log entry and no timestamp"),
    )
  }
  for verified in times {
    check_certificate(leaf, root, verified.time)
  }
  for entry in bundle.entries {
    check_body(bundle, entry, leaf)
  }
  let statement = check_content(bundle, leaf, artifact)
  let claims = read_claims(leaf.certificate) catch {
    err => raise invalid(Certificate(Unreadable(err.message())))
  }
  let reasons = []
  for index, policy in policies {
    match policy.mismatch(claims, statement) {
      None =>
        return {
          statement,
          policy_index: index,
          claims,
          times,
        }
      Some(reason) => reasons.push(reason)
    }
  }
  raise invalid(Policy(reasons))
}

///|
fn read_leaf(raw : Bytes) -> Leaf raise Stop {
  let certificate = @x509.parse(raw) catch {
    err => raise invalid(Certificate(Unreadable(err.message())))
  }
  let key = @signature.PublicKey::from_spki(certificate.spki) catch {
    UnsupportedKey(kind) => raise unsupported(KeyType(kind))
    BadKey(rule) => raise invalid(Certificate(Unreadable("bad public key: \{rule}")))
  }
  { certificate, key }
}

///|
/// Check one Rekor v1 entry: its log, its signed entry timestamp, its time and
/// its inclusion proof. Give the verified integrated time.
fn check_entry(
  entry : LogEntry,
  root : TrustedRoot,
  now : Instant,
) -> Instant raise Stop {
  match (entry.kind, entry.version) {
    ("dsse", "0.0.1") | ("hashedrekord", "0.0.1") => ()
    ("dsse", "0.0.2") | ("hashedrekord", "0.0.2") => raise unsupported(RekorV2)
    (kind, version) => raise unsupported(EntryKind(kind~, version~))
  }
  guard root.tlog(entry.log_id) is Some(log) else {
    raise invalid(
      TransparencyLog(
        "the log \{@encoding.encode_hex(entry.log_id)} is not in the trusted root",
      ),
    )
  }
  let key = match log.key {
    Usable(key) => key
    Unusable(kind) => raise unsupported(KeyType(kind))
  }
  guard entry.promise is Some(promise) else {
    raise invalid(TransparencyLog("the entry has no signed entry timestamp"))
  }
  let payload = @tlog.set_payload(
    entry.body,
    entry.integrated_time,
    entry.log_id,
    entry.log_index,
  )
  guard key.verify(payload, promise) else {
    raise invalid(TransparencyLog("the signed entry timestamp does not verify"))
  }
  let time = Instant::from_unix_seconds(entry.integrated_time)
  guard log.valid.contains(time) && time <= now else {
    raise invalid(TransparencyLogTime(integrated_time=time, now~))
  }
  if entry.proof is Some(proof) {
    check_inclusion(entry, proof, key)
  }
  time
}

///|
fn check_inclusion(
  entry : LogEntry,
  proof : InclusionProof,
  key : @signature.PublicKey,
) -> Unit raise Stop {
  let computed = @tlog.root_from_inclusion_proof(
    proof.log_index,
    proof.tree_size,
    @tlog.leaf_hash(entry.body),
    proof.hashes,
  )
  guard computed is Some(hash) else {
    raise invalid(InclusionProof("the proof does not fit the index and tree size"))
  }
  guard hash == proof.root_hash else {
    raise invalid(InclusionProof("the proof gives another root hash"))
  }
  let checkpoint = @tlog.parse_checkpoint(proof.checkpoint) catch {
    BadCheckpoint(rule) => raise invalid(Checkpoint(rule))
  }
  guard checkpoint.verify(key) else {
    raise invalid(Checkpoint("no signature of the log key verifies"))
  }
  guard checkpoint.root_hash == proof.root_hash else {
    raise invalid(Checkpoint("the checkpoint root hash differs from the proof"))
  }
  guard checkpoint.size == proof.tree_size else {
    raise invalid(Checkpoint("the checkpoint tree size differs from the proof"))
  }
}

///|
/// The JSON object at `name` of `json`, or a body failure.
fn body_object(json : Json?, name : String) -> Json raise Stop {
  guard json is Some(Object(_) as found) else {
    raise invalid(TransparencyLogBody("the body has no \{name}"))
  }
  found
}

///|
/// The member `key` of a JSON object.
fn json_field(json : Json, key : String) -> Json? {
  if json is Object(object) {
    object.get(key)
  } else {
    None
  }
}

///|
fn body_string(json : Json?, name : String) -> String raise Stop {
  guard json is Some(String(text)) else {
    raise invalid(TransparencyLogBody("the body has no \{name}"))
  }
  text
}

///|
fn body_base64(json : Json?, name : String) -> Bytes raise Stop {
  @encoding.decode_base64(body_string(json, name)) catch {
    _ => raise invalid(TransparencyLogBody("\{name} is not base64"))
  }
}

///|
/// True when the PEM text holds exactly the leaf certificate.
fn same_certificate(pem : Bytes, leaf : Leaf) -> Bool {
  let text = @utf8.decode(pem) catch {
    _ => return false
  }
  let certificates = @x509.decode_pem(text) catch {
    _ => return false
  }
  certificates.length() == 1 && certificates[0] == leaf.certificate.raw
}

///|
/// Check that the logged body is for this bundle's signature, certificate and
/// content.
fn check_body(bundle : Bundle, entry : LogEntry, leaf : Leaf) -> Unit raise Stop {
  let text = @utf8.decode(entry.body) catch {
    _ => raise invalid(TransparencyLogBody("the body is not UTF-8"))
  }
  let body = @json.parse(text) catch {
    _ => raise invalid(TransparencyLogBody("the body is not JSON"))
  }
  guard json_field(body, "kind") is Some(String(kind)) &&
    kind == entry.kind &&
    json_field(body, "apiVersion") is Some(String(version)) &&
    version == entry.version else {
    raise invalid(TransparencyLogBody("the body kind or version differs from the entry"))
  }
  let spec = body_object(json_field(body, "spec"), "spec")
  match (entry.kind, bundle.content) {
    ("dsse", Dsse(envelope)) => {
      let payload_hash = body_object(json_field(spec, "payloadHash"), "payloadHash")
      guard body_string(json_field(payload_hash, "algorithm"), "payloadHash.algorithm") ==
        "sha256" &&
        body_string(json_field(payload_hash, "value"), "payloadHash.value").to_lower() ==
        @encoding.encode_hex(@signature.sha256(envelope.payload)) else {
        raise invalid(TransparencyLogBody("the payload hash differs from the payload"))
      }
      guard json_field(spec, "signatures") is Some(Array(signatures)) &&
        signatures.length() == 1 else {
        raise invalid(TransparencyLogBody("the body does not have one signature"))
      }
      let logged = signatures[0]
      guard body_base64(json_field(logged, "signature"), "signature") ==
        envelope.signatures[0] else {
        raise invalid(TransparencyLogBody("the logged signature differs from the envelope"))
      }
      guard same_certificate(body_base64(json_field(logged, "verifier"), "verifier"), leaf) else {
        raise invalid(TransparencyLogBody("the logged certificate differs from the leaf"))
      }
    }
    ("hashedrekord", Message(algorithm~, digest~, signature~)) => {
      let hash = body_object(
        json_field(body_object(json_field(spec, "data"), "data"), "hash"),
        "data.hash",
      )
      let logged_algorithm = body_string(json_field(hash, "algorithm"), "data.hash.algorithm")
      guard logged_algorithm == algorithm.rekor_name() &&
        body_string(json_field(hash, "value"), "data.hash.value").to_lower() ==
        @encoding.encode_hex(digest) else {
        raise invalid(TransparencyLogBody("the logged digest differs from the message digest"))
      }
      let logged = body_object(json_field(spec, "signature"), "signature")
      guard body_base64(json_field(logged, "content"), "signature.content") == signature else {
        raise invalid(TransparencyLogBody("the logged signature differs from the bundle"))
      }
      let key = body_object(json_field(logged, "publicKey"), "signature.publicKey")
      guard same_certificate(body_base64(json_field(key, "content"), "signature.publicKey.content"), leaf) else {
        raise invalid(TransparencyLogBody("the logged certificate differs from the leaf"))
      }
    }
    _ =>
      raise invalid(TransparencyLogBody("the entry kind does not match the bundle content"))
  }
}

///|
/// The certificate chain at `time`, from the leaf to the root, for a trusted
/// certificate authority whose validity holds `time`.
fn check_certificate(leaf : Leaf, root : TrustedRoot, time : Instant) -> Unit raise Stop {
  let certificate = leaf.certificate
  guard valid_at(certificate, time) else {
    raise invalid(
      CertificateValidity(
        not_before=Instant::from_unix_seconds(certificate.not_before),
        not_after=Instant::from_unix_seconds(certificate.not_after),
        time~,
      ),
    )
  }
  guard certificate.extended_key_usage is Some(usages) &&
    usages.contains(@x509.EKU_CODE_SIGNING) else {
    raise invalid(Certificate(NotForCodeSigning))
  }
  guard certificate.key_usage is Some(bits) &&
    (bits & @x509.KEY_USAGE_DIGITAL_SIGNATURE) != 0 else {
    raise invalid(Certificate(NoDigitalSignature))
  }
  if certificate.unhandled_critical() is Some(oid) {
    raise invalid(Certificate(UnknownCriticalExtension(oid)))
  }
  if certificate.basic_constraints is Some(constraints) && constraints.is_ca {
    raise invalid(Certificate(LeafIsAuthority))
  }
  let mut reason = "no trusted certificate authority issued the leaf"
  for authority in root.authorities {
    guard authority.valid.contains(time) else { continue }
    match chain_from(certificate, authority.chain, time, @x509.EKU_CODE_SIGNING) {
      Ok(issuer) => {
        // The SCT rule of the root that listed the authority (design ROOT-1).
        if authority.sct_required {
          check_sct(leaf, issuer, root)
        }
        return
      }
      Err(text) => reason = text
    }
  }
  raise invalid(CertificateChain(reason))
}

///|
/// Check the path from `leaf` through `chain[start..]` at `time`. Give the
/// certificate that issued the leaf, or the reason that no path is valid.
fn chain_from(
  leaf : @x509.Certificate,
  chain : ArrayView[@x509.Certificate],
  time : Instant,
  usage : String,
) -> Result[@x509.Certificate, String] {
  let mut reason = "no certificate of the authority issued the leaf"
  for start in 0..<chain.length() {
    guard leaf.is_issued_by(chain[start]) else { continue }
    match check_path(chain, start, time, usage) {
      None => return Ok(chain[start])
      Some(text) => reason = text
    }
  }
  Err(reason)
}

///|
/// The reason that the CA path `chain[start..]` is not valid at `time` for the
/// extended key usage `usage`, or `None`.
fn check_path(
  chain : ArrayView[@x509.Certificate],
  start : Int,
  time : Instant,
  usage : String,
) -> String? {
  for index in start..<chain.length() {
    let ca = chain[index]
    guard valid_at(ca, time) else {
      return Some("a certificate authority certificate is not valid at that time")
    }
    guard ca.basic_constraints is Some(constraints) && constraints.is_ca else {
      return Some("an issuer is not a certificate authority")
    }
    // The number of CA certificates below this one in the path.
    let below = index - start
    if constraints.path_length is Some(limit) && below > limit {
      return Some("the path is longer than a path length constraint")
    }
    if ca.key_usage is Some(bits) && (bits & @x509.KEY_USAGE_CERT_SIGN) == 0 {
      return Some("an issuer key usage does not allow certificate signing")
    }
    if ca.extended_key_usage is Some(usages) &&
      !usages.contains(usage) &&
      !usages.contains(@x509.EKU_ANY) {
      return Some("an issuer does not allow the extended key usage \{usage}")
    }
    if ca.unhandled_critical() is Some(oid) {
      return Some("an issuer has the unknown critical extension \{oid}")
    }
    if index + 1 < chain.length() {
      guard ca.is_issued_by(chain[index + 1]) else {
        return Some("the authority chain does not verify")
      }
    }
  }
  None
}

///|
/// True when `time` is inside the validity of `certificate`, both bounds
/// inclusive, with the fraction of a second counted.
fn valid_at(certificate : @x509.Certificate, time : Instant) -> Bool {
  let seconds = time.unix_seconds()
  certificate.not_before <= seconds &&
  (seconds < certificate.not_after ||
  (seconds == certificate.not_after && time == Instant::from_unix_seconds(seconds)))
}

///|
let eku_time_stamping : String = "1.3.6.1.5.5.7.3.8"

///|
/// Key usage contentCommitment (bit 1), which a timestamping leaf may have.
let key_usage_content_commitment : Int = 2

///|
/// Verify one RFC 3161 timestamp of the bundle signature `signature` against
/// the timestamp authorities of `root`, and give its time.
fn check_timestamp(
  bytes : Bytes,
  signature : Bytes,
  root : TrustedRoot,
  now : Instant,
) -> VerifiedTime raise Stop {
  let token = @timestamp.parse(bytes) catch {
    BadTimestamp(rule) => raise invalid(Timestamp(rule))
    UnsupportedTimestamp(name) => raise unsupported(TimestampAlgorithm(name))
  }
  guard @signature.digest(token.imprint_hash, signature) == token.imprint else {
    raise invalid(Timestamp("the message imprint is not the hash of the bundle signature"))
  }
  let time = Instant::from_parts(token.seconds, token.nanos)
  guard time <= now else { raise invalid(TimestampTime(time~, now~)) }
  // The reason of the first authority whose validity holds the time is the
  // most useful one.
  let mut reason : String? = None
  let mut outside = false
  for authority in root.timestamp_authorities {
    guard authority.valid.contains(time) else {
      outside = true
      continue
    }
    match timestamp_signer(token, authority, time) {
      None => return { time, source: Authority(uri=authority.uri) }
      Some(text) => if reason is None { reason = Some(text) }
    }
  }
  raise invalid(
    TimestampAuthority(
      match reason {
        Some(text) => text
        None if outside => "the timestamp time is outside the validity of the authority"
        None => "no timestamp authority of the trusted root signed the timestamp"
      },
    ),
  )
}

///|
/// The reason that `authority` did not sign `token` at `time`, or `None`.
fn timestamp_signer(
  token : @timestamp.Timestamp,
  authority : Authority,
  time : Instant,
) -> String? raise Stop {
  let chain = authority.chain
  let names_signer = (certificate : @x509.Certificate) => certificate.issuer ==
    token.signer_issuer &&
    certificate.serial == token.signer_serial
  // A listed leaf is the only signer; an embedded certificate can never take
  // its place (design TSA-2).
  let first_is_leaf = !(chain[0].basic_constraints is Some({ is_ca: true, .. }))
  let (signer, issuers) = if first_is_leaf {
    guard names_signer(chain[0]) else {
      return Some("the signer is not the leaf of the authority")
    }
    (chain[0], chain[1:])
  } else {
    let embedded = token.certificates
      .iter()
      .filter_map(raw => try Some(@x509.parse(raw)) catch { _ => None })
    guard embedded.find_first(names_signer) is Some(signer) else {
      return Some("the token has no certificate for its signer")
    }
    (signer, chain[:])
  }
  guard valid_at(signer, time) else {
    return Some("the timestamp authority certificate is not valid at the timestamp time")
  }
  guard signer.extension("2.5.29.37") is Some(eku) &&
    eku.critical &&
    signer.extended_key_usage == Some([eku_time_stamping]) else {
    return Some("the signer does not have a critical extended key usage of only timeStamping")
  }
  if signer.key_usage is Some(bits) &&
    (bits & (@x509.KEY_USAGE_DIGITAL_SIGNATURE | key_usage_content_commitment)) == 0 {
    return Some("the signer key usage does not allow signatures")
  }
  if signer.basic_constraints is Some({ is_ca: true, .. }) {
    return Some("the signer is a certificate authority")
  }
  if signer.unhandled_critical() is Some(oid) {
    return Some("the signer has the unknown critical extension \{oid}")
  }
  if token.signing_certificate is Some(reference) {
    guard @signature.digest(reference.hash, signer.raw) == reference.cert_hash else {
      return Some("the signing certificate attribute names another certificate")
    }
  }
  if token.signing_time is Some(signing_time) {
    guard signer.not_before <= signing_time && signing_time <= signer.not_after else {
      return Some("the signing time is outside the signer validity")
    }
  }
  let key = @signature.PublicKey::from_spki(signer.spki) catch {
    UnsupportedKey(kind) => raise unsupported(TimestampAlgorithm("\{kind} keys"))
    BadKey(rule) => return Some("bad signer key: \{rule}")
  }
  guard token.verify_signature(key) else {
    return Some("the timestamp signature does not verify")
  }
  guard !issuers.is_empty() else { return Some("the authority has no issuer certificate") }
  match chain_from(signer, issuers, time, eku_time_stamping) {
    Ok(_) => None
    Err(text) => Some(text)
  }
}

///|
/// Require one embedded SCT from a trusted CT log that verifies.
fn check_sct(leaf : Leaf, issuer : @x509.Certificate, root : TrustedRoot) -> Unit raise Stop {
  guard leaf.certificate.extension(@x509.SCT_LIST_OID) is Some(extension) else {
    raise invalid(CertificateTimestamp("the leaf has no embedded SCT"))
  }
  let scts = @sct.parse_list(extension.value) catch {
    BadSct(rule) => raise invalid(CertificateTimestamp(rule))
  }
  guard !scts.is_empty() else { raise invalid(CertificateTimestamp("the SCT list is empty")) }
  let tbs = leaf.certificate.tbs_without(@x509.SCT_LIST_OID) catch {
    err => raise invalid(Certificate(Unreadable(err.message())))
  }
  for sct in scts {
    guard root.ctlog(sct.log_id) is Some(log) else { continue }
    guard log.key is Usable(key) else { continue }
    let time = Instant::from_unix_millis(sct.timestamp)
    guard log.valid.contains(time) else { continue }
    if sct.verify(key, issuer.spki, tbs) {
      return
    }
  }
  raise invalid(CertificateTimestamp("no SCT from a trusted CT log verifies"))
}

///|
/// The DSSE pre-authentication encoding: `DSSEv1 SP LEN(type) SP type SP
/// LEN(body) SP body`, with lengths in ASCII decimal.
fn pae(payload_type : String, payload : Bytes) -> Bytes {
  let type_bytes = @encoding.utf8(payload_type)
  let out : Array[Byte] = []
  for byte in @encoding.utf8("DSSEv1 \{type_bytes.length()} ") {
    out.push(byte)
  }
  for byte in type_bytes {
    out.push(byte)
  }
  for byte in @encoding.utf8(" \{payload.length()} ") {
    out.push(byte)
  }
  for byte in payload {
    out.push(byte)
  }
  Bytes::from_array(out)
}

///|
/// Verify a signature with the hash of the key, and for a P-384 key also with
/// SHA-256, as sigstore-go does for bundles up to v0.3.
fn verify_with_leaf(leaf : Leaf, message : Bytes, signature : Bytes) -> Bool {
  leaf.key.verify(message, signature) ||
  (leaf.key.kind is EcdsaP384 && leaf.key.verify(message, signature, hash=Sha256))
}

///|
/// Check the content signature and that the content names the artifact.
fn check_content(
  bundle : Bundle,
  leaf : Leaf,
  artifact : ArtifactDigest,
) -> Statement? raise Stop {
  match bundle.content {
    Dsse(envelope) => {
      guard envelope.payload_type == in_toto_payload_type else {
        raise invalid(PayloadType(envelope.payload_type))
      }
      guard verify_with_leaf(
          leaf,
          pae(envelope.payload_type, envelope.payload),
          envelope.signatures[0],
        ) else {
        raise invalid(ContentSignature)
      }
      let statement = read_statement(envelope.payload)
      guard statement.subjects.iter().any(subject => subject.sha256 == Some(artifact)) else {
        raise invalid(ArtifactDigestMismatch(artifact))
      }
      Some(statement)
    }
    Message(algorithm~, digest~, signature~) => {
      guard algorithm is Sha2_256 else {
        raise unsupported(DigestAlgorithm(algorithm.name()))
      }
      guard digest.length() == 32 else {
        raise invalid(BundleShape("a SHA-256 message digest has 32 bytes"))
      }
      guard leaf.key.verify_digest(digest, signature) else {
        raise invalid(ContentSignature)
      }
      guard digest == artifact.to_bytes() else {
        raise invalid(ArtifactDigestMismatch(artifact))
      }
      None
    }
  }
}

///|
/// Read the in-toto statement of a DSSE payload.
fn read_statement(payload : Bytes) -> Statement raise Stop {
  let text = @utf8.decode(payload) catch {
    _ => raise invalid(Statement("the payload is not UTF-8"))
  }
  // Duplicate keys are refused, as protobuf JSON refuses them, so that no
  // other reader can see another subject list in the same signed payload.
  let json = @json.parse(text, reject_duplicate_keys=true) catch {
    _ => raise invalid(Statement("the payload is not JSON, or has a duplicate key"))
  }
  guard json_field(json, "_type") is Some(String(statement_type)) &&
    in_toto_statement_types.contains(statement_type) else {
    raise invalid(Statement("the payload is not an in-toto statement"))
  }
  guard json_field(json, "predicateType") is Some(String(predicate_text)) else {
    raise invalid(Statement("the statement has no predicate type"))
  }
  let predicate_type = PredicateType::parse(predicate_text) catch {
    err => raise invalid(Statement(err.message()))
  }
  guard json_field(json, "subject") is Some(Array(items)) && items.length() <= max_subjects else {
    raise invalid(Statement("the statement has no subject list, or more than \{max_subjects}"))
  }
  let subjects = []
  for item in items {
    guard json_field(item, "digest") is Some(Object(digests)) && digests.length() <= max_subject_digests else {
      raise invalid(Statement("a subject has no digest map, or more than \{max_subject_digests}"))
    }
    let sha256 = match digests.get("sha256") {
      Some(String(hex)) => {
        let bytes = @encoding.decode_hex(hex) catch {
          _ => raise invalid(Statement("a subject digest is not hex"))
        }
        guard bytes.length() == 32 else {
          raise invalid(Statement("a subject sha256 digest does not have 32 bytes"))
        }
        Some(ArtifactDigest::{ bytes, })
      }
      Some(_) => raise invalid(Statement("a subject digest is not a string"))
      None => None
    }
    let name = match json_field(item, "name") {
      Some(String(name)) => name
      _ => ""
    }
    subjects.push({ name, sha256 })
  }
  let predicate = json_field(json, "predicate").unwrap_or(Json::null())
  { predicate_type, predicate, subjects, payload }
}

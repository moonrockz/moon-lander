///|
fn base64(text : String) -> Bytes raise {
  @encoding.decode_base64(text)
}

///|
fn text_of(bytes : Bytes) -> String raise {
  @utf8.decode(bytes)
}

///|
/// The text of a fixture file in a generated fixture group.
fn fixture(group : Array[(String, String)], path : String) -> String {
  for file in group {
    if file.0 == path {
      return file.1
    }
  }
  abort("no fixture \{path}")
}

///|
fn object_at(json : Json, path : Array[String]) -> Map[String, Json] raise {
  let mut at = json
  for name in path {
    guard at is Object(object) && object.get(name) is Some(next) else {
      fail("no \{name}")
    }
    at = next
  }
  guard at is Object(object) else { fail("not an object") }
  object
}

///|
fn member_text(object : Map[String, Json], name : String) -> String raise {
  guard object.get(name) is Some(String(value)) else { fail("no text \{name}") }
  value
}

///|
/// The public-good Rekor v1 key (tlogs[0] of the public-good trusted root).
let rekor_key : String = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE2G2Y+2tabdTV5BcGiBIx0a9fAFwrkBbmLSGtks4L3qX6yYY0zufBnhC8Ur/iy55GhWP/9A/bY2LhC30M9+RYtw=="

///|
/// The public-good CT log key (ctlogs[1]), a P-256 key of another log.
let ct_key : String = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEiPSlFi0CmFTfEjCUqF9HuCEcYXNKAaYalIJmBZ8yyezPjTqhxrKBpMnaocVtLJBI1eM3uXnQzQGAJdJ4gs9Fyw=="

///|
/// The Rekor entry of the morphir-rust GitHub attestation.
fn morphir_entry() -> Map[String, Json] raise {
  let bundle = @json.parse(
    fixture(
      @fixtures.github, "morphir-rust-provider-snapshot-0.2.0.sigstore.json",
    ),
  )
  guard object_at(bundle, ["verificationMaterial"]).get("tlogEntries")
    is Some(Array(entries)) &&
    entries.length() == 1 &&
    entries[0] is Object(entry) else {
    fail("one tlog entry")
  }
  entry
}

///|
test "set_payload is the canonical JSON of the entry" {
  assert_eq(
    text_of(@tlog.set_payload(b"hi", 1L, b"\xab\x01", 2L)),
    "{\"body\":\"aGk=\",\"integratedTime\":1,\"logID\":\"ab01\",\"logIndex\":2}",
  )
  assert_eq(
    text_of(@tlog.set_payload(b"", 0L, b"", 0L)),
    "{\"body\":\"\",\"integratedTime\":0,\"logID\":\"\",\"logIndex\":0}",
  )
  // Base64 padding and characters past 62 are kept as they are.
  assert_eq(
    text_of(@tlog.set_payload(b"\xfb\xff", 1792133282L, b"\x00\xff", 3275146211L)),
    "{\"body\":\"+/8=\",\"integratedTime\":1792133282,\"logID\":\"00ff\",\"logIndex\":3275146211}",
  )
}

///|
test "the real signed entry timestamp signs set_payload" {
  let entry = morphir_entry()
  let body = base64(member_text(entry, "canonicalizedBody"))
  let log_id = base64(member_text(object_at(Json::object(entry), ["logId"]), "keyId"))
  let set = base64(
    member_text(object_at(Json::object(entry), ["inclusionPromise"]), "signedEntryTimestamp"),
  )
  let key = @signature.PublicKey::from_spki(base64(rekor_key))
  assert_eq(log_id, @signature.sha256(key.spki))
  let payload = @tlog.set_payload(body, 1792133282L, log_id, 3275146211L)
  assert_true(key.verify(payload, set))
  // Another time or index does not verify.
  assert_false(
    key.verify(@tlog.set_payload(body, 1792133283L, log_id, 3275146211L), set),
  )
  assert_false(
    key.verify(@tlog.set_payload(body, 1792133282L, log_id, 3153241949L), set),
  )
}

///|
test "leaf and node hashes have the RFC 6962 prefixes" {
  assert_eq(
    @encoding.encode_hex(@tlog.leaf_hash(b"")),
    "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d",
  )
  assert_eq(@tlog.leaf_hash(b"abc"), @signature.sha256(b"\x00abc"))
  assert_eq(@tlog.node_hash(b"ab", b"cd"), @signature.sha256(b"\x01abcd"))
  assert_true(@tlog.node_hash(b"ab", b"cd") != @tlog.node_hash(b"cd", b"ab"))
}

///|
/// The largest power of two that is less than `n` (n > 1).
fn split_point(n : Int) -> Int {
  let mut k = 1
  while k * 2 < n {
    k = k * 2
  }
  k
}

///|
/// The RFC 6962 tree hash of `leaves` (leaf hashes), at least one.
fn tree_hash(leaves : ArrayView[Bytes]) -> Bytes {
  if leaves.length() == 1 {
    return leaves[0]
  }
  let k = split_point(leaves.length())
  @tlog.node_hash(tree_hash(leaves[:k]), tree_hash(leaves[k:]))
}

///|
/// The RFC 6962 audit path of the leaf at `index`.
fn audit_path(index : Int, leaves : ArrayView[Bytes]) -> Array[Bytes] {
  if leaves.length() == 1 {
    return []
  }
  let k = split_point(leaves.length())
  if index < k {
    let path = audit_path(index, leaves[:k])
    path.push(tree_hash(leaves[k:]))
    path
  } else {
    let path = audit_path(index - k, leaves[k:])
    path.push(tree_hash(leaves[:k]))
    path
  }
}

///|
fn small_tree(size : Int) -> Array[Bytes] {
  Array::makei(size, i => @tlog.leaf_hash(Bytes::make(i + 1, i.to_byte())))
}

///|
test "inclusion proofs of every leaf of trees of 1 to 8 leaves" {
  for size in 1..=8 {
    let leaves = small_tree(size)
    let root = tree_hash(leaves[:])
    for index in 0..<size {
      let proof = audit_path(index, leaves[:])
      let at = "size \{size} index \{index}"
      assert_eq(
        @tlog.root_from_inclusion_proof(
          index.to_int64(),
          size.to_int64(),
          leaves[index],
          proof,
        ),
        Some(root),
        msg=at,
      )
      // One hash too many.
      let longer = proof.copy()
      longer.push(root)
      assert_eq(
        @tlog.root_from_inclusion_proof(
          index.to_int64(),
          size.to_int64(),
          leaves[index],
          longer,
        ),
        None,
        msg=at,
      )
      if proof.length() > 0 {
        // One hash too few.
        assert_eq(
          @tlog.root_from_inclusion_proof(
            index.to_int64(),
            size.to_int64(),
            leaves[index],
            proof[:proof.length() - 1].to_owned(),
          ),
          None,
          msg=at,
        )
        // A hash of 31 bytes and of 33 bytes.
        for i in 0..<proof.length() {
          let short = proof.copy()
          short[i] = proof[i][:31].to_owned()
          assert_eq(
            @tlog.root_from_inclusion_proof(
              index.to_int64(),
              size.to_int64(),
              leaves[index],
              short,
            ),
            None,
            msg=at,
          )
          let long = proof.copy()
          long[i] = Bytes::from_array([..proof[i], b'\x00'])
          assert_eq(
            @tlog.root_from_inclusion_proof(
              index.to_int64(),
              size.to_int64(),
              leaves[index],
              long,
            ),
            None,
            msg=at,
          )
          // A changed hash gives another root.
          let changed = proof.copy()
          let bytes = proof[i].to_array()
          bytes[0] = bytes[0] ^ b'\x01'
          changed[i] = Bytes::from_array(bytes)
          let other = @tlog.root_from_inclusion_proof(
            index.to_int64(),
            size.to_int64(),
            leaves[index],
            changed,
          )
          assert_true(other is Some(hash) && hash != root, msg=at)
        }
      } else {
        // A one-leaf tree: the root is the leaf.
        assert_eq(root, leaves[0])
      }
      // A changed leaf gives another root.
      let changed_leaf = @tlog.root_from_inclusion_proof(
        index.to_int64(),
        size.to_int64(),
        @tlog.leaf_hash(b"other"),
        proof,
      )
      assert_true(changed_leaf is Some(hash) && hash != root, msg=at)
      // A leaf of 31 bytes.
      assert_eq(
        @tlog.root_from_inclusion_proof(
          index.to_int64(),
          size.to_int64(),
          leaves[index][:31],
          proof,
        ),
        None,
        msg=at,
      )
    }
    // The index must be in the tree.
    let proof = audit_path(size - 1, leaves[:])
    for index in [-1L, size.to_int64(), size.to_int64() + 1L] {
      assert_eq(
        @tlog.root_from_inclusion_proof(
          index,
          size.to_int64(),
          leaves[size - 1],
          proof,
        ),
        None,
        msg="size \{size} index \{index}",
      )
    }
  }
  // An empty tree has no leaf, and a negative size is refused.
  assert_eq(@tlog.root_from_inclusion_proof(0L, 0L, small_tree(1)[0], []), None)
  assert_eq(
    @tlog.root_from_inclusion_proof(-1L, -1L, small_tree(1)[0], []),
    None,
  )
}

///|
test "the real morphir-rust inclusion proof gives the root hash" {
  let entry = morphir_entry()
  let proof = object_at(Json::object(entry), ["inclusionProof"])
  let body = base64(member_text(entry, "canonicalizedBody"))
  guard proof.get("hashes") is Some(Array(items)) else { fail("no hashes") }
  let hashes = items.map(item => {
    guard item is String(text) else { fail("a hash is not text") }
    base64(text)
  })
  assert_eq(hashes.length(), 25)
  assert_eq(member_text(proof, "logIndex"), "3153241949")
  assert_eq(member_text(proof, "treeSize"), "3153242266")
  let root = base64(member_text(proof, "rootHash"))
  let leaf = @tlog.leaf_hash(body)
  assert_eq(
    @tlog.root_from_inclusion_proof(3153241949L, 3153242266L, leaf, hashes),
    Some(root),
  )
  // The entry log index is not the index in the tree.
  assert_true(
    @tlog.root_from_inclusion_proof(3275146211L, 3153242266L, leaf, hashes)
    is None,
  )
  // A neighbour index gives another root.
  let neighbour = @tlog.root_from_inclusion_proof(
    3153241948L,
    3153242266L,
    leaf,
    hashes,
  )
  assert_true(neighbour != Some(root))
}

///|
let morphir_checkpoint : String = "rekor.sigstore.dev - 1193050959916656506\n3153242266\nksJPOaqwDlRB0LJdpzhXegJuIpROHGiyq0AIGfPD/Pw=\n\n\u{2014} rekor.sigstore.dev wNI9ajBFAiBKtfZhl/EeonvIcHVM5EMEu4x6KQdHtAXlZvcI2P4y6gIhANlZbzCizccrC8kuWXnDOOpWHwd8280okKhlMgzTo7U4\n"

///|
/// The outcome of `parse_checkpoint` as text.
fn checkpoint_outcome(envelope : String) -> String {
  try {
    let checkpoint = @tlog.parse_checkpoint(envelope)
    "ok \{checkpoint.size} \{checkpoint.signatures.length()}"
  } catch {
    BadCheckpoint(rule) => rule
  }
}

///|
/// A checkpoint with the fields given, signed with a fake signature line.
fn note(text : String, signatures : String) -> String {
  text + "\n" + signatures
}

///|
let root_text : String = "ksJPOaqwDlRB0LJdpzhXegJuIpROHGiyq0AIGfPD/Pw="

///|
/// A signature line with a key hint and one signature byte.
let fake_signature : String = "\u{2014} name AAAAAAA=\n"

///|
test "the real checkpoint is read" {
  assert_eq(@encoding.encode_base64(Bytes::make(5, b'\x00')), "AAAAAAA=")
  let checkpoint = @tlog.parse_checkpoint(
    fixture_checkpoint(morphir_entry()),
  )
  assert_eq(checkpoint.origin, "rekor.sigstore.dev - 1193050959916656506")
  assert_eq(checkpoint.size, 3153242266L)
  assert_eq(checkpoint.root_hash, base64(root_text))
  assert_eq(
    text_of(checkpoint.text),
    "rekor.sigstore.dev - 1193050959916656506\n3153242266\n\{root_text}\n",
  )
  assert_eq(checkpoint.signatures.length(), 1)
  let signature = checkpoint.signatures[0]
  assert_eq(signature.name, "rekor.sigstore.dev")
  assert_eq(@encoding.encode_hex(signature.key_hint), "c0d23d6a")
  assert_eq(signature.signature.length(), 71)
  assert_eq(fixture_checkpoint(morphir_entry()), morphir_checkpoint)
}

///|
fn fixture_checkpoint(entry : Map[String, Json]) -> String raise {
  member_text(object_at(Json::object(entry), ["inclusionProof", "checkpoint"]), "envelope")
}

///|
test "checkpoint text rules" {
  let header = "origin\n5\n\{root_text}\n"
  assert_eq(checkpoint_outcome(note(header, fake_signature)), "ok 5 1")
  // Extra lines after the root hash are allowed.
  assert_eq(
    checkpoint_outcome(note(header + "extension\n", fake_signature)),
    "ok 5 1",
  )
  assert_eq(
    checkpoint_outcome(header + fake_signature),
    "no blank line before the signatures",
  )
  assert_eq(
    checkpoint_outcome(note("origin\n5\n", fake_signature)),
    "the text has too few lines",
  )
  assert_eq(
    checkpoint_outcome(note("\n5\n\{root_text}\n", fake_signature)),
    "the origin is empty",
  )
  for size in ["", "x", "-1", "+5", " 5", "5 ", "0x5", "1_0", "99999999999999999999"] {
    assert_eq(
      checkpoint_outcome(note("origin\n\{size}\n\{root_text}\n", fake_signature)),
      "the tree size is not a number",
      msg=size,
    )
  }
  assert_eq(
    checkpoint_outcome(note("origin\n0\n\{root_text}\n", fake_signature)),
    "ok 0 1",
  )
  assert_eq(
    checkpoint_outcome(note("origin\n5\n!!!!\n", fake_signature)),
    "the root hash is not base64",
  )
  let short_root = @encoding.encode_base64(Bytes::make(31, b'\x01'))
  let long_root = @encoding.encode_base64(Bytes::make(33, b'\x01'))
  assert_eq(
    checkpoint_outcome(note("origin\n5\n\{short_root}\n", fake_signature)),
    "the root hash is not 32 bytes",
  )
  assert_eq(
    checkpoint_outcome(note("origin\n5\n\{long_root}\n", fake_signature)),
    "the root hash is not 32 bytes",
  )
}

///|
test "checkpoint signature line rules" {
  let header = "origin\n5\n\{root_text}\n"
  assert_eq(
    checkpoint_outcome(note(header, "- name AAAAAAA=\n")),
    "a signature line does not start with an em dash",
  )
  assert_eq(
    checkpoint_outcome(note(header, "\u{2014}name AAAAAAA=\n")),
    "a signature line does not start with an em dash",
  )
  assert_eq(
    checkpoint_outcome(note(header, "\u{2014} AAAAAAA=\n")),
    "a signature line has no name",
  )
  assert_eq(
    checkpoint_outcome(note(header, "\u{2014}  AAAAAAA=\n")),
    "a signature line has no name",
  )
  assert_eq(
    checkpoint_outcome(note(header, "\u{2014} name !!!!\n")),
    "a signature is not base64",
  )
  // A name ends at the first space.
  assert_eq(
    checkpoint_outcome(note(header, "\u{2014} two names AAAAAAA=\n")),
    "a signature is not base64",
  )
  // Four bytes are only the key hint; five bytes are the shortest signature.
  assert_eq(
    checkpoint_outcome(note(header, "\u{2014} name AAAAAA==\n")),
    "a signature is too short",
  )
  assert_eq(checkpoint_outcome(note(header, "\u{2014} name AAAAAAA=\n")), "ok 5 1")
  assert_eq(
    checkpoint_outcome(note(header, "")),
    "the note has no signature",
  )
  assert_eq(
    checkpoint_outcome(note(header, fake_signature + fake_signature)),
    "ok 5 2",
  )
}

///|
test "the real checkpoint verifies with the Rekor key only" {
  let rekor = @signature.PublicKey::from_spki(base64(rekor_key))
  let other = @signature.PublicKey::from_spki(base64(ct_key))
  let checkpoint = @tlog.parse_checkpoint(morphir_checkpoint)
  assert_true(checkpoint.verify(rekor))
  assert_false(checkpoint.verify(other))
  // A changed tree size or root hash fails.
  let size = @tlog.parse_checkpoint(
    morphir_checkpoint.replace(old="\n3153242266\n", new="\n3153242267\n"),
  )
  assert_eq(size.size, 3153242267L)
  assert_false(size.verify(rekor))
  let changed_root = morphir_checkpoint.replace(
    old=root_text,
    new="ksJPOaqwDlRB0LJdpzhXegJuIpROHGiyq0AIGfPD/Pv=",
  )
  assert_false(@tlog.parse_checkpoint(changed_root).verify(rekor))
  // A changed origin fails.
  assert_false(
    @tlog.parse_checkpoint(
      morphir_checkpoint.replace(old="rekor.sigstore.dev - ", new="rekor.sigstore.dev  - "),
    ).verify(rekor),
  )
}

///|
test "a checkpoint with the Rekor hint must have only good signatures" {
  let rekor = @signature.PublicKey::from_spki(base64(rekor_key))
  let good_line = "\u{2014} rekor.sigstore.dev wNI9ajBFAiBKtfZhl/EeonvIcHVM5EMEu4x6KQdHtAXlZvcI2P4y6gIhANlZbzCizccrC8kuWXnDOOpWHwd8280okKhlMgzTo7U4\n"
  // The same signature with its last byte changed.
  let bad_line = "\u{2014} rekor.sigstore.dev wNI9ajBFAiBKtfZhl/EeonvIcHVM5EMEu4x6KQdHtAXlZvcI2P4y6gIhANlZbzCizccrC8kuWXnDOOpWHwd8280okKhlMgzTo7U5\n"
  // A line from another key.
  let foreign_line = "\u{2014} other.example AAAAAAAA\n"
  let text = "rekor.sigstore.dev - 1193050959916656506\n3153242266\n\{root_text}\n\n"
  assert_true(@tlog.parse_checkpoint(text + good_line).verify(rekor))
  assert_false(@tlog.parse_checkpoint(text + bad_line).verify(rekor))
  assert_false(@tlog.parse_checkpoint(text + good_line + bad_line).verify(rekor))
  assert_false(@tlog.parse_checkpoint(text + bad_line + good_line).verify(rekor))
  assert_true(
    @tlog.parse_checkpoint(text + foreign_line + good_line).verify(rekor),
  )
  assert_false(@tlog.parse_checkpoint(text + foreign_line).verify(rekor))
}

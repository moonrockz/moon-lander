///|
/// The text that a Rekor v1 signed entry timestamp signs: canonical JSON
/// (RFC 8785) of the body, integrated time, log ID and log index. The keys are
/// in this order, and the values are only base64 text, lowercase hex and
/// integers, so no other escaping applies.
pub fn set_payload(
  body : BytesView,
  integrated_time : Int64,
  log_id : BytesView,
  log_index : Int64,
) -> Bytes {
  @encoding.utf8(
    "{\"body\":\"\{@encoding.encode_base64(body)}\",\"integratedTime\":\{integrated_time},\"logID\":\"\{@encoding.encode_hex(log_id)}\",\"logIndex\":\{log_index}}",
  )
}

///|
/// The RFC 6962 hash of a leaf: SHA-256 of `0x00 ∥ data`.
pub fn leaf_hash(data : BytesView) -> Bytes {
  let input : Array[Byte] = [b'\x00']
  for byte in data {
    input.push(byte)
  }
  @signature.sha256(Bytes::from_array(input))
}

///|
/// The RFC 6962 hash of an inner node: SHA-256 of `0x01 ∥ left ∥ right`.
pub fn node_hash(left : BytesView, right : BytesView) -> Bytes {
  let input : Array[Byte] = [b'\x01']
  for byte in left {
    input.push(byte)
  }
  for byte in right {
    input.push(byte)
  }
  @signature.sha256(Bytes::from_array(input))
}

///|
fn bit_length(value : Int64) -> Int {
  let mut bits = 0
  let mut rest = value
  while rest > 0L {
    bits += 1
    rest = rest >> 1
  }
  bits
}

///|
fn popcount(value : Int64) -> Int {
  let mut count = 0
  let mut rest = value
  while rest > 0L {
    count += (rest & 1L).to_int()
    rest = rest >> 1
  }
  count
}

///|
/// The tree root that an RFC 6962 inclusion proof gives for the leaf at
/// `index` in a tree of `size` leaves (RFC 9162, section 2.1.3.2), or `None`
/// when the proof has the wrong shape for that position.
pub fn root_from_inclusion_proof(
  index : Int64,
  size : Int64,
  leaf : BytesView,
  proof : Array[Bytes],
) -> Bytes? {
  guard index >= 0L && index < size else { return None }
  let inner = bit_length(index ^ (size - 1L))
  let border = popcount(index >> inner)
  guard proof.length() == inner + border else { return None }
  guard proof.iter().all(hash => hash.length() == 32) && leaf.length() == 32 else {
    return None
  }
  let mut seed = leaf.to_owned()
  for i in 0..<inner {
    seed = if ((index >> i) & 1L) == 0L {
      node_hash(seed, proof[i])
    } else {
      node_hash(proof[i], seed)
    }
  }
  for i in inner..<proof.length() {
    seed = node_hash(proof[i], seed)
  }
  Some(seed)
}

///|
/// A checkpoint text that cannot be read.
pub suberror CheckpointError {
  BadCheckpoint(String)
} derive(Debug)

///|
pub extend CheckpointError with @debug.Debug::{to_repr}

///|
/// One signature line of a signed note.
pub struct NoteSignature {
  name : String
  key_hint : Bytes
  signature : Bytes
}

///|
/// A Rekor checkpoint: a signed note whose text gives the origin, the tree
/// size and the root hash.
pub struct Checkpoint {
  origin : String
  size : Int64
  root_hash : Bytes
  /// The signed text, with its final newline.
  text : Bytes
  signatures : Array[NoteSignature]
}

///|
/// Read a signed note in the form that Rekor writes.
pub fn parse_checkpoint(envelope : String) -> Checkpoint raise CheckpointError {
  guard envelope.rev_find("\n\n") is Some(split) else {
    raise BadCheckpoint("no blank line before the signatures")
  }
  let text = envelope[:split + 1].to_owned()
  let lines = text.split("\n").map(line => line.to_owned()).collect()
  // The text ends with a newline, so the last part is empty.
  guard lines.length() >= 4 else { raise BadCheckpoint("the text has too few lines") }
  let origin = lines[0]
  guard !origin.is_empty() else { raise BadCheckpoint("the origin is empty") }
  let size = @string.parse_int64(lines[1]) catch {
    _ => raise BadCheckpoint("the tree size is not a number")
  }
  guard size >= 0L && lines[1].iter().all(c => c >= '0' && c <= '9') else {
    raise BadCheckpoint("the tree size is not a number")
  }
  let root_hash = @encoding.decode_base64(lines[2]) catch {
    _ => raise BadCheckpoint("the root hash is not base64")
  }
  guard root_hash.length() == 32 else { raise BadCheckpoint("the root hash is not 32 bytes") }
  let signatures = []
  for line in envelope[split + 2:].split("\n") {
    if line.is_empty() {
      continue
    }
    guard line.has_prefix("\u{2014} ") else {
      raise BadCheckpoint("a signature line does not start with an em dash")
    }
    let rest = line[2:]
    // The name has no space (signed note format), so the first space ends it.
    guard rest.find(" ") is Some(space) && space > 0 else {
      raise BadCheckpoint("a signature line has no name")
    }
    let bytes = @encoding.decode_base64(rest[space + 1:]) catch {
      _ => raise BadCheckpoint("a signature is not base64")
    }
    guard bytes.length() > 4 else { raise BadCheckpoint("a signature is too short") }
    signatures.push({
      name: rest[:space].to_owned(),
      key_hint: bytes[:4].to_owned(),
      signature: bytes[4:].to_owned(),
    })
  }
  guard !signatures.is_empty() else { raise BadCheckpoint("the note has no signature") }
  { origin, size, root_hash, text: @encoding.utf8(text), signatures }
}

///|
/// True when a signature whose key hint is the first four bytes of SHA-256 of
/// the key's DER encoding verifies, and no signature with that hint fails.
pub fn Checkpoint::verify(self : Checkpoint, key : @signature.PublicKey) -> Bool {
  let hint = @signature.sha256(key.spki)[:4].to_owned()
  let mut verified = false
  for signature in self.signatures {
    if signature.key_hint == hint {
      if !key.verify(self.text, signature.signature) {
        return false
      }
      verified = true
    }
  }
  verified
}

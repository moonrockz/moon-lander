///|
/// Select how a message becomes an undelivered-event payload.
/// The default omits the message. Ion and JSON encoding include the whole message;
/// use a custom encoder to remove secrets. Encoders cannot raise.
pub struct PayloadPolicy[M] {
  priv encoder : ((M) -> @ion.Ion)?
}

///|
/// Omit the message from the event payload, with no encoding work.
pub fn[M] PayloadPolicy::omit() -> PayloadPolicy[M] {
  { encoder: None }
}

///|
/// Omit the message by default, because messages can hold secrets.
pub fn[M] PayloadPolicy::default() -> PayloadPolicy[M] {
  PayloadPolicy::omit()
}

///|
/// Apply the policy to a message. The runtime calls this only for an undelivered
/// event with an active subscriber. `None` means the policy omits the payload.
pub fn[M] PayloadPolicy::apply(self : PayloadPolicy[M], message : M) -> @ion.Ion? {
  self.encoder.map(encode => encode(message))
}

///|
/// Encode the whole message with its Ion implementation, preserving Ion types.
pub fn[M : @ion.ToIon] PayloadPolicy::ion() -> PayloadPolicy[M] {
  { encoder: Some(message => @ion.Ion(message)) }
}

///|
/// Encode the whole message as JSON, then hold that JSON as an Ion value.
pub fn[M : ToJson] PayloadPolicy::json() -> PayloadPolicy[M] {
  { encoder: Some(message => @ion.Ion(message.to_json())) }
}

///|
/// Use a custom encoder, for example to remove a secret or omit a reply field.
/// The encoder cannot raise.
pub fn[M] PayloadPolicy::encode(f : (M) -> @ion.Ion) -> PayloadPolicy[M] {
  { encoder: Some(f) }
}

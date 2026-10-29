///|
/// The identity of one actor lifetime. Copies of handles and references keep
/// it. Another actor gets another address. An address cannot send to or
/// control an actor, and its text is only for diagnostics.
pub struct ActorAddress {
  priv id : Int64
}

///|
pub impl Eq for ActorAddress with equal(self, other) {
  self.id == other.id
}

///|
pub extend ActorAddress with Eq::{equal, not_equal}

///|
pub impl Hash for ActorAddress with hash_combine(self, hasher) {
  hasher.combine(self.id)
}

///|
pub extend ActorAddress with Hash::{hash, hash_combine}

///|
pub impl @debug.Debug for ActorAddress with to_repr(self) {
  @debug.Repr(self.to_string())
}

///|
pub extend ActorAddress with @debug.Debug::{to_repr}

///|
/// Diagnostic text such as `actor#7`.
pub fn ActorAddress::to_string(self : ActorAddress) -> String {
  "actor#\{self.id}"
}

///|
/// The last address that this process gave. Addresses are never reused.
let last_address : Ref[Int64] = Ref(0L)

///|
fn ActorAddress::next() -> ActorAddress {
  last_address.val += 1L
  { id: last_address.val }
}

///|
/// The identity of one actor lifetime, with the name that the actor started
/// with, if any. Copies of handles and references keep it. A replacement
/// actor gets another address, also when it reuses a name. An address cannot
/// send to or control an actor, and its text is only for diagnostics.
pub struct ActorAddress {
  priv id : Int64
  priv name : @policy.ActorName?
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
/// Creation order, only for the directory's internal map. The order is not
/// part of the contract.
impl Compare for ActorAddress with compare(self, other) {
  self.id.compare(other.id)
}

///|
pub impl @debug.Debug for ActorAddress with to_repr(self) {
  @debug.Repr(self.to_string())
}

///|
pub extend ActorAddress with @debug.Debug::{to_repr}

///|
/// The name of the actor, when it started with one.
pub fn ActorAddress::name(self : ActorAddress) -> @policy.ActorName? {
  self.name
}

///|
/// Diagnostic text such as `actor#7` or `actor#7(counter)`. It cannot be
/// parsed back into an address.
pub fn ActorAddress::to_string(self : ActorAddress) -> String {
  match self.name {
    Some(name) => "actor#\{self.id}(\{name.to_string()})"
    None => "actor#\{self.id}"
  }
}

///|
/// The last address that this process gave. Addresses are never reused.
let last_address : Ref[Int64] = Ref(0L)

///|
fn ActorAddress::next(name : @policy.ActorName?) -> ActorAddress {
  last_address.val += 1L
  { id: last_address.val, name }
}

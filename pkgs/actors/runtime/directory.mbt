///|
/// An immutable set of send references with protocol `M`, keyed by actor
/// address. Operations give new values and never start, stop or own actors.
pub struct Directory[M] {
  priv members : @sorted_map.SortedMap[ActorAddress, ActorRef[M]]
}

///|
/// The directory with no members.
pub fn[M] Directory::empty() -> Directory[M] {
  { members: @sorted_map.SortedMap::new() }
}

///|
/// The directory with the one member `entry`.
pub fn[M] Directory::of(entry : ActorRef[M]) -> Directory[M] {
  Directory::empty().add(entry)
}

///|
/// All members of both directories, one for each address.
pub fn[M] Directory::union(self : Directory[M], other : Directory[M]) -> Directory[M] {
  let mut members = self.members
  for address, entry in other.members {
    members = members.add(address, entry)
  }
  { members, }
}

///|
/// This directory with `member` as a entry.
pub fn[M] Directory::add(self : Directory[M], entry : ActorRef[M]) -> Directory[M] {
  { members: self.members.add(entry.address(), entry) }
}

///|
/// This directory without the entry that has the address of `member`. Other
/// actors with the same name stay.
pub fn[M] Directory::remove(
  self : Directory[M],
  entry : ActorRef[M],
) -> Directory[M] {
  { members: self.members.remove(entry.address()) }
}

///|
/// This directory without every address of `other`.
pub fn[M] Directory::difference(
  self : Directory[M],
  other : Directory[M],
) -> Directory[M] {
  let mut members = self.members
  for address, _ in other.members {
    members = members.remove(address)
  }
  { members, }
}

///|
pub impl[M] Add for Directory[M] with add(self, other) {
  self.union(other)
}

///|
pub impl[M] Sub for Directory[M] with sub(self, other) {
  self.difference(other)
}

///|
/// Use `a - b` or `difference`; the `sub` method is not part of the API.
#deprecated
pub extend Directory with Sub::{sub}

///|
/// Equal when both have the same entry addresses.
pub impl[M] Eq for Directory[M] with equal(self, other) {
  self.members.length() == other.members.length() &&
  self.members.keys_as_iter().all(address => other.members.contains(address))
}

///|
pub extend Directory with Eq::{equal, not_equal}

///|
/// The number of members.
pub fn[M] Directory::size(self : Directory[M]) -> Int {
  self.members.length()
}

///|
/// The addresses of the members. The order is not part of the contract.
pub fn[M] Directory::addresses(self : Directory[M]) -> Array[ActorAddress] {
  self.members.keys_as_iter().collect()
}

///|
/// The entry with exactly `address`, also when that actor has ended.
pub fn[M] Directory::resolve(
  self : Directory[M],
  address : ActorAddress,
) -> ActorRef[M]? {
  self.members.get(address)
}

///|
/// The result of a name lookup.
pub enum Lookup[M] {
  /// No entry has the name.
  Missing
  /// One entry has the name.
  Found(ActorRef[M])
  /// Two or more members have the name.
  Ambiguous(NameConflict[M])
}

///|
/// Two or more different members with one name. Only `lookup` makes it.
pub struct NameConflict[M] {
  priv name : @policy.ActorName
  priv refs : Array[ActorRef[M]]
}

///|
/// The name that two or more members share.
pub fn[M] NameConflict::name(self : NameConflict[M]) -> @policy.ActorName {
  self.name
}

///|
/// The members with the name, as a new array.
pub fn[M] NameConflict::refs(self : NameConflict[M]) -> Array[ActorRef[M]] {
  self.refs.copy()
}

///|
/// The members with `name`. Lookup reads only this value: it does not search a
/// scope, a global registry or the liveness of actors.
pub fn[M] Directory::lookup(
  self : Directory[M],
  name : @policy.ActorName,
) -> Lookup[M] {
  let refs = self.members
    .values()
    .filter(entry => entry.address().name() is Some(found) && found == name)
    .collect()
  match refs {
    [] => Missing
    [entry] => Found(entry)
    _ => Ambiguous({ name, refs })
  }
}

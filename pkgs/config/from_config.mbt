///|
/// One value of the configuration tree for exact decoding: its decode path,
/// the value or its absence, and the sources to blame. A node in a list has a
/// decode path with an index suffix and the blame of the list.
pub struct ConfigNode {
  priv config : Config
  priv path : DecodePath
  priv value : ConfigValue?
}

///|
/// The decode path of the node.
pub fn ConfigNode::path(self : ConfigNode) -> DecodePath {
  self.path
}

///|
/// The value of the node, or `None` when no source sets it.
pub fn ConfigNode::value(self : ConfigNode) -> ConfigValue? {
  self.value
}

///|
/// The sources to blame for the value of the node.
pub fn ConfigNode::blame(self : ConfigNode) -> Blame {
  self.config.blame(self.path)
}

///|
/// The node of the field `name`. The node has no value when this node is not a
/// table or has no such field.
pub fn ConfigNode::child(self : ConfigNode, name : String) -> ConfigNode {
  {
    config: self.config,
    path: self.path.below([Field(name)]),
    value: match self.value {
      Some(value) => value.field(name)
      None => None
    },
  }
}

///|
/// The fields of a table, with their nodes, in configuration order. A node
/// that is not a table has no fields.
pub fn ConfigNode::children(self : ConfigNode) -> Array[(String, ConfigNode)] {
  guard self.value is Some(value) && value.ion.kind() is Struct(fields) else {
    return []
  }
  let children = []
  for field in fields {
    guard field.name().text() is Some(name) else { continue }
    children.push((
      name,
      {
        config: self.config,
        path: self.path.below([Field(name)]),
        value: Some({ ion: field.value() }),
      },
    ))
  }
  children
}

///|
/// The items of a list, in order. Each item node has the index in its decode
/// path and the blame of the list. A node that is not a list has no items.
pub fn ConfigNode::items(self : ConfigNode) -> Array[ConfigNode] {
  guard self.value is Some(value) else { return [] }
  match value.ion.kind() {
    List(items) | Sexp(items) =>
      items.mapi((index, item) => {
        config: self.config,
        path: self.path.below([Index(index)]),
        value: Some({ ion: item }),
      })
    _ => []
  }
}

///|
/// Decode the field `name` exactly.
pub fn[T : FromConfig] ConfigNode::get(
  self : ConfigNode,
  name : String,
) -> T raise ConfigError {
  T::from_config(self.child(name))
}

///|
/// Decode the node with `FromJson`, with the same error translation as `bind`:
/// a failure names the full decode path from the bound section. A node with no
/// value decodes as `null`. A secret reference in the node raises `Decode`.
pub fn[T : FromJson] ConfigNode::json(self : ConfigNode) -> T raise ConfigError {
  match self.value {
    Some(value) => {
      self.config.check_no_secret(self.path, value)
      decode(self.config, self.path, section_json(self.config, self.path, value))
    }
    None => decode(self.config, self.path, Json::null())
  }
}

///|
/// Raise `Decode` at the node with `detail` and the blame of the node. Use it
/// for a rule that a `FromConfig` implementation checks while it decodes.
pub fn[T] ConfigNode::fail(self : ConfigNode, detail : String) -> T raise ConfigError {
  raise Decode(failure={
    at: [{ path: self.path, blame: self.blame() }],
    detail,
  })
}

///|
/// Exact decoding from the configuration tree. Unlike `FromJson`, it keeps Ion
/// decimals, timestamps and integers of any size, and it can read the blame of
/// each value.
pub(open) trait FromConfig {
  from_config(ConfigNode) -> Self raise ConfigError
}

///|
/// Decode the section at `key` exactly into a `T`. A section that no source
/// sets gives a node with no value, so an `Option` target gives `None`. A
/// failure raises `Decode` with the decode path and the sources to blame.
/// Binding never resolves a secret reference: only `SecretRef` accepts one.
pub fn[T : FromConfig] bind_with(config : Config, key : String) -> T raise ConfigError {
  let path = KeyPath::parse(key)
  T::from_config({
    config,
    path: { key: Some(path), suffix: [] },
    value: config.get(path),
  })
}

///|
/// The value of a node that must have one. A node with no value fails with
/// `no value`, and a secret reference fails with the secret detail.
fn ConfigNode::present(self : ConfigNode) -> ConfigValue raise ConfigError {
  guard self.value is Some(value) else { self.fail("no value") }
  if is_secret_reference(value, self.config.secret_syntax) {
    self.fail(secret_detail)
  }
  value
}

///|
/// Fail because the value of the node is not of the type `expected`.
fn[T] ConfigNode::mismatch(
  self : ConfigNode,
  value : ConfigValue,
  expected : String,
) -> T raise ConfigError {
  self.fail("expected \{expected}, found \{value.type_name()}")
}

///|
/// Fail because an integer is out of the range of `target`.
fn[T] ConfigNode::out_of_range(self : ConfigNode, target : String) -> T raise ConfigError {
  self.fail("the integer is out of range for \{target}")
}

///|
/// Text or a symbol with text.
pub impl FromConfig for String with from_config(node) {
  let value = node.present()
  match value.ion.kind() {
    String(text) => text
    Symbol(token) if token.text() is Some(text) => text
    _ => node.mismatch(value, "string")
  }
}

///|
/// A time limit from its text form, for example `"30s"` or `"1m 30s"`. Only
/// text or a symbol with text can give one: a number has no unit, so it fails.
/// Text that `TimeLimit::parse` rejects fails with the parse message, which
/// names the input and the broken rule.
pub impl FromConfig for @lander_core.TimeLimit with from_config(node) {
  let value = node.present()
  let text = match value.ion.kind() {
    String(text) => text
    Symbol(token) if token.text() is Some(text) => text
    _ =>
      node.mismatch(value, "time limit text with a unit, such as \"30s\"")
  }
  @lander_core.TimeLimit::parse(text) catch {
    error => node.fail(error.message())
  }
}

///|
pub impl FromConfig for Bool with from_config(node) {
  let value = node.present()
  guard value.ion.kind() is Bool(flag) else { node.mismatch(value, "bool") }
  flag
}

///|
/// An integer value only, so a fraction fails.
fn ConfigNode::integer(self : ConfigNode) -> @bigint.BigInt raise ConfigError {
  let value = self.present()
  guard value.ion.kind() is Int(number) else { self.mismatch(value, "int") }
  number
}

///|
/// An integer in the range of `Int`. A fraction fails.
pub impl FromConfig for Int with from_config(node) {
  let number = node.integer()
  if number.compare_int(@int.MIN_VALUE) < 0 ||
    number.compare_int(@int.MAX_VALUE) > 0 {
    node.out_of_range("Int")
  }
  number.to_int()
}

///|
/// An integer in the range of `Int64`. A fraction fails.
pub impl FromConfig for Int64 with from_config(node) {
  let number = node.integer()
  if number.compare_int64(@int64.MIN_VALUE) < 0 ||
    number.compare_int64(@int64.MAX_VALUE) > 0 {
    node.out_of_range("Int64")
  }
  number.to_int64()
}

///|
/// An integer in the range of `UInt64`. A fraction fails.
pub impl FromConfig for UInt64 with from_config(node) {
  let number = node.integer()
  if number.compare_int(0) < 0 || number.compare_uint64(@uint64.MAX_VALUE) > 0 {
    node.out_of_range("UInt64")
  }
  number.to_uint64()
}

///|
/// An integer of any size.
pub impl FromConfig for @bigint.BigInt with from_config(node) {
  node.integer()
}

///|
/// A float, an integer or a decimal, as the nearest `Double`.
pub impl FromConfig for Double with from_config(node) {
  let value = node.present()
  let double = match value.ion.kind() {
    Float(double) => Some(double)
    Int(number) => @ion.Decimal::Decimal(number, 0).to_double()
    Decimal(decimal) => decimal.to_double()
    _ => node.mismatch(value, "float")
  }
  guard double is Some(double) else { node.fail("the number has no Double value") }
  double
}

///|
/// A decimal, or an integer as a decimal with exponent 0. A float fails,
/// because a binary float has no exact decimal scale.
pub impl FromConfig for @ion.Decimal with from_config(node) {
  let value = node.present()
  match value.ion.kind() {
    Decimal(decimal) => decimal
    Int(number) => @ion.Decimal::Decimal(number, 0)
    _ => node.mismatch(value, "decimal")
  }
}

///|
/// A timestamp with its precision, fraction and offset.
pub impl FromConfig for @ion.Timestamp with from_config(node) {
  let value = node.present()
  guard value.ion.kind() is Timestamp(timestamp) else {
    node.mismatch(value, "timestamp")
  }
  timestamp
}

///|
/// `None` when no source sets the value or the value is a null.
pub impl[T : FromConfig] FromConfig for T? with from_config(node) {
  match node.value {
    None => None
    Some(value) if value.ion.kind() is Null(_) => None
    Some(_) => Some(T::from_config(node))
  }
}

///|
/// Each item of a list, in order.
pub impl[T : FromConfig] FromConfig for Array[T] with from_config(node) {
  let value = node.present()
  guard value.ion.kind() is (List(_) | Sexp(_)) else {
    node.mismatch(value, "list")
  }
  node.items().map(item => T::from_config(item))
}

///|
/// Each field of a table, in configuration order.
pub impl[T : FromConfig] FromConfig for Map[String, T] with from_config(node) {
  let value = node.present()
  guard value.ion.kind() is Struct(_) else { node.mismatch(value, "struct") }
  let map = Map([])
  for child in node.children() {
    map[child.0] = T::from_config(child.1)
  }
  map
}

///|
/// The unresolved reference. Binding never resolves it; use
/// `Config::secret` for that.
pub impl FromConfig for SecretRef with from_config(node) {
  guard node.value is Some(value) else { node.fail("no value") }
  guard node.config.secret_syntax is Standard &&
    secret_ref_of(value) is Some(reference) else {
    node.mismatch(value, "a secret reference")
  }
  reference
}

///|
pub extend SecretRef with FromConfig::{from_config}

///|
/// A decoded value with the sources to blame for it, for example to resolve a
/// relative path against the file that set it.
pub struct Sourced[T] {
  value : T
  blame : Blame
} derive(Eq, Debug)

///|
pub extend Sourced with Eq::{equal, not_equal}

///|
pub extend Sourced with @debug.Debug::{to_repr}

///|
pub impl[T : FromConfig] FromConfig for Sourced[T] with from_config(node) {
  { value: T::from_config(node), blame: node.blame() }
}

///|
pub extend Sourced with FromConfig::{from_config}

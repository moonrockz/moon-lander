///|
/// The options values of the children of one section, one for each instance
/// name, in configuration order.
pub struct NamedOptions[T] {
  priv instances : Map[String, Options[T]]
}

///|
/// The options value of the instance `name`, or `None` when the section has no
/// child with that name.
pub fn[T] NamedOptions::get(self : NamedOptions[T], name : String) -> Options[T]? {
  self.instances.get(name)
}

///|
/// The instance names, in configuration order.
pub fn[T] NamedOptions::names(self : NamedOptions[T]) -> Array[String] {
  self.instances.keys().collect()
}

///|
/// Bind each child of the section at `key` as one named instance. `bind_one`
/// gets the configuration and the key text of one child, for example
/// `backends.ts`, and gives its options value; `bind`, `bind_or` and
/// `bind_with` with `validated` all fit. Each options value gets the child
/// name as its instance name. The `Decode` and `Validation` failures of all
/// instances raise one `Validation` error. A section that no source sets gives
/// no instances. A section that is not a table raises `Decode`.
pub fn[T] named(
  config : Config,
  key : String,
  bind_one : (Config, String) -> Options[T] raise ConfigError,
) -> NamedOptions[T] raise ConfigError {
  let path = KeyPath::parse(key)
  let instances : Map[String, Options[T]] = Map([])
  guard config.get(path) is Some(section) else { return { instances, } }
  guard section.ion.kind() is Struct(fields) else {
    let at : DecodePath = { key: Some(path), suffix: [] }
    raise Decode(failure={
      at: [{ path: at, blame: config.blame(at) }],
      detail: "must be a table of named instances",
    })
  }
  let failures : Array[BindFailure] = []
  for field in fields {
    guard field.name().text() is Some(name) else { continue }
    let child = KeyPath::from_names([..path.names, name])
    try bind_one(config, child.to_string()) catch {
      Decode(failure~) => failures.push(failure)
      Validation(failures=found) => failures.append(found)
      error => raise error
    } noraise {
      options => instances[name] = { ..options, name: Some(name) }
    }
  }
  if !failures.is_empty() {
    raise Validation(failures~)
  }
  { instances, }
}

///|
/// A merged configuration with the reports of its sources. Its root is always
/// a struct.
pub struct Config {
  priv root : ConfigValue
  priv reports : Array[SourceReport]
  priv notes : Array[ConfigWarning]
  priv provenance : Map[KeyPath, Array[Origin]]
  priv secret_syntax : SecretSyntax
}

///|
/// Load the sources in list order over a complete empty file tree: a later
/// source wins. A file source raises `FileNotFound`, so this suits value
/// sources.
pub fn build(sources : Array[ConfigSource]) -> Config raise ConfigError {
  match load(sources.fold(init=builder(), add), FileTree::new(complete=true)) {
    Done(config) => config
    Need(_) => abort("a complete file tree never asks for files")
  }
}

///|
/// The origins of the leaf at `key`: one origin for a replaced leaf or list.
/// A struct has no origin of its own, so a struct or a missing key gives an
/// empty array.
pub fn Config::origins(self : Config, key : KeyPath) -> Array[Origin] {
  self.provenance.get(key).map(origins => origins.copy()).unwrap_or([])
}

///|
/// The origins of every leaf, in tree order. Each array is not empty.
pub fn Config::provenance(self : Config) -> Array[(KeyPath, Array[Origin])] {
  leaves(self.root, secret_syntax=self.secret_syntax).map(leaf =>
    (leaf.0, self.origins(leaf.0))
  )
}

///|
/// The source reports in merge order.
pub fn Config::reports(self : Config) -> Array[SourceReport] {
  self.reports.map(report => {
    ..report,
    candidates: report.candidates.copy(),
    warnings: report.warnings.copy(),
  })
}

///|
/// The warnings of the load: the warnings of the source providers, then the
/// warnings of each source report in merge order.
pub fn Config::warnings(self : Config) -> Array[ConfigWarning] {
  [..self.notes, ..self.reports.map(report => report.warnings).flatten()]
}

///|
/// The merged value tree.
pub fn Config::value(self : Config) -> ConfigValue {
  self.root
}

///|
/// The value at `key`, or `None` when no value is there.
pub fn Config::get(self : Config, key : KeyPath) -> ConfigValue? {
  self.root.at(key.names)
}

///|
/// Resolve the secret at `key`. A plain string is a literal secret and does not
/// call the resolver. A secret reference calls `resolver` with the leaf origin.
pub fn[R : SecretResolver] Config::secret(
  self : Config,
  key : String,
  resolver : R,
) -> Secret raise SecretError {
  let path = KeyPath::parse(key) catch {
    _ => raise MissingConfigKey(key={ names: [key] })
  }
  guard self.get(path) is Some(value) else { raise MissingConfigKey(key=path) }
  match value.ion.kind() {
    String(text) => return { text, }
    _ => ()
  }
  guard secret_ref_of(value) is Some(reference) else {
    raise InvalidSecretValue(reason="configuration key \{path} is not a secret")
  }
  let origin = match self.provenance.get(path) {
    Some(origins) if !origins.is_empty() => origins[0]
    _ =>
      {
        kind: InMemory,
        source: "unknown",
        priority: 0,
        location: None,
      }
  }
  resolver.resolve(reference, origin)
}


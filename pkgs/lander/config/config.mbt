///|
/// A merged configuration with the reports of its sources. Its root is always
/// a struct.
pub struct Config {
  priv root : ConfigValue
  priv reports : Array[SourceReport]
  priv notes : Array[ConfigWarning]
  priv provenance : Map[KeyPath, Array[Origin]]
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
  leaves(self.root).map(leaf => (leaf.0, self.origins(leaf.0)))
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
/// The value at the key path `key` as text: a string gives its text, and any
/// other value gives compact JSON. A missing key raises `KeyNotFound`.
pub fn get_text(config : Config, key : String) -> String raise ConfigError {
  let path = KeyPath::parse(key)
  guard config.get(path) is Some(value) else { raise KeyNotFound(key=path) }
  match value.ion.kind() {
    String(text) => text
    _ => {
      let json = @ion_json.to_json(value.ion) catch {
        err => raise Render(format="JSON", key=path, reason=err.message())
      }
      json.stringify()
    }
  }
}

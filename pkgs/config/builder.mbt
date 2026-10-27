///|
/// An immutable list of sources and source providers in merge order, the
/// registered formats, and the explicit inputs of one run: the variable set,
/// the working directory, and the platform. Each function returns a new
/// builder.
pub struct ConfigBuilder {
  priv entries : Array[BuilderEntry]
  priv formats : Array[Format]
  priv env_vars : Map[String, String]?
  priv working_dir : String?
  priv platform : Platform?
  priv secret_syntax : SecretSyntax
}

///|
priv enum BuilderEntry {
  Source(ConfigSource)
  Provider(SourceProvider)
}

///|
/// A builder with no sources, no formats, and no run inputs.
pub fn builder() -> ConfigBuilder {
  {
    entries: [],
    formats: [],
    env_vars: None,
    working_dir: None,
    platform: None,
    secret_syntax: Standard,
  }
}

///|
/// Set whether one-field `env` / `file` / `command` / `keyring` structs are
/// secret references. The default is `SecretSyntax::standard()`.
pub fn secret_syntax(
  builder : ConfigBuilder,
  syntax : SecretSyntax,
) -> ConfigBuilder {
  { ..builder, secret_syntax: syntax }
}

///|
/// Add `source` after the sources that the builder holds.
pub fn add(builder : ConfigBuilder, source : ConfigSource) -> ConfigBuilder {
  { ..builder, entries: [..builder.entries, Source(source)] }
}

///|
/// Add a source provider. During the load, its sources take its place in
/// merge order.
pub fn provider(builder : ConfigBuilder, p : SourceProvider) -> ConfigBuilder {
  { ..builder, entries: [..builder.entries, Provider(p)] }
}

///|
/// Register `format` after the formats that the builder holds.
pub fn format(builder : ConfigBuilder, format : Format) -> ConfigBuilder {
  { ..builder, formats: [..builder.formats, format.copy()] }
}

///|
/// The registered formats in registration order.
pub fn ConfigBuilder::formats(self : ConfigBuilder) -> Array[Format] {
  self.formats.map(Format::copy)
}

///|
/// The variable set that the builder holds, or `None` when nobody gave one. A
/// host reads the process variables only when this is `None`.
pub fn ConfigBuilder::given_env_vars(
  self : ConfigBuilder,
) -> Map[String, String]? {
  self.env_vars.map(vars => vars.copy())
}

///|
/// The working directory that the builder holds, or `None` when nobody gave one.
pub fn ConfigBuilder::given_working_dir(self : ConfigBuilder) -> String? {
  self.working_dir
}

///|
/// The path texts of the file, candidate and parsed-file sources that the
/// builder holds, in add order, as the caller gave them. The load parses each
/// text one time; an adapter with stricter path rules, such as the browser
/// adapter, checks the texts here before the load. Providers are not included.
pub fn ConfigBuilder::given_file_paths(self : ConfigBuilder) -> Array[String] {
  let paths = []
  for entry in self.entries {
    guard entry is Source(source) else { continue }
    match source.input {
      Path(text) | Parsed(text, _) => paths.push(text)
      Candidates(texts, _) => paths.append(texts)
      _ => ()
    }
  }
  paths
}

///|
/// The platform that the builder holds, or `None` when nobody gave one.
pub fn ConfigBuilder::given_platform(self : ConfigBuilder) -> Platform? {
  self.platform
}

///|
/// Set the variable set of the run. Source providers read variables only from
/// this set.
pub fn env_vars(
  builder : ConfigBuilder,
  vars : Map[String, String],
) -> ConfigBuilder {
  { ..builder, env_vars: Some(vars.copy()) }
}

///|
/// Set the working directory of the run. A relative explicit file path joins
/// it.
pub fn working_dir(builder : ConfigBuilder, dir : String) -> ConfigBuilder {
  { ..builder, working_dir: Some(dir) }
}

///|
/// Set the platform of the run.
pub fn platform(builder : ConfigBuilder, p : Platform) -> ConfigBuilder {
  { ..builder, platform: Some(p) }
}

///|
/// Add a defaults source from a JSON value, for example
/// `Defaults::default().to_json()`.
pub fn defaults(
  builder : ConfigBuilder,
  json : Json,
) -> ConfigBuilder raise ConfigError {
  add(builder, ConfigSource::defaults(json))
}

///|
/// Add a file source at an explicit path, as `ConfigSource::file` gives it.
pub fn file(
  builder : ConfigBuilder,
  path : String,
  role? : FileRole = Explicit,
  name? : String,
  priority? : Int,
) -> ConfigBuilder {
  add(builder, ConfigSource::file(path, role~, name?, priority?))
}

///|
fn path(text : String) -> @config.FileTreePath raise @config.ConfigError { @config.FileTreePath::parse(text) }

///|
/// Equivalent public loads for every registered serialization. Each observation
/// retains values, complete provenance, reports and typed profile metadata.
pub fn configurations() -> Array[(String, @config.Config)] raise @config.ConfigError {
  let cases = [
    ("toml", "[profiles]\ninclude=['common']\nactive=['production']\n[profiles.groups]\nproduction=['metrics']", "mode='metrics'\nitems=['profile']"),
    ("yaml", "profiles:\n  include: [common]\n  active: [production]\n  groups:\n    production: [metrics]\n", "mode: metrics\nitems: [profile]\n"),
    ("json", "{\"profiles\":{\"include\":[\"common\"],\"active\":[\"production\"],\"groups\":{\"production\":[\"metrics\"]}}}", "{\"mode\":\"metrics\",\"items\":[\"profile\"]}"),
    ("json5", "{profiles:{include:['common'],active:['production'],groups:{production:['metrics']}}}", "{mode:'metrics',items:['profile'],}"),
    ("ion", "{profiles:{include:[\"common\"],active:[\"production\"],groups:{production:[\"metrics\"]}}}", "{mode:\"metrics\",items:[\"profile\"]}"),
  ]
  let output = []
  for case in cases {
    let (extension, base, overlay) = case
    let primary = "acme.\{extension}"
    let profile = "acme.profile.metrics.\{extension}"
    let tree = @config.FileTree::new(complete=true)
      .with_listing(path("/workspace"), [{name: primary,kind:File},{name:profile,kind:File}])
      .with_file(path("/workspace/\{primary}"), base)
      .with_file(path("/workspace/\{profile}"), overlay)
    let mut builder = @config.builder() |> @config.working_dir("/workspace") |> @config.env_vars({})
    for format in @formats.formats() { builder = builder |> @config.format(format) }
    builder = builder |> @config.defaults({"mode":"base","items":["base"]})
      |> @conventions.add(@conventions.base("acme") |> @conventions.layouts |> @conventions.profiles(@profiles.Policy::new()))
    guard @config.load(builder, tree) is Done(config) else { abort("complete public fixture") }
    output.push((extension,config))
  }
  output
}

///|
/// Complete values, provenance, source reports and profile metadata for parity.
pub fn observations() -> String raise @config.ConfigError {
  let output = []
  for (extension, config) in configurations() {
    output.push(extension)
    output.push(@debug.Debug::to_repr(config.value().to_ion()).to_string())
    output.push(@debug.Debug::to_repr(config.provenance()).to_string())
    output.push(@debug.Debug::to_repr(config.reports()).to_string())
    output.push(@debug.Debug::to_repr(config.profiles()).to_string())
  }
  output.push(failure_observations())
  output.join("\n")
}


///|
fn failure_observations() -> String raise @config.ConfigError {
  let observations = []
  for (extension, text) in [
    ("toml", "profiles.active=42"),
    ("yaml", "profiles:\n  active: 42\n"),
    ("json", "{\"profiles\":{\"active\":42}}"),
    ("json5", "{profiles:{active:42}}"),
    ("ion", "{profiles:{active:42}}"),
  ] {
    let filename = "acme.\{extension}"
    let tree = @config.FileTree::new(complete=true)
      .with_listing(path("/workspace"), [{name: filename,kind:File}])
      .with_file(path("/workspace/\{filename}"),text)
    let mut builder = @config.builder() |> @config.working_dir("/workspace") |> @config.env_vars({})
    for format in @formats.formats() { builder = builder |> @config.format(format) }
    builder = builder |> @conventions.add(@conventions.base("acme") |> @conventions.layouts |> @conventions.profiles(@profiles.Policy::new()))
    let error = try { ignore(@config.load(builder, tree)); "unexpected success" } catch {
      error => @debug.Debug::to_repr(error).to_string()
    }
    observations.push(error)
  }
  observations.join("\n")
}

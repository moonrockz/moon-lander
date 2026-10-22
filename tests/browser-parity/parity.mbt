///|
/// One explicit parity case: a builder with its run inputs and ordered sources,
/// and the complete file snapshot that the case loads.
pub struct Case {
  name : String
  builder : @config.ConfigBuilder
  files : Array[(String, String)]
  bind : Bool
}

///|
priv struct Server {
  host : String
  port : Int
} derive(FromJson)

///|
/// The shared cases: the complete core fixture, a parse failure and a binding
/// failure. Every target and the browser load these same inputs.
pub fn cases() -> Array[Case] raise @config.ConfigError {
  let toml = @config.builder()
    |> @config.format(@toml.format())
    |> @config.working_dir("/workspace")
    |> @config.env_vars({})
  [
    {
      name: "complete",
      builder: @fixture.builder(),
      files: @fixture.files(),
      bind: false,
    },
    {
      name: "parse",
      builder: toml |> @config.file("bad.toml"),
      files: [("/workspace/bad.toml", "[server]\nhost = 'x'\n[broken\n")],
      bind: false,
    },
    {
      name: "binding",
      builder: toml |> @config.file("defaults.toml") |> @config.file("wrong.toml"),
      files: [
        ("/workspace/defaults.toml", "[server]\nhost = 'defaults'\nport = 80\n"),
        ("/workspace/wrong.toml", "[server]\nhost = 42\n"),
      ],
      bind: true,
    },
  ]
}

///|
/// A digest of every case name, path and text, so a comparison proves that
/// both sides used the same fixture revision.
pub fn revision(cases : Array[Case]) -> String {
  let mut hash = 0x811c9dc5U
  for case in cases {
    let parts = [case.name]
    for file in case.files {
      parts.push(file.0)
      parts.push(file.1)
    }
    for part in parts {
      for char in part {
        hash = (hash ^ char.to_uint()) * 0x01000193U
      }
      hash = (hash ^ 0U) * 0x01000193U
    }
  }
  "fixture \{hash.to_string(radix=16)}"
}

///|
/// The observation of a loaded case: value, provenance and reports in source
/// order. A binding case also binds `server`, which can fail.
pub fn observe(case : Case, config : @config.Config) -> String {
  let lines = [
    "case \{case.name}",
    @debug.Debug::to_repr(config.value().to_ion()).to_string(),
    @debug.Debug::to_repr(config.provenance()).to_string(),
    @debug.Debug::to_repr(config.reports()).to_string(),
  ]
  if case.bind {
    lines.push(
      try {
        let server : Server = @config.bind(config, "server")
        "bound \{server.host}:\{server.port}"
      } catch {
        error => failure(error)
      },
    )
  }
  lines.join("\n")
}

///|
/// The observation of a failed case. Core errors keep all their fields.
pub fn failure(error : Error) -> String {
  let text = match error {
    @config.Parse(format~, origin~, message~, line~, column~) =>
      @debug.Debug::to_repr(
        @config.ConfigError::Parse(format~, origin~, message~, line~, column~),
      ).to_string()
    @config.Decode(failure~) =>
      @debug.Debug::to_repr(@config.ConfigError::Decode(failure~)).to_string()
    @config.FileNotFound(path~) =>
      @debug.Debug::to_repr(@config.ConfigError::FileNotFound(path~)).to_string()
    _ => "unexpected error"
  }
  "error \{text}"
}

///|
/// The reference observation from the pure loader with complete snapshots.
pub fn reference() -> String raise @config.ConfigError {
  let cases = cases()
  let lines = [revision(cases)]
  for case in cases {
    let mut tree = @config.FileTree::new(complete=true)
    for file in case.files {
      tree = tree.with_file(file.0, file.1)
    }
    lines.push(
      try {
        match @config.load(case.builder, tree) {
          Done(config) => observe(case, config)
          Need(_) => abort("a complete parity tree must not request files")
        }
      } catch {
        error => "case \{case.name}\n" + failure(error)
      },
    )
  }
  lines.join("\n")
}

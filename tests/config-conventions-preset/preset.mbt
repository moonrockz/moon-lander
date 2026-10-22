// The Morphir preset of the configuration conventions, made only from public
// parts (design D16). It is a test fixture: morphir-moonbit keeps its own
// production copy.

///|
/// The root directory of each case. Case paths that are relative join it.
pub let root : String = "/case"

///|
/// The Morphir convention set: the standard parts without local overrides,
/// the legacy `morphir.json` file, workspaces with Morphir's key paths, the
/// member-scope key `workspace.out_dir`, and the inherited filter for the
/// `project` and `workspace` tables. Environments stay off. The legacy
/// decoder keeps the parsed value; morphir-moonbit keeps its own translation
/// of the Elm manifest.
pub fn morphir() -> @conventions.Conventions {
  @conventions.app_dirs("morphir", prefix="MORPHIR", display="Morphir")
  |> @conventions.without(LocalOverrides)
  |> @conventions.legacy("morphir.json", format=@json5.format(), decode=value => value)
  |> @conventions.workspace
  |> @conventions.member_scope_keys(["workspace.out_dir"])
  |> @conventions.inherited_filter(["project", "workspace"])
}

///|
/// The registered formats of the preset: TOML, and YAML limited to `.yaml`.
/// The JSON5 format is only the format of the legacy part.
pub fn formats() -> Array[@config.Format] {
  [@toml.format(), { ..@yaml.format(), extensions: ["yaml"] }]
}

///|
/// One preset case: the files, the start directory, the discovery options,
/// the platform and the variable set of the run.
pub(all) struct Case {
  /// The name of the case.
  name : String
  /// Each file: a path, relative to `root` or absolute, and its text.
  files : Array[(String, String)]
  /// The working directory, relative to `root`; empty for `root`.
  start : String
  /// The explicit configuration file, relative to the working directory.
  config : String?
  /// Isolated mode.
  isolated : Bool
  /// The project selector.
  project : String?
  /// The platform of the run.
  platform : @config.Platform
  /// The variable set of the run.
  env_vars : Array[(String, String)]
}

///|
/// A case with the defaults: the start directory `root`, no explicit file,
/// isolated mode off, no selector, Linux, and `HOME=/home/user`.
pub fn Case::new(
  name : String,
  files : Array[(String, String)],
  start? : String = "",
  config? : String,
  isolated? : Bool = false,
  project? : String,
  platform? : @config.Platform = Linux,
  env_vars? : Array[(String, String)] = [("HOME", "/home/user")],
) -> Case {
  { name, files, start, config, isolated, project, platform, env_vars }
}

///|
/// `path` joined to `root` when it is relative.
pub fn at_root(path : String) -> String {
  if path.has_prefix("/") || (path.length() >= 3 && path[1:3] == ":/") {
    path
  } else if path.is_empty() {
    root
  } else {
    "\{root}/\{path}"
  }
}

///|
/// The builder of the case: the Morphir defaults, the preset, and the
/// environment-variable source with the reserved names `MORPHIR_HOME` and
/// `MORPHIR_LOG_DIR`, because the fixture does not use hosting.
pub fn builder(case : Case) -> @config.ConfigBuilder raise @config.ConfigError {
  let options = @conventions.DiscoveryOptions::new(
    config=match case.config {
      Some(path) => Explicit(path)
      None => Discover
    },
    isolated=case.isolated,
    project?=case.project,
  )
  formats().fold(
    init=@config.builder()
      |> @config.working_dir(at_root(case.start))
      |> @config.platform(case.platform)
      |> @config.env_vars(Map::from_array(case.env_vars)),
    (builder, format) => builder |> @config.format(format),
  )
  |> @config.defaults({
    "workspace": { "out_dir": ".morphir/out" },
    "ir": { "format_version": 4 },
  })
  |> @conventions.add(morphir(), options~)
  |> @config.env(prefix="MORPHIR", reserved=["MORPHIR_HOME", "MORPHIR_LOG_DIR"])
}

///|
/// A complete tree that holds the files of `files` and the listing of every
/// directory above them.
pub fn tree(files : Array[(String, String)]) -> @config.FileTree {
  let listings : Map[String, Array[@config.DirEntry]] = Map([])
  let mut tree = @config.FileTree::new(complete=true)
  for file in files {
    let (given, text) = file
    let path = at_root(given)
    tree = tree.with_file(path, text)
    let (prefix, rest) = if path.has_prefix("/") {
      ("/", path[1:].to_owned())
    } else {
      (path[:3].to_owned(), path[3:].to_owned())
    }
    let names = rest.split("/").map(name => name.to_owned()).collect()
    let mut dir = prefix
    for index, name in names {
      let entry : @config.DirEntry = {
        name,
        kind: if index == names.length() - 1 { File } else { Directory },
      }
      let entries = listings.get(dir).unwrap_or([])
      if !entries.contains(entry) {
        entries.push(entry)
      }
      listings[dir] = entries
      dir = if dir.has_suffix("/") { dir + name } else { "\{dir}/\{name}" }
    }
  }
  for dir, entries in listings {
    tree = tree.with_listing(dir, entries)
  }
  tree
}

///|
/// Load the case over its complete tree.
pub fn load(case : Case) -> @config.Config raise @config.ConfigError {
  match @config.load(builder(case), tree(case.files)) {
    Done(config) => config
    Need(_) => abort("a complete tree never asks for files")
  }
}

///|
/// A text observation of the case for snapshots: each report with its kind
/// name, priority, status, path, candidates and warnings, the effective value
/// as JSON, and the load warnings. A failed load gives its error message.
pub fn observe(case : Case) -> String {
  let config = try load(case) catch {
    error => return "error: \{error.message()}"
  }
  let lines = []
  for report in config.reports() {
    let status = match report.status {
      Loaded => "loaded"
      NotFound => "not-found"
      Skipped => "skipped"
    }
    lines.push(
      "\{report.kind.report_name()} \{report.priority} \{status} \{report.path.unwrap_or("-")}",
    )
    for candidate in report.candidates {
      lines.push("  candidate \{candidate}")
    }
    for warning in report.warnings {
      lines.push("  warning \{describe(warning)}")
    }
  }
  let value = try @config.show(config, Json) catch {
    error => "error: \{error.message()}"
  }
  lines.push("value \{value}")
  for warning in config.warnings() {
    lines.push("warning \{describe(warning)}")
  }
  lines.join("\n")
}

///|
fn describe(warning : @config.ConfigWarning) -> String {
  match warning {
    KeyRemoved(key, origin) =>
      "key-removed \{key} from \{origin.location.unwrap_or(origin.source)}"
    Note(message~, ..) => "note \{message}"
  }
}

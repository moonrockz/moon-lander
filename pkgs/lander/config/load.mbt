///|
/// The operating system of a run.
pub(all) enum Platform {
  Linux
  MacOs
  Windows
} derive(Eq, Debug)

///|
pub extend Platform with Eq::{equal, not_equal}

///|
pub extend Platform with @debug.Debug::{to_repr}

///|
/// The inputs that a source provider gets during a load. `platform` is `None`
/// when no host gave it, and `env_vars` is empty when the builder holds no
/// variable set.
pub(all) struct LoadContext {
  tree : FileTree
  platform : Platform?
  env_vars : Map[String, String]
  working_dir : String?
  formats : Array[Format]
}

///|
/// The sources that a provider gives, in merge order, and its warnings.
pub(all) struct Expansion {
  sources : Array[ConfigSource]
  warnings : Array[ConfigWarning]
}

///|
/// A step of the builder that gives sources during the load. `expand` gives
/// the file requests that it still needs, or its sources. With a complete tree
/// it must give its sources.
pub(all) struct SourceProvider {
  name : String
  expand : (LoadContext) -> LoadStep[Expansion] raise ConfigError
}

///|
/// Load the configuration from the builder and the file tree. This is pure: it
/// reads only its inputs and gives the same result on every target.
///
/// It runs each provider at its position, then checks the priorities over the
/// expanded list and raises `SourceOrder` when a priority decreases. When a
/// provider or a file source needs a path that the tree does not know, it
/// gives all such requests in one `Need`. Otherwise it parses, excludes, and
/// merges the sources in list order and gives `Done`.
pub fn load(
  builder : ConfigBuilder,
  tree : FileTree,
) -> LoadStep[Config] raise ConfigError {
  let context : LoadContext = {
    tree,
    platform: builder.platform,
    env_vars: builder.env_vars.map(vars => vars.copy()).unwrap_or(Map([])),
    working_dir: builder.working_dir,
    formats: builder.formats(),
  }
  let sources : Array[ConfigSource] = []
  let notes : Array[ConfigWarning] = []
  let needs : Array[FileRequest] = []
  let mut expanded = true
  for entry in builder.entries {
    match entry {
      Source(source) => sources.push(source)
      Provider(p) =>
        match (p.expand)(context) {
          Need(requests) => {
            add_needs(needs, requests)
            expanded = false
          }
          Done(expansion) => {
            sources.append(expansion.sources)
            notes.append(expansion.warnings)
          }
        }
    }
  }
  let priorities = if expanded { source_priorities(sources) } else { [] }
  let env_given = builder.env_vars is Some(_)
  let results = sources.map(source => resolve(source, context, needs, env_given))
  guard expanded && needs.is_empty() else { return Need(needs) }
  let secret_syntax = builder.secret_syntax
  let mut root = fields([])
  let provenance : Map[KeyPath, Array[Origin]] = Map([])
  let reports : Array[SourceReport] = []
  for index, source in sources {
    // A source gives `None` only with a request, and no request is open.
    guard results[index] is Some(result) else { continue }
    let origin : Origin = {
      kind: source.kind,
      source: source.name,
      priority: priorities[index],
      location: result.path,
    }
    let warnings : Array[ConfigWarning] = []
    let pieces = result.pieces.copy()
    for excluded in source.excluded {
      let (key, warn) = excluded
      let mut removed : Origin? = None
      for piece_index, piece in pieces {
        if remove_key(piece.0, key.names) is Some(rest) {
          pieces[piece_index] = (rest, piece.1)
          if removed is None {
            removed = Some({ ..origin, location: piece.1 })
          }
        }
      }
      if warn && removed is Some(removed_origin) {
        warnings.push(KeyRemoved(key, removed_origin))
      }
    }
    // Each piece has its own location, for example the variable of an
    // environment source.
    for piece in pieces {
      let piece_origin = piece.1.unwrap_or(source.name)
      check_secret_payloads(piece.0, piece_origin, secret_syntax)
      let previous = root
      root = merge(
        root,
        piece.0,
        policy=source.policy,
        key_policies=source.key_policies,
        source=source.name,
        secret_syntax=secret_syntax,
      )
      record_origins(
        provenance,
        piece.0,
        { ..origin, location: piece.1 },
        source_policy=source.policy,
        key_policies=source.key_policies,
        secret_syntax=secret_syntax,
        previous=previous,
      )
    }
    reports.push({
      kind: source.kind,
      name: source.name,
      priority: priorities[index],
      path: result.path,
      candidates: result.candidates,
      status: result.status,
      warnings,
    })
  }
  // The configuration holds no null field, and a record only for each leaf.
  root = without_nulls(root)
  let leaf_origins : Map[KeyPath, Array[Origin]] = Map([])
  for leaf in leaves(root, secret_syntax=secret_syntax) {
    if provenance.get(leaf.0) is Some(origins) {
      leaf_origins[leaf.0] = origins
    }
  }
  Done({ root, reports, notes, provenance: leaf_origins, secret_syntax, })
}

///|
/// What a load resolved for one source.
priv struct Resolved {
  /// The trees of the source in merge order, each with its location.
  pieces : Array[(ConfigValue, String?)]
  path : String?
  candidates : Array[String]
  status : SourceStatus
}

///|
/// Resolve the input of `source` over the tree. Give `None` and add to
/// `needs` when the tree does not know a path that the source needs.
fn resolve(
  source : ConfigSource,
  context : LoadContext,
  needs : Array[FileRequest],
  env_given : Bool,
) -> Resolved? raise ConfigError {
  match source.input {
    Value(value) =>
      Some({ pieces: [(value, None)], path: None, candidates: [], status: Loaded })
    NoInput => Some({ pieces: [], path: None, candidates: [], status: Skipped })
    Parsed(given, value) => {
      let path = join_path(context.working_dir, given)
      Some({ pieces: [(value, Some(path))], path: Some(path), candidates: [], status: Loaded })
    }
    Env(selection, prefix, reserved) =>
      match selection {
        Skip => Some({ pieces: [], path: None, candidates: [], status: Skipped })
        Explicit(vars) =>
          Some({
            pieces: env_pieces(vars, prefix, reserved),
            path: None,
            candidates: [],
            status: Loaded,
          })
        Discover if env_given =>
          Some({
            pieces: env_pieces(context.env_vars, prefix, reserved),
            path: None,
            candidates: [],
            status: Loaded,
          })
        Discover =>
          Some({ pieces: [], path: None, candidates: [], status: NotFound })
      }
    Path(given) => {
      let path = join_path(context.working_dir, given)
      let format = select_format(context.formats, path)
      match context.tree.file(path) {
        Found(text) =>
          Some({
            pieces: [(parse_with(format, path, text), Some(path))],
            path: Some(path),
            candidates: [],
            status: Loaded,
          })
        Missing => raise FileNotFound(path~)
        Unknown => {
          add_needs(needs, [ReadFile(path)])
          None
        }
      }
    }
    Candidates(given, display) => {
      let candidates : Array[String] = []
      for path in given {
        let joined = join_path(context.working_dir, path)
        if !candidates.contains(joined) {
          candidates.push(joined)
        }
      }
      let existing = []
      let mut unknown = false
      for candidate in candidates {
        match context.tree.is_file(candidate) {
          Found(true) => existing.push(candidate)
          Found(false) | Missing => ()
          Unknown => {
            add_needs(needs, [ListDir(split_path(candidate).0)])
            unknown = true
          }
        }
      }
      if existing.length() > 1 {
        raise Ambiguous(
          display~,
          location=common_dir(candidates),
          candidates=existing,
        )
      }
      guard !unknown else { return None }
      guard existing is [path] else {
        return Some({ pieces: [], path: None, candidates, status: NotFound })
      }
      let format = select_format(context.formats, path)
      match context.tree.file(path) {
        Found(text) =>
          Some({
            pieces: [(parse_with(format, path, text), Some(path))],
            path: Some(path),
            candidates,
            status: Loaded,
          })
        Missing => raise FileNotFound(path~)
        Unknown => {
          add_needs(needs, [ReadFile(path)])
          None
        }
      }
    }
  }
}

///|
fn parse_with(
  format : Format,
  path : String,
  text : String,
) -> ConfigValue raise ConfigError {
  let value = (format.parse)(text, path)
  value.check_root(path)
  value
}

///|
/// The display priority of each source. A source with no priority takes the
/// default of its kind and role. An in-memory source with no priority takes
/// the priority of the source before it, or 0 when it is first. A priority
/// lower than the one before it raises `SourceOrder`.
fn source_priorities(
  sources : Array[ConfigSource],
) -> Array[Int] raise ConfigError {
  let priorities = []
  for index, source in sources {
    let previous = if index > 0 { Some(priorities[index - 1]) } else { None }
    let priority = match (source.priority, source.kind) {
      (Some(priority), _) => priority
      (None, InMemory) => previous.unwrap_or(0)
      (None, kind) => default_priority(kind)
    }
    if previous is Some(previous_priority) && priority < previous_priority {
      raise SourceOrder(
        source=source.name,
        priority~,
        previous=sources[index - 1].name,
        previous_priority~,
      )
    }
    priorities.push(priority)
  }
  priorities
}

///|
/// The default display priority of a kind and role. An in-memory source has
/// no default; it follows the source before it.
fn default_priority(kind : SourceKind) -> Int {
  match kind {
    Defaults | InMemory => 0
    File(System) => 100
    File(Global) => 200
    File(Workspace | Explicit | Legacy) => 300
    File(Member) => 350
    File(EnvironmentFile) => 375
    File(LocalOverride) => 390
    File(UserOverride) => 400
    Environment => 600
    Overrides => 700
  }
}

///|
/// Add each request of `requests` that `needs` does not hold yet.
fn add_needs(needs : Array[FileRequest], requests : Array[FileRequest]) -> Unit {
  for request in requests {
    if !needs.contains(request) {
      needs.push(request)
    }
  }
}

///|
/// `path` joined to `dir` when `path` is relative. An absolute path starts with
/// `/` (also `//server/share`) or with a drive such as `C:/`.
fn join_path(dir : String?, path : String) -> String {
  guard dir is Some(dir) && !is_absolute(path) else { path }
  if dir.has_suffix("/") {
    dir + path
  } else {
    "\{dir}/\{path}"
  }
}

///|
fn is_absolute(path : String) -> Bool {
  path.has_prefix("/") || (path.length() >= 3 && path[1:3] == ":/")
}

///|
/// The longest directory that holds every path in `paths`.
fn common_dir(paths : Array[String]) -> String {
  guard paths is [first, .. rest] else { return "." }
  let mut dir = split_path(first).0
  for path in rest {
    while dir != "/" && dir != "." && !path.has_prefix(dir + "/") {
      dir = split_path(dir).0
    }
  }
  dir
}

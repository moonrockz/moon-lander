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
/// variable set. `working_dir` is the parsed working directory of the builder.
pub(all) struct LoadContext {
  tree : FileTree
  platform : Platform?
  env_vars : Map[String, String]
  working_dir : FileTreePath?
  formats : Array[Format]
}

///|
/// The sources that a provider gives, in merge order, and its warnings.
pub struct Expansion {
  priv sources : Array[ConfigSource]
  priv warnings : Array[ConfigWarning]
  priv profiles : ProfileResolution?
}

///|
/// Provider output. Omit `profiles` for an ordinary source provider.
pub fn Expansion::new(
  sources : Array[ConfigSource],
  warnings? : Array[ConfigWarning] = [],
  profiles? : ProfileResolution,
) -> Expansion {
  { sources: sources.copy(), warnings: warnings.copy(), profiles }
}

///|
/// A copy of this provider's sources, for a provider decorator.
pub fn Expansion::sources(self : Expansion) -> Array[ConfigSource] { self.sources.copy() }

///|
/// A copy of this provider's warnings, for a provider decorator.
pub fn Expansion::warnings(self : Expansion) -> Array[ConfigWarning] { self.warnings.copy() }

///|
/// The immutable optional resolution, for a provider decorator.
pub fn Expansion::profiles(self : Expansion) -> ProfileResolution? { self.profiles }

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
  let working_dir = match builder.working_dir {
    Some(text) => Some(input_path(text, builder.platform))
    None => None
  }
  let context : LoadContext = {
    tree,
    platform: builder.platform,
    env_vars: builder.env_vars.map(vars => vars.copy()).unwrap_or(Map([])),
    working_dir,
    formats: builder.formats(),
  }
  let sources : Array[ConfigSource] = []
  let notes : Array[ConfigWarning] = []
  let needs : Array[FileRequest] = []
  let mut expanded = true
  let mut profiles : ProfileState = Off
  let mut profile_provider : String? = None
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
            if expansion.profiles is Some(resolution) {
              if profile_provider is Some(previous) {
                raise Profile(failure=ProfileFailure::new(p.name, CompetingProviders(previous, p.name)))
              }
              profile_provider = Some(p.name)
              profiles = Resolved(resolution)
            }
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
    // Profile controls are reserved across the whole pipeline. Check each raw
    // source before application filters can remove a forbidden subtree.
    if profiles is Resolved(resolution) {
      for piece_index, piece in pieces {
        let key = KeyPath::parse("profiles")
        if piece.0.at(key.names) is Some(_) {
          let piece_origin = { ..origin, location: piece.1 }
          let authoritative = resolution.controls().any(control => match control {
            Control(control_origin, _) => control_origin == piece_origin
            _ => false
          })
          if !resolution.disabled() && !authoritative {
            raise Profile(failure=ProfileFailure::new("profiles", ForbiddenLocation, origin=Control(piece_origin, key)))
          }
          if remove_key(piece.0, key.names) is Some(rest) {
            pieces[piece_index] = (rest, piece.1)
          }
        }
      }
    }
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
  Done({ root, reports, notes, provenance: leaf_origins, secret_syntax, profiles })
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
      let path = source_path(context, given).to_string()
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
      let file = source_path(context, given)
      let path = file.to_string()
      let format = select_format(context.formats, path)
      match context.tree.file(file) {
        Found(text) =>
          Some({
            pieces: [(parse_with(format, path, text), Some(path))],
            path: Some(path),
            candidates: [],
            status: Loaded,
          })
        Missing => raise FileNotFound(path~)
        Unknown => {
          add_needs(needs, [ReadFile(file)])
          None
        }
      }
    }
    Candidates(given, display) => {
      let paths : Array[FileTreePath] = []
      for text in given {
        let path = source_path(context, text)
        if !paths.contains(path) {
          paths.push(path)
        }
      }
      let candidates = paths.map(path => path.to_string())
      let existing : Array[FileTreePath] = []
      let mut unknown = false
      for candidate in paths {
        match context.tree.is_file(candidate) {
          Found(true) => existing.push(candidate)
          Found(false) | Missing => ()
          Unknown => {
            add_needs(needs, [context.tree.file_request(candidate)])
            unknown = true
          }
        }
      }
      // The host answers for each candidate first, so the error of an
      // inaccessible candidate passes out even when two others exist.
      guard !unknown else { return None }
      if existing.length() > 1 {
        raise Ambiguous(
          display~,
          location=FileTreePath::common_dir(paths)
            .map(dir => dir.to_string())
            .unwrap_or("."),
          candidates=existing.map(path => path.to_string()),
        )
      }
      guard existing is [file] else {
        return Some({ pieces: [], path: None, candidates, status: NotFound })
      }
      let path = file.to_string()
      let format = select_format(context.formats, path)
      match context.tree.file(file) {
        Found(text) =>
          Some({
            pieces: [(parse_with(format, path, text), Some(path))],
            path: Some(path),
            candidates,
            status: Loaded,
          })
        Missing => raise FileNotFound(path~)
        Unknown => {
          add_needs(needs, [ReadFile(file)])
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
    File(ProfileFile(_)) => 380
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
/// The parsed form of the path text `text`. With a platform, the text is in
/// the native form of that platform, so `\` separators work on Windows.
fn input_path(
  text : String,
  platform : Platform?,
) -> FileTreePath raise ConfigError {
  match platform {
    Some(platform) => FileTreePath::from_native(text, platform)
    None => FileTreePath::parse(text)
  }
}

///|
/// The path of the source text `text`: parsed one time, and below the working
/// directory when it is relative.
fn source_path(
  context : LoadContext,
  text : String,
) -> FileTreePath raise ConfigError {
  let path = input_path(text, context.platform)
  match context.working_dir {
    Some(dir) => dir.resolve(path)
    None => path
  }
}

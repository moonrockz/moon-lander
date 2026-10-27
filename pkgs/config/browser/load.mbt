///|
/// Positive per-load bounds. Construct with limits().
pub struct Limits {
  priv entries : Int
  priv bytes : Int
  priv requests : Int
}

///|
pub fn limits(entries? : Int = 4096, bytes? : Int = 8388608, requests? : Int = 8192) -> Limits raise BrowserError {
  guard entries > 0 && bytes > 0 && requests > 0 else {
    raise InvalidMount(operation="limits", path="", reason="limits must be positive")
  }
  { entries, bytes, requests }
}

///|
/// The adapter capability that a backend needs.
fn Backend::capability(self : Backend) -> String {
  match self {
    Urls(_) => "urls"
    Files(_) => "files"
    Directory(_) => "directory"
  }
}

///|
/// Record absence, or raise the boundary error of a failed reply.
fn answer_missing(
  tree : @config.FileTree,
  path : @config.FileTreePath,
  kind : String,
  operation : String,
) -> @config.FileTree raise BrowserError {
  let text = path.to_string()
  match kind {
    "missing" => tree.with_missing(path)
    "aborted" => raise Aborted(operation~, path=text)
    "unsupported" => raise Unsupported(operation~, path=text)
    "permission" => raise PermissionDenied(operation~, path=text)
    _ => raise Io(operation~, path=text)
  }
}

///|
fn check_abort(signal : @js_async.AbortSignal, path : String) -> Unit raise BrowserError {
  if signal_aborted(signal) { raise Aborted(operation="load", path~) }
}

///|
fn select(mounts : Array[Mount], path : String) -> Mount raise BrowserError {
  validate_path(path, absolute=true, operation="load")
  for mount in mounts {
    if contains(mount.root, path) { return mount }
  }
  raise OutsideMount(operation="load", path~)
}

///|
fn request_path(request : @config.FileRequest) -> @config.FileTreePath {
  match request { ReadFile(path) | ListDir(path) => path }
}

///|
fn known(tree : @config.FileTree, request : @config.FileRequest) -> Bool {
  match request {
    ReadFile(path) => tree.file(path) is (Found(_) | Missing)
    ListDir(path) => tree.listing(path) is (Found(_) | Missing)
  }
}

///|
/// Load only from the supplied mounts. Omitted variables are empty, the working
/// directory defaults to the first root, and the explicit platform is preserved.
/// ConfigError values are not wrapped. Each call builds a fresh bounded snapshot.
#warnings("-67")
pub async fn load(
  builder : @config.ConfigBuilder,
  mounts : Array[Mount],
  limits? : Limits = { entries: 4096, bytes: 8388608, requests: 8192 },
  signal? : @js_async.AbortSignal,
) -> @config.Config raise {
  let mounts = mounts.copy()
  guard !mounts.is_empty() else {
    raise InvalidMount(operation="load", path="", reason="at least one mount is required")
  }
  let state : LoadState = {
    tree: @config.FileTree::new(),
    answered: Set([]),
    observed: Set([]),
    entries: limits.entries,
    bytes: limits.bytes,
    requests: limits.requests,
    signal: signal.unwrap_or(@js_async.AbortController::new().signal()),
  }
  for i, mount in mounts {
    for j = 0; j < i; j = j + 1 {
      if contains(mount.root, mounts[j].root) || contains(mounts[j].root, mount.root) {
        raise InvalidMount(operation="load", path=mount.root, reason="overlapping roots")
      }
    }
    guard adapter.supported(mount.backend.capability()) else {
      raise Unsupported(operation="load", path=mount.root)
    }
    let entries = mount.kinds.length() - 1
    guard entries <= state.entries else {
      raise LimitExceeded(operation="load", path=mount.root, limit="entries")
    }
    state.entries -= entries
  }
  check_abort(state.signal, "")
  let cwd = builder.given_working_dir().unwrap_or(mounts[0].root)
  ignore(select(mounts, cwd))
  let mut builder = builder |> @config.working_dir(cwd)
  if builder.given_env_vars() is None { builder = builder |> @config.env_vars(Map([])) }
  while true {
    check_abort(state.signal, "")
    match @config.load(builder, state.tree) {
      Done(config) => {
        check_abort(state.signal, "")
        return config
      }
      Need(requests) => {
        let pending : Array[(@config.FileRequest, Mount)] = []
        let batch : Set[@config.FileRequest] = Set([])
        for request in requests {
          // The browser rules are stricter than the file-tree path rules: the
          // text must also be a valid mount path.
          let mount = select(mounts, request_path(request).to_string())
          if !state.answered.contains(request) && !known(state.tree, request) && !batch.contains(request) {
            pending.push((request, mount))
            batch.add(request)
          }
        }
        guard !pending.is_empty() else {
          raise Protocol(operation="load", path=match requests {
            [first, ..] => request_path(first).to_string()
            [] => ""
          })
        }
        guard pending.length() <= state.requests - state.answered.length() else {
          raise LimitExceeded(operation="load", path=request_path(pending[0].0).to_string(), limit="requests")
        }
        for (request, mount) in pending {
          let path = request_path(request)
          let text = path.to_string()
          check_abort(state.signal, text)
          match (request, mount.backend) {
            (ListDir(_), Directory(handle)) => ignore(state.live_listing(mount.root, handle, path))
            (ListDir(_), _) =>
              match mount.listings.get(text) {
                Some(entries) => state.tree = state.tree.with_listing(path, entries)
                None => state.tree = state.tree.with_missing(path)
              }
            (ReadFile(_), Directory(handle)) => state.live_read(mount.root, handle, path)
            (ReadFile(_), Urls(base)) if mount.kinds.get(text) == Some(File) => {
              let relative = relative_to(mount.root, text)
              state.accept(path, @js_async.run_promise(task_signal => adapter.read(base, relative, state.bytes, state.signal, task_signal)))
            }
            (ReadFile(_), Files(files)) if mount.kinds.get(text) == Some(File) => {
              let file = files[relative_to(mount.root, text)]
              state.accept(path, @js_async.run_promise(task_signal => adapter.read_file(file, state.bytes, state.signal, task_signal)))
            }
            (ReadFile(_), _) => state.tree = state.tree.with_missing(path)
          }
          state.answered.add(request)
        }
      }
    }
  }
  abort("the load loop returns only a complete configuration")
}

///|
/// The mutable answers and remaining budgets of one load.
priv struct LoadState {
  mut tree : @config.FileTree
  answered : Set[@config.FileRequest]
  observed : Set[String]
  mut entries : Int
  mut bytes : Int
  requests : Int
  signal : @js_async.AbortSignal
}

///|
fn relative_to(root : String, path : String) -> String {
  if path == root {
    ""
  } else if root == "/" {
    path[1:].to_owned()
  } else {
    path[root.length() + 1:].to_owned()
  }
}

///|
/// Count each unique observed virtual entry once against the entry budget.
fn LoadState::observe(self : LoadState, path : String, operation : String, at : String) -> Unit raise BrowserError {
  if !self.observed.contains(path) {
    guard self.entries > 0 else { raise LimitExceeded(operation~, path=at, limit="entries") }
    self.observed.add(path)
    self.entries -= 1
  }
}

///|
/// Store a file reply, or record absence, or raise its boundary error.
fn LoadState::accept(
  self : LoadState,
  path : @config.FileTreePath,
  reply : Reply,
) -> Unit raise BrowserError {
  let text = path.to_string()
  check_abort(self.signal, text)
  match reply.kind() {
    "file" => {
      self.bytes -= reply.size()
      self.tree = self.tree.with_file(path, reply.text())
    }
    "http" => raise Http(operation="read", path=text, status=reply.status())
    "limit" => raise LimitExceeded(operation="read", path=text, limit="bytes")
    kind => self.tree = answer_missing(self.tree, path, kind, "read")
  }
}

///|
/// The exact listing of a live directory, or None when it is absent. Each
/// ancestor below the mount root is listed first, so every name is checked
/// against the names that the handle reports: an engine can resolve a name
/// without case on a case-insensitive host file system. Every listing is cached
/// for this load and counts toward the request and entry budgets.
async fn LoadState::live_listing(
  self : LoadState,
  root : String,
  handle : DirectoryHandle,
  path : @config.FileTreePath,
) -> Array[@config.DirEntry]? raise {
  match self.tree.listing(path) {
    Found(entries) => return Some(entries)
    Missing => return None
    Unknown => ()
  }
  let text = path.to_string()
  if text != root {
    guard path.parent() is Some(dir) && path.name() is Some(name) else {
      raise Protocol(operation="list", path=text)
    }
    let present = match self.live_listing(root, handle, dir) {
      Some(entries) => entries.iter().any(entry => entry.name == name && entry.kind == Directory)
      None => false
    }
    guard present else {
      self.tree = self.tree.with_missing(path)
      return None
    }
  }
  let request = @config.FileRequest::ListDir(path)
  if !self.answered.contains(request) {
    guard self.answered.length() < self.requests else {
      raise LimitExceeded(operation="list", path=text, limit="requests")
    }
  }
  check_abort(self.signal, text)
  // Children that this load already counted do not consume the budget again.
  let mut counted = 0
  for seen in self.observed {
    if seen.has_prefix(if text == "/" { "/" } else { text + "/" }) && parent(seen).0 == text { counted += 1 }
  }
  let reply = @js_async.run_promise(task_signal => adapter.list_directory(
    handle, relative_to(root, text), self.entries + counted, self.signal, task_signal,
  ))
  check_abort(self.signal, text)
  match reply.kind() {
    "listing" => {
      let entries : Array[@config.DirEntry] = []
      for i = 0; i < reply.count(); i = i + 1 {
        entries.push({ name: reply.name_at(i), kind: if reply.directory_at(i) { Directory } else { File } })
      }
      entries.sort_by((a, b) => a.name.lexical_compare(b.name))
      if text != root { self.observe(text, "list", text) }
      for entry in entries { self.observe(join(text, entry.name), "list", text) }
      self.tree = self.tree.with_listing(path, entries)
      self.answered.add(request)
      Some(entries)
    }
    "limit" => raise LimitExceeded(operation="list", path=text, limit="entries")
    kind => {
      self.tree = answer_missing(self.tree, path, kind, "list")
      self.answered.add(request)
      None
    }
  }
}

///|
/// Read a live file only when its exact name is a file in its parent listing.
async fn LoadState::live_read(
  self : LoadState,
  root : String,
  handle : DirectoryHandle,
  path : @config.FileTreePath,
) -> Unit raise {
  let text = path.to_string()
  let exists = match (path.parent(), path.name()) {
    (Some(dir), Some(name)) if text != root =>
      match self.live_listing(root, handle, dir) {
        Some(entries) => entries.iter().any(entry => entry.name == name && entry.kind == File)
        None => false
      }
    _ => false
  }
  guard exists else {
    self.tree = self.tree.with_missing(path)
    return
  }
  let reply = @js_async.run_promise(task_signal => adapter.read_directory_file(
    handle, relative_to(root, text), self.bytes, self.signal, task_signal,
  ))
  self.accept(path, reply)
}

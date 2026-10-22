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
  path : String,
  kind : String,
  operation : String,
) -> @config.FileTree raise BrowserError {
  match kind {
    "missing" => tree.with_missing(path)
    "aborted" => raise Aborted(operation~, path~)
    "unsupported" => raise Unsupported(operation~, path~)
    "permission" => raise PermissionDenied(operation~, path~)
    _ => raise Io(operation~, path~)
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
fn request_path(request : @config.FileRequest) -> String {
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
  let mut entry_budget = limits.entries
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
    guard entries <= entry_budget else {
      raise LimitExceeded(operation="load", path=mount.root, limit="entries")
    }
    entry_budget -= entries
  }
  let signal = signal.unwrap_or(@js_async.AbortController::new().signal())
  check_abort(signal, "")
  let cwd = builder.given_working_dir().unwrap_or(mounts[0].root)
  ignore(select(mounts, cwd))
  let mut builder = builder |> @config.working_dir(cwd)
  if builder.given_env_vars() is None { builder = builder |> @config.env_vars(Map([])) }
  let mut tree = @config.FileTree::new()
  let answered : Set[@config.FileRequest] = Set([])
  let mut byte_budget = limits.bytes
  let observed : Set[String] = Set([])
  while true {
    check_abort(signal, "")
    match @config.load(builder, tree) {
      Done(config) => {
        check_abort(signal, "")
        return config
      }
      Need(requests) => {
        let pending : Array[(@config.FileRequest, Mount)] = []
        let batch : Set[@config.FileRequest] = Set([])
        for request in requests {
          let mount = select(mounts, request_path(request))
          if !answered.contains(request) && !known(tree, request) && !batch.contains(request) {
            pending.push((request, mount))
            batch.add(request)
          }
        }
        guard !pending.is_empty() else {
          raise Protocol(operation="load", path=match requests { [first, ..] => request_path(first); [] => "" })
        }
        guard pending.length() <= limits.requests - answered.length() else {
          raise LimitExceeded(operation="load", path=request_path(pending[0].0), limit="requests")
        }
        for (request, mount) in pending {
          let path = request_path(request)
          check_abort(signal, path)
          let relative = if path == mount.root {
            ""
          } else if mount.root == "/" {
            path[1:].to_owned()
          } else {
            path[mount.root.length() + 1:].to_owned()
          }
          match (request, mount.backend) {
            (ListDir(_), Directory(handle)) => {
              let reply = @js_async.run_promise(task_signal => adapter.list_directory(handle, relative, signal, task_signal))
              check_abort(signal, path)
              match reply.kind() {
                "listing" => {
                  let entries : Array[@config.DirEntry] = []
                  for i = 0; i < reply.count(); i = i + 1 {
                    let name = reply.name_at(i)
                    entries.push({ name, kind: if reply.directory_at(i) { Directory } else { File } })
                  }
                  entries.sort_by((a, b) => a.name.lexical_compare(b.name))
                  let seen = if path == mount.root { [] } else { [path] }
                  for entry in entries { seen.push(join(path, entry.name)) }
                  for entry_path in seen {
                    if !observed.contains(entry_path) {
                      guard entry_budget > 0 else {
                        raise LimitExceeded(operation="list", path~, limit="entries")
                      }
                      observed.add(entry_path)
                      entry_budget -= 1
                    }
                  }
                  tree = tree.with_listing(path, entries)
                }
                kind => tree = answer_missing(tree, path, kind, "list")
              }
            }
            (ListDir(_), _) =>
              match mount.listings.get(path) {
                Some(entries) => tree = tree.with_listing(path, entries)
                None => tree = tree.with_missing(path)
              }
            (ReadFile(_), Directory(_)) if path == mount.root => tree = tree.with_missing(path)
            (ReadFile(_), backend) if backend is Directory(_) || mount.kinds.get(path) == Some(File) => {
              let reply = @js_async.run_promise(task_signal => match mount.backend {
                Urls(base) => adapter.read(base, relative, byte_budget, signal, task_signal)
                Files(files) => adapter.read_file(files[relative], byte_budget, signal, task_signal)
                Directory(handle) => adapter.read_directory_file(handle, relative, byte_budget, signal, task_signal)
              })
              check_abort(signal, path)
              match reply.kind() {
                "file" => {
                  if mount.backend is Directory(_) && !observed.contains(path) {
                    guard entry_budget > 0 else {
                      raise LimitExceeded(operation="read", path~, limit="entries")
                    }
                    observed.add(path)
                    entry_budget -= 1
                  }
                  byte_budget -= reply.size()
                  tree = tree.with_file(path, reply.text())
                }
                "http" => raise Http(operation="read", path~, status=reply.status())
                "limit" => raise LimitExceeded(operation="read", path~, limit="bytes")
                kind => tree = answer_missing(tree, path, kind, "read")
              }
            }
            (ReadFile(_), _) => tree = tree.with_missing(path)
          }
          answered.add(request)
        }
      }
    }
  }
  abort("the load loop returns only a complete configuration")
}

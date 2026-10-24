///|
/// An explicit OPFS store for configuration text. Its files live in one
/// application namespace below a fixed library-owned OPFS directory. Opening,
/// writing and removing are caller actions; a load never writes a store.
pub struct Store {
  priv name : String
  priv root : String
  priv handle : DirectoryHandle
}

///|
/// The application namespace of the store. (`namespace` is a reserved word.)
pub fn Store::name(self : Store) -> String {
  self.name
}

///|
/// The virtual root of the store's read mount.
pub fn Store::root(self : Store) -> String {
  self.root
}

///|
/// The read-only mount of the store at its virtual root. It uses the directory
/// backend: each load reads the current stored files.
pub fn Store::mount(self : Store) -> Mount {
  {
    root: self.root,
    backend: Directory(self.handle),
    kinds: Map::from_array([(self.root, Directory)]),
    listings: Map([]),
  }
}

///|
#external
priv type StoreReply

///|
extern "js" fn BrowserAdapter::open_store(
  self : BrowserAdapter,
  name : String,
) -> @js_async.Promise[StoreReply] =
  #|(adapter, name) => adapter.openStore(name)

///|
extern "js" fn BrowserAdapter::write_text(
  self : BrowserAdapter,
  store : DirectoryHandle,
  relative : String,
  text : String,
) -> @js_async.Promise[StoreReply] =
  #|(adapter, store, relative, text) => adapter.writeText(store, relative, text)

///|
extern "js" fn BrowserAdapter::remove_file(
  self : BrowserAdapter,
  store : DirectoryHandle,
  relative : String,
) -> @js_async.Promise[StoreReply] =
  #|(adapter, store, relative) => adapter.removeFile(store, relative)

///|
extern "js" fn StoreReply::kind(self : StoreReply) -> String =
  #|reply => reply.kind

///|
extern "js" fn StoreReply::handle(self : StoreReply) -> DirectoryHandle =
  #|reply => reply.handle

///|
extern "js" fn StoreReply::removed(self : StoreReply) -> Bool =
  #|reply => reply.removed === true

///|
/// Raise the boundary error of a failed storage reply. No failure falls back
/// to localStorage, IndexedDB or another store.
fn storage_failure(
  kind : String,
  operation : String,
  path : String,
) -> BrowserError {
  match kind {
    "unsupported" => Unsupported(operation~, path~)
    "permission" => PermissionDenied(operation~, path~)
    "quota" => LimitExceeded(operation~, path~, limit="quota")
    "conflict" =>
      InvalidPath(
        operation~,
        reason="the host maps the name to an entry with another exact name",
      )
    _ => Io(operation~, path~)
  }
}

///|
/// Open the OPFS store of one application namespace, `name`, and give its read
/// mount the virtual `root`. The namespace is one path segment. Both are validated
/// before any storage access. The root does not change the backing namespace:
/// reopening a namespace at another root reads the same files.
pub async fn open_store(
  name : String,
  root~ : String,
) -> Store raise BrowserError {
  let operation = "open_store"
  validate_path(root, absolute=true, operation~)
  validate_path(name, absolute=false, operation~)
  guard !name.contains("/") else {
    raise InvalidPath(operation~, reason="a namespace is one path segment")
  }
  let reply = @js_async.run_promise(_ => adapter.open_store(name)) catch {
    _ => raise Io(operation~, path=root)
  }
  guard reply.kind() == "store" else {
    raise storage_failure(reply.kind(), operation, root)
  }
  { name, root, handle: reply.handle() }
}

///|
/// Write `text` to a relative file inside the store. Parent directories are
/// created only inside the store. Success means that the write and its close
/// completed. A failed write or close raises; quota failure raises
/// `LimitExceeded` with the `quota` limit. This is one file, not a transaction.
/// A write never replaces an entry with another exact name: when the host maps
/// a segment or the file name to such an entry, as a case-insensitive file
/// system can, the write raises `InvalidPath` and changes nothing.
pub async fn write_text(
  store : Store,
  path : String,
  text : String,
) -> Unit raise BrowserError {
  let operation = "write_text"
  validate_path(path, absolute=false, operation~)
  let mounted = join(store.root, path)
  let reply = @js_async.run_promise(_ => adapter.write_text(
    store.handle,
    path,
    text,
  )) catch {
    _ => raise Io(operation~, path=mounted)
  }
  guard reply.kind() == "written" else {
    raise storage_failure(reply.kind(), operation, mounted)
  }
}

///|
/// Remove one named file inside the store. Give `true` when a file was
/// removed and `false` when it was absent. A directory is never removed.
pub async fn remove(store : Store, path : String) -> Bool raise BrowserError {
  let operation = "remove"
  validate_path(path, absolute=false, operation~)
  let mounted = join(store.root, path)
  let reply = @js_async.run_promise(_ => adapter.remove_file(store.handle, path)) catch {
    _ => raise Io(operation~, path=mounted)
  }
  guard reply.kind() == "removed" else {
    raise storage_failure(reply.kind(), operation, mounted)
  }
  reply.removed()
}

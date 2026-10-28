///|
/// An open log file: a Node.js `FileHandle`.
#external
priv type FileHandle

///|
#external
priv type Done

///|
extern "js" fn Done::error(self : Done) -> String =
  #|(done) => done.error

///|
#external
priv type Opened

///|
extern "js" fn Opened::error(self : Opened) -> String =
  #|(opened) => opened.error

///|
extern "js" fn Opened::handle(self : Opened) -> FileHandle =
  #|(opened) => opened.handle

///|
extern "js" fn Opened::size(self : Opened) -> Double =
  #|(opened) => opened.size

///|
#external
priv type Written

///|
extern "js" fn Written::error(self : Written) -> String =
  #|(written) => written.error

///|
extern "js" fn Written::written(self : Written) -> Double =
  #|(written) => written.written

///|
#external
priv type Listing

///|
extern "js" fn Listing::error(self : Listing) -> String =
  #|(listing) => listing.error

///|
extern "js" fn Listing::names(self : Listing) -> FixedArray[String] =
  #|(listing) => listing.names

///|
extern "js" fn Listing::sizes(self : Listing) -> FixedArray[Double] =
  #|(listing) => listing.sizes

///|
extern "js" fn Listing::regular(self : Listing) -> FixedArray[Bool] =
  #|(listing) => listing.regular

///|
extern "js" fn NodeAdapter::make_directory(
  self : NodeAdapter,
  path : String,
) -> @js_async.Promise[Done] =
  #|(adapter, path) => adapter.makeDirectory(path)

///|
extern "js" fn NodeAdapter::create_exclusive(
  self : NodeAdapter,
  path : String,
) -> @js_async.Promise[Done] =
  #|(adapter, path) => adapter.createExclusive(path)

///|
extern "js" fn NodeAdapter::remove_file(
  self : NodeAdapter,
  path : String,
) -> @js_async.Promise[Done] =
  #|(adapter, path) => adapter.removeFile(path)

///|
extern "js" fn NodeAdapter::open_append(
  self : NodeAdapter,
  path : String,
) -> @js_async.Promise[Opened] =
  #|(adapter, path) => adapter.openAppend(path)

///|
extern "js" fn NodeAdapter::write_file(
  self : NodeAdapter,
  handle : FileHandle,
  text : String,
) -> @js_async.Promise[Written] =
  #|(adapter, handle, text) => adapter.writeFile(handle, text)

///|
extern "js" fn NodeAdapter::close_file(
  self : NodeAdapter,
  handle : FileHandle,
) -> @js_async.Promise[Done] =
  #|(adapter, handle) => adapter.closeFile(handle)

///|
extern "js" fn NodeAdapter::list_directory(
  self : NodeAdapter,
  path : String,
) -> @js_async.Promise[Listing] =
  #|(adapter, path) => adapter.listDirectory(path)

///|
/// The error of a reply, or `None` for success.
fn reply_error(text : String) -> String? {
  if text.is_empty() {
    None
  } else {
    Some(text)
  }
}

///|
/// Create the directory and its missing parents.
async fn make_directory(path : String) -> String? {
  let done = node.make_directory(path).wait() catch {
    error => return Some(failure_text(error))
  }
  reply_error(done.error())
}

///|
/// Create the file at `path` only when no entry is there (`wx`).
async fn create_exclusive(path : String) -> String? {
  let done = node.create_exclusive(path).wait() catch {
    error => return Some(failure_text(error))
  }
  reply_error(done.error())
}

///|
/// Delete the file at `path`.
async fn remove_file(path : String) -> String? {
  let done = node.remove_file(path).wait() catch {
    error => return Some(failure_text(error))
  }
  reply_error(done.error())
}

///|
/// Open `path` to append (`a`), and create it when it is missing.
async fn open_append(path : String) -> Result[(FileHandle, Int64), String] {
  let opened = node.open_append(path).wait() catch {
    error => return Err(failure_text(error))
  }
  match reply_error(opened.error()) {
    Some(error) => Err(error)
    None => Ok((opened.handle(), opened.size().to_int64()))
  }
}

///|
/// Write all of `text`, and wait for the OS to accept it.
async fn write_handle(handle : FileHandle, text : String) -> String? {
  let written = node.write_file(handle, text).wait() catch {
    error => return Some(failure_text(error))
  }
  match reply_error(written.error()) {
    Some(error) if written.written() > 0.0 =>
      Some("\{error} (after \{written.written().to_int64()} bytes)")
    other => other
  }
}

///|
/// Close the file.
async fn close_handle(handle : FileHandle) -> String? {
  let done = node.close_file(handle).wait() catch {
    error => return Some(failure_text(error))
  }
  reply_error(done.error())
}

///|
/// The entries of `path` with their size, and whether each is a regular file.
async fn list_directory(path : String) -> Result[Array[@rolling.ListedFile], String] {
  let listing = node.list_directory(path).wait() catch {
    error => return Err(failure_text(error))
  }
  if reply_error(listing.error()) is Some(error) {
    return Err(error)
  }
  let names = listing.names()
  let sizes = listing.sizes()
  let regular = listing.regular()
  let listed = []
  for i in 0..<names.length() {
    listed.push(listed_file(names[i], sizes[i].to_int64(), regular[i]))
  }
  Ok(listed)
}

///|
/// An open log file.
priv struct FileHandle {
  file : @fs.File
}

///|
/// Create the directory and its missing parents. It gives the error text when
/// this fails, else `None`.
async fn make_directory(path : String) -> String? {
  @fs.mkdir(path, recursive=true, allow_exist=true) catch {
    error => return Some(failure_text(error))
  }
  None
}

///|
/// Create the file at `path` only when no entry is there. It gives the error
/// text when the entry exists or the create fails, else `None`.
async fn create_exclusive(path : String) -> String? {
  let file = @fs.open(path, mode=WriteOnly, create_mode=CreateNew) catch {
    error => return Some(failure_text(error))
  }
  file.close()
  None
}

///|
/// Delete the file at `path`. It gives the error text when this fails.
async fn remove_file(path : String) -> String? {
  @fs.remove(path) catch {
    error => return Some(failure_text(error))
  }
  None
}

///|
/// Open `path` to append, and create it when it is missing. The file is never
/// truncated. It gives the handle and the current size of the file.
async fn open_append(path : String) -> Result[(FileHandle, Int64), String] {
  let file = @fs.open(path, mode=WriteOnly, append=true, create_mode=OpenOrCreate) catch {
    error => return Err(failure_text(error))
  }
  let size = file.size() catch {
    error => {
      file.close()
      return Err(failure_text(error))
    }
  }
  Ok(({ file, }, size))
}

///|
/// Write all of `text`. It gives the error text when the write fails.
async fn write_handle(handle : FileHandle, text : String) -> String? {
  handle.file.write(text) catch {
    error => return Some(failure_text(error))
  }
  None
}

///|
/// Close the file. It gives the error text when this fails. The pinned
/// `moonbitlang/async` closes a file without an error result.
// The js version waits for the close, so both versions are async (67).
#warnings("-67")
async fn close_handle(handle : FileHandle) -> String? {
  handle.file.close()
  None
}

///|
/// The entries of `path`, with their size, and whether each is a regular file.
/// Links are not followed, so a link is not a regular file. An entry that
/// disappears while the listing runs is left out.
async fn list_directory(path : String) -> Result[Array[@rolling.ListedFile], String] {
  let names = @fs.readdir(path, include_hidden=true, sort=true) catch {
    error => return Err(failure_text(error))
  }
  let listed = []
  for name in names {
    if inspect_entry(path + "/" + name) is Some((size, regular)) {
      listed.push(@rolling.ListedFile::{ name, size, regular })
    }
  }
  Ok(listed)
}

///|
/// The size of the entry at `path` and whether it is a regular file, without
/// following a link. As in the Node.js adapter, an entry that disappeared gives
/// `None`, and an entry that cannot be inspected is not regular.
async fn inspect_entry(path : String) -> (Int64, Bool)? {
  try {
    guard @fs.kind(path, follow_symlink=false) is Regular else {
      return Some((0L, false))
    }
    Some((@fs.file_size(path), true))
  } catch {
    error => {
      ignore(failure_text(error))
      if @fs.exists(path) {
        Some((0L, false))
      } else {
        None
      }
    }
  }
}

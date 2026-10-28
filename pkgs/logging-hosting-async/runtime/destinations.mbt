///|
/// The color hints of the process, read once for each console destination.
fn process_color_hints() -> @sinks.ColorHints {
  @sinks.ColorHints::from_env(
    no_color=@env.get_env_var("NO_COLOR"),
    term=@env.get_env_var("TERM"),
  )
}

///|
/// The destination of a console sink. It selects its theme one time, from the
/// color mode, the terminal of the stream and the environment hints.
fn console_destination(console : @sinks.ConsoleSink) -> Sink {
  let stream = console.stream()
  let target : @sinks.SinkTarget = Console(stream)
  let theme = console.render_theme(
    console_capability(stream),
    process_color_hints(),
  )
  Sink::new(
    target,
    console.minimum(),
    record => @formatting.format_console(record, theme),
    {
      write: async fn(text) {
        write_console(stream, text).map(detail => @sinks.SinkFailure::new(
          Write, target, detail,
        ))
      },
      close: fn() { [] },
    },
  )
}

///|
/// An open log file, as the file writer sees it.
priv struct OpenFile {
  /// Append all of the text. It gives the error text when the write fails.
  write : async (String) -> String?
  /// Close the file. It gives the error text when this fails.
  close : async () -> String?
}

///|
/// The file system operations of the file writer. Each gives the error text
/// of a failure. The tests give an in-memory file system.
priv struct FileIo {
  make_directory : async (String) -> String?
  create_exclusive : async (String) -> String?
  remove_file : async (String) -> String?
  open_append : async (String) -> Result[(OpenFile, @rolling.ByteCount), String]
  list_directory : async (String) -> Result[Array[@rolling.ListedFile], String]
}

///|
/// The file system of the process: `moonbitlang/async` on native and the
/// Node.js adapter on js.
fn system_io() -> FileIo {
  {
    make_directory,
    create_exclusive,
    remove_file,
    open_append: async fn(path) {
      match open_append(path) {
        Ok((handle, size)) => {
          let file : OpenFile = {
            write: async fn(text) { write_handle(handle, text) },
            close: async fn() { close_handle(handle) },
          }
          // Parse the size from the file system once, at this boundary.
          let count = @rolling.ByteCount::of(size) catch {
            _ => {
              ignore(close_handle(handle))
              return Err("the file system gave the size \{size}")
            }
          }
          Ok((file, count))
        }
        Err(detail) => Err(detail)
      }
    },
    list_directory,
  }
}

///|
/// The writer state of one file set. It opens nothing before the first
/// payload, and it changes its rolling state only after an I/O step succeeds.
priv struct FileOutput {
  sink : @sinks.FileSink
  target : @sinks.SinkTarget
  clock : () -> @formatting.LogTimestamp
  warn : (@sinks.SinkFailure) -> Unit
  io : FileIo
  mut owned : Bool
  mut state : @rolling.RollingState
  mut handle : OpenFile?
}

///|
fn FileOutput::new(
  sink : @sinks.FileSink,
  clock : () -> @formatting.LogTimestamp,
  warn : (@sinks.SinkFailure) -> Unit,
  io : FileIo,
) -> FileOutput {
  {
    sink,
    target: sink.target(),
    clock,
    warn,
    io,
    owned: false,
    state: @rolling.RollingState::new(sink.files()),
    handle: None,
  }
}

///|
fn FileOutput::failure(
  self : FileOutput,
  operation : @sinks.SinkOperation,
  subject? : String,
  detail : String,
) -> @sinks.SinkFailure {
  @sinks.SinkFailure::new(operation, self.target, subject?, detail)
}

///|
/// Create the directory and the ownership marker of the file set, one time.
/// An existing marker, also one that a crash left, fails: the writer never
/// removes a marker that it did not create.
async fn FileOutput::acquire(self : FileOutput) -> @sinks.SinkFailure? {
  guard !self.owned else { return None }
  let directory = self.sink.directory().path().to_string()
  if (self.io.make_directory)(directory) is Some(detail) {
    return Some(self.failure(CreateDirectory, subject=directory, detail))
  }
  let marker = self.sink.marker_path()
  if (self.io.create_exclusive)(marker) is Some(detail) {
    return Some(self.failure(AcquireOwnership, subject=marker, detail))
  }
  self.owned = true
  None
}

///|
/// Delete the old files that the retention selects, after `active` opened. A
/// failure here is reported and does not stop the destination.
async fn FileOutput::retain(
  self : FileOutput,
  active : @rolling.LogFileName,
) -> Unit {
  guard self.sink.retention() is KeepNewest(_) else { return }
  let directory = self.sink.directory()
  let listing = match (self.io.list_directory)(directory.path().to_string()) {
    Ok(listing) => listing
    Err(detail) => {
      (self.warn)(
        self.failure(
          ListDirectory,
          subject=directory.path().to_string(),
          detail,
        ),
      )
      return
    }
  }
  for
    name in self.sink.files().retention(self.sink.retention(), listing, active) {
    if (self.io.remove_file)(directory.file(name)) is Some(detail) {
      (self.warn)(self.failure(DeleteOldFile, subject=name.to_string(), detail))
    }
  }
}

///|
/// Open `name` to append, record its size in the rolling state, and run the
/// retention.
async fn FileOutput::open(
  self : FileOutput,
  name : @rolling.LogFileName,
) -> @sinks.SinkFailure? {
  let path = self.sink.directory().file(name)
  match (self.io.open_append)(path) {
    Err(detail) => Some(self.failure(OpenFile, subject=name.to_string(), detail))
    Ok((handle, size)) => {
      self.handle = Some(handle)
      self.state = self.state.opened(name, size)
      self.retain(name)
      None
    }
  }
}

///|
/// Write one payload: acquire the file set, follow the rolling plan, then
/// append the whole payload.
async fn FileOutput::write(
  self : FileOutput,
  text : String,
) -> @sinks.SinkFailure? {
  if self.acquire() is Some(failure) {
    return Some(failure)
  }
  let bytes = @rolling.ByteCount::of_text(text)
  // Read the writer clock once for this record.
  let now = (self.clock)()
  let listing = if self.state.needs_listing(now) {
    let directory = self.sink.directory().path().to_string()
    match (self.io.list_directory)(directory) {
      Ok(listing) => listing
      Err(detail) =>
        return Some(self.failure(ListDirectory, subject=directory, detail))
    }
  } else {
    []
  }
  let plan = self.state.plan(now, bytes, listing) catch {
    error => return Some(self.failure(PlanFile, error_text(error)))
  }
  match plan {
    Append(_) => ()
    Open(name, ..) =>
      if self.open(name) is Some(failure) {
        return Some(failure)
      }
    Roll(name, ..) => {
      if self.handle is Some(handle) {
        self.handle = None
        if (handle.close)() is Some(detail) {
          return Some(self.failure(CloseFile, detail))
        }
      }
      if self.open(name) is Some(failure) {
        return Some(failure)
      }
    }
  }
  guard self.handle is Some(handle) else {
    return Some(self.failure(Write, "no file is open"))
  }
  if (handle.write)(text) is Some(detail) {
    return Some(self.failure(Write, detail))
  }
  self.state = self.state.wrote(bytes)
  None
}

///|
/// Close the open file, then delete the ownership marker that this writer
/// created.
async fn FileOutput::close(self : FileOutput) -> Array[@sinks.SinkFailure] {
  let failures = []
  if self.handle is Some(handle) {
    self.handle = None
    if (handle.close)() is Some(detail) {
      failures.push(self.failure(CloseFile, detail))
    }
  }
  if self.owned {
    // The writer owns the marker until the delete succeeds, so a close that is
    // cut short can try again.
    let marker = self.sink.marker_path()
    match (self.io.remove_file)(marker) {
      None => self.owned = false
      Some(detail) =>
        failures.push(self.failure(ReleaseOwnership, subject=marker, detail))
    }
  }
  failures
}

///|
/// The destination of a file sink.
fn file_destination(
  file : @sinks.FileSink,
  clock : () -> @formatting.LogTimestamp,
  warn : (@sinks.SinkFailure) -> Unit,
  io? : FileIo = system_io(),
) -> Sink {
  let output = FileOutput::new(file, clock, warn, io)
  let render : (@formatting.LogRecord) -> String = match file.files().format() {
    Text => @formatting.format_text
    JsonLines => match file.json_properties() {
      OrderedArray => @formatting.format_json_line
      NamedObject => @formatting.format_json_object_line
    }
  }
  Sink::new(output.target, file.minimum(), render, {
    write: async fn(text) { output.write(text) },
    close: async fn() { output.close() },
  })
}

///|
/// The destinations of `settings`: the console first, then the files in order.
fn production_sinks(
  settings : @sinks.SessionSettings,
  clock : () -> @formatting.LogTimestamp,
  warn : (Int, @sinks.SinkFailure) -> Unit,
) -> Array[Sink] {
  let sinks = []
  if settings.console() is Some(console) {
    sinks.push(console_destination(console))
  }
  for file in settings.files() {
    let index = sinks.length()
    sinks.push(file_destination(file, clock, failure => warn(index, failure)))
  }
  sinks
}

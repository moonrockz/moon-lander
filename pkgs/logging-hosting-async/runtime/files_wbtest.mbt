///|
priv enum FakeKind {
  Regular
  Folder
  Link
}

///|
priv struct FakeEntry {
  kind : FakeKind
  content : StringBuilder
}

///|
/// An in-memory file system for the file writer, with failures on request.
priv struct FakeFs {
  entries : Map[String, FakeEntry]
  mut fail_mkdir : String?
  fail_open : Map[String, String]
  fail_remove : Map[String, String]
  /// The bytes that writes can still add before the disk is full.
  mut write_budget : Int?
  mut write_calls : Int
}

///|
fn FakeFs::new() -> FakeFs {
  {
    entries: {},
    fail_mkdir: None,
    fail_open: {},
    fail_remove: {},
    write_budget: None,
    write_calls: 0,
  }
}

///|
fn FakeFs::add(self : FakeFs, path : String, kind : FakeKind, text? : String = "") -> Unit {
  let content = StringBuilder()
  content.write_string(text)
  self.entries[path] = { kind, content }
}

///|
fn FakeFs::text(self : FakeFs, path : String) -> String? {
  self.entries.get(path).map(entry => entry.content.to_string())
}

///|
fn FakeFs::names(self : FakeFs, dir : String) -> Array[String] {
  let names = []
  for path, _ in self.entries {
    if path.strip_prefix(dir + "/") is Some(rest) && !rest.contains("/") {
      names.push(rest.to_owned())
    }
  }
  // `String` compares by length first; a listing reads in character order.
  names.sort_by(lexical)
  names
}

///|
fn lexical(a : String, b : String) -> Int {
  let left = a.to_array()
  let right = b.to_array()
  for i in 0..<@cmp.minimum(left.length(), right.length()) {
    if left[i] != right[i] {
      return left[i].compare(right[i])
    }
  }
  left.length().compare(right.length())
}

///|
fn base_name(path : String) -> String {
  match path.rev_find("/") {
    Some(at) => path[at + 1:].to_owned()
    None => path
  }
}

///|
fn FakeFs::io(self : FakeFs) -> FileIo {
  {
    make_directory: fn(path) {
      if self.fail_mkdir is Some(detail) {
        return Some(detail)
      }
      if !self.entries.contains(path) {
        self.add(path, Folder)
      }
      None
    },
    create_exclusive: fn(path) {
      if self.entries.contains(path) {
        return Some("EEXIST: file already exists")
      }
      self.add(path, Regular)
      None
    },
    remove_file: fn(path) {
      if self.fail_remove.get(base_name(path)) is Some(detail) {
        return Some(detail)
      }
      guard self.entries.contains(path) else { return Some("ENOENT") }
      self.entries.remove(path)
      None
    },
    open_append: fn(path) {
      if self.fail_open.get(base_name(path)) is Some(detail) {
        return Err(detail)
      }
      match self.entries.get(path) {
        Some({ kind: Folder | Link, .. }) => return Err("EISDIR")
        Some(_) => ()
        None => self.add(path, Regular)
      }
      let entry = self.entries.get(path).unwrap()
      let file : OpenFile = {
        write: fn(text) {
          self.write_calls += 1
          match self.write_budget {
            Some(budget) if budget < text.length() => {
              entry.content.write_string(text.view(end_offset=budget).to_owned())
              self.write_budget = Some(0)
              Some("ENOSPC: no space left on device (after \{budget} bytes)")
            }
            Some(budget) => {
              entry.content.write_string(text)
              self.write_budget = Some(budget - text.length())
              None
            }
            None => {
              entry.content.write_string(text)
              None
            }
          }
        },
        close: fn() { None },
      }
      Ok((file, @rolling.ByteCount::of_text(entry.content.to_string())))
    },
    list_directory: fn(path) {
      guard self.entries.get(path) is Some({ kind: Folder, .. }) else {
        return Err("ENOENT: no such directory")
      }
      Ok(
        self
        .names(path)
        .map(name => {
          let entry = self.entries.get(path + "/" + name).unwrap()
          @rolling.ListedFile::{
            name,
            size: @rolling.ByteCount::of_text(entry.content.to_string()),
            regular: entry.kind is Regular,
          }
        }),
      )
    },
  }
}

///|
fn logs() -> @sinks.LogDirectory {
  @sinks.LogDirectory::from_absolute(@lander_core.AbsolutePath::parse("/logs")) catch {
    _ => abort("a valid directory")
  }
}

///|
fn acme() -> @rolling.LogFileStem {
  @rolling.LogFileStem::parse("acme") catch {
    _ => abort("a valid stem")
  }
}

///|
/// Run `body` with a session of file destinations over `fs`.
async fn[X] with_files(
  fs : FakeFs,
  files : Array[@sinks.FileSink],
  body : async (Session) -> X,
  clock? : () -> @formatting.LogTimestamp = sample_time,
) -> X {
  let settings = @sinks.SessionSettings::new(files~)
  run_session(
    settings,
    (settings, clock, warn) => settings
      .files()
      .mapi((index, file) => file_destination(
        file,
        clock,
        failure => warn(index, failure),
        io=fs.io(),
      )),
    clock,
    None,
    body,
  )
}

///|
fn line(text : String) -> String {
  "2026-10-27T14:23:07.024Z [INF] \{text}\n"
}

///|
async test "no file-directed event creates no directory, marker or file" {
  let fs = FakeFs::new()
  let report = with_files(fs, [@sinks.FileSink::new(logs(), acme())], session => {
    let logger : &@logging.Logger = session.logger()
    logger.debug("below the minimum", [])
    session.close()
  })
  assert_eq(fs.entries.length(), 0)
  assert_eq(report.accepted(), 0L)
}

///|
async test "the first event creates the directory, marker and file; close releases the marker" {
  let fs = FakeFs::new()
  let report = with_files(fs, [@sinks.FileSink::new(logs(), acme())], session => {
    let logger : &@logging.Logger = session.logger()
    logger.info("first", [])
    ignore(session.drain())
    assert_eq(fs.names("/logs"), ["acme-20261027.log", "acme.log.lock"])
    session.close()
  })
  assert_eq(fs.names("/logs"), ["acme-20261027.log"])
  assert_eq(fs.text("/logs/acme-20261027.log"), Some(line("first")))
  assert_false(report.delivery_failed())
}

///|
async test "an existing marker fails ownership, stays, and no file changes" {
  let fs = FakeFs::new()
  fs.add("/logs", Folder)
  fs.add("/logs/acme.log.lock", Regular)
  fs.add("/logs/acme-20261027.log", Regular, text="old\n")
  let report = with_files(fs, [@sinks.FileSink::new(logs(), acme())], session => {
    let logger : &@logging.Logger = session.logger()
    logger.info("first", [])
    logger.info("second", [])
    session.close()
  })
  assert_eq(fs.names("/logs"), ["acme-20261027.log", "acme.log.lock"])
  assert_eq(fs.text("/logs/acme-20261027.log"), Some("old\n"))
  let destination = report.destinations()[0]
  guard destination.failure() is Some(failure) else { fail("no failure") }
  assert_eq(failure.operation(), AcquireOwnership)
  assert_eq(failure.subject(), Some("/logs/acme.log.lock"))
  assert_eq(destination.undelivered(), 2L)
}

///|
async test "a restart appends to the newest file of the period and keeps its bytes" {
  let fs = FakeFs::new()
  fs.add("/logs", Folder)
  fs.add("/logs/acme-20261027.log", Regular, text="old line\n")
  ignore(
    with_files(fs, [@sinks.FileSink::new(logs(), acme())], session => {
      (session.logger() : &@logging.Logger).info("new", [])
      session.close()
    }),
  )
  assert_eq(fs.text("/logs/acme-20261027.log"), Some("old line\n" + line("new")))
}

///|
fn limit(bytes : Int64) -> @rolling.FileByteLimit {
  @rolling.FileByteLimit::bytes(bytes) catch {
    _ => abort("a valid limit")
  }
}

///|
fn keep(count : Int) -> @rolling.Retention {
  KeepNewest(
    @rolling.RetainedFileCount::count(count) catch {
      _ => abort("a valid count")
    },
  )
}

///|
async test "a size roll writes whole records, exact fits stay, and one byte more rolls" {
  let fs = FakeFs::new()
  // line("aa") is 34 bytes, so two records fit 68 bytes exactly.
  let sink = @sinks.FileSink::new(logs(), acme(), policy=DailyAndSize(limit(68L)))
  ignore(
    with_files(fs, [sink], session => {
      let logger : &@logging.Logger = session.logger()
      logger.info("aa", [])
      logger.info("aa", [])
      logger.info("a", [])
      session.close()
    }),
  )
  assert_eq(fs.text("/logs/acme-20261027.log"), Some(line("aa") + line("aa")))
  assert_eq(fs.text("/logs/acme-20261027_001.log"), Some(line("a")))
}

///|
async test "a record larger than the file limit goes whole into an empty file" {
  let fs = FakeFs::new()
  let sink = @sinks.FileSink::new(logs(), acme(), policy=Size(limit(10L)))
  ignore(
    with_files(fs, [sink], session => {
      let logger : &@logging.Logger = session.logger()
      logger.info("larger than ten bytes", [])
      logger.info("next", [])
      session.close()
    }),
  )
  assert_eq(fs.text("/logs/acme.log"), Some(line("larger than ten bytes")))
  assert_eq(fs.text("/logs/acme_001.log"), Some(line("next")))
}

///|
async test "a replacement that cannot open stops the file and skips retention" {
  let fs = FakeFs::new()
  fs.add("/logs", Folder)
  fs.add("/logs/acme-20261020.log", Regular, text="x\n")
  fs.add("/logs/acme-20261021.log", Regular, text="y\n")
  fs.fail_open["acme-20261027_001.log"] = "EACCES: permission denied"
  let sink = @sinks.FileSink::new(
    logs(),
    acme(),
    policy=DailyAndSize(limit(40L)),
    retention=keep(2),
  )
  let report = with_files(fs, [sink], session => {
    let logger : &@logging.Logger = session.logger()
    logger.info("one", [])
    logger.info("two", [])
    logger.info("three", [])
    session.close()
  })
  // The first open kept the active file and the newest other file.
  assert_eq(fs.names("/logs"), ["acme-20261021.log", "acme-20261027.log"])
  let destination = report.destinations()[0]
  guard destination.failure() is Some(failure) else { fail("no failure") }
  assert_eq(failure.operation(), OpenFile)
  assert_eq(failure.subject(), Some("acme-20261027_001.log"))
  assert_eq(destination.written(), 1L)
  assert_eq(destination.undelivered(), 2L)
}

///|
async test "a deletion failure is reported and the active file keeps the event" {
  let fs = FakeFs::new()
  fs.add("/logs", Folder)
  for day in ["20", "21", "22"] {
    fs.add("/logs/acme-202610\{day}.log", Regular, text="old\n")
  }
  fs.fail_remove["acme-20261020.log"] = "EBUSY: resource busy"
  let sink = @sinks.FileSink::new(logs(), acme(), retention=keep(2))
  let report = with_files(fs, [sink], session => {
    (session.logger() : &@logging.Logger).info("kept", [])
    session.close()
  })
  assert_eq(fs.names("/logs"), [
    "acme-20261020.log", "acme-20261022.log", "acme-20261027.log",
  ])
  assert_eq(fs.text("/logs/acme-20261027.log"), Some(line("kept")))
  let destination = report.destinations()[0]
  assert_eq(destination.failure(), None)
  guard destination.retention_failure() is Some(failure) else {
    fail("no retention failure")
  }
  assert_eq(failure.operation(), DeleteOldFile)
  assert_eq(failure.subject(), Some("acme-20261020.log"))
  assert_false(report.delivery_failed())
}

///|
async test "a full disk stops the file and a partial write is not replayed" {
  let fs = FakeFs::new()
  fs.write_budget = Some(10)
  let report = with_files(fs, [@sinks.FileSink::new(logs(), acme())], session => {
    let logger : &@logging.Logger = session.logger()
    logger.info("first", [])
    logger.info("second", [])
    session.close()
  })
  assert_eq(fs.write_calls, 1)
  assert_eq(fs.text("/logs/acme-20261027.log"), Some("2026-10-27"))
  let destination = report.destinations()[0]
  guard destination.failure() is Some(failure) else { fail("no failure") }
  assert_eq(failure.operation(), Write)
  assert_true(failure.detail().contains("after 10 bytes"))
  assert_eq(destination.undelivered(), 2L)
  // The marker of a failed file set is still released at close.
  assert_eq(fs.names("/logs"), ["acme-20261027.log"])
}

///|
async test "two formats in one directory keep their own markers and files" {
  let fs = FakeFs::new()
  let report = with_files(
    fs,
    [
      @sinks.FileSink::new(logs(), acme()),
      @sinks.FileSink::new(logs(), acme(), format=JsonLines),
    ],
    session => {
      (session.logger() : &@logging.Logger).info("both", [])
      ignore(session.drain())
      assert_eq(fs.names("/logs"), [
        "acme-20261027.jsonl", "acme-20261027.log", "acme.jsonl.lock", "acme.log.lock",
      ])
      session.close()
    },
  )
  assert_eq(fs.names("/logs"), ["acme-20261027.jsonl", "acme-20261027.log"])
  assert_eq(report.destinations().map(d => d.written()), [1L, 1L])
}

///|
async test "retention leaves links, directories, unrelated files and other sets" {
  let fs = FakeFs::new()
  fs.add("/logs", Folder)
  fs.add("/logs/acme-20261001.log", Link)
  fs.add("/logs/acme-20261002.log", Folder)
  for name in [
    "acme-old.log", "acmex-20261003.log", "acme-20261004.jsonl", "acme-20261005.log.bak",
    "acme-20261006.log", "acme-20261007.log",
  ] {
    fs.add("/logs/" + name, Regular, text="old\n")
  }
  ignore(
    with_files(fs, [@sinks.FileSink::new(logs(), acme(), retention=keep(2))], session => {
      (session.logger() : &@logging.Logger).info("new", [])
      session.close()
    }),
  )
  assert_eq(fs.names("/logs"), [
    "acme-20261001.log", "acme-20261002.log", "acme-20261004.jsonl", "acme-20261005.log.bak",
    "acme-20261007.log", "acme-20261027.log", "acme-old.log", "acmex-20261003.log",
  ])
}

///|
async test "keep all deletes nothing" {
  let fs = FakeFs::new()
  fs.add("/logs", Folder)
  fs.add("/logs/acme-20261001.log", Regular, text="old\n")
  ignore(
    with_files(fs, [@sinks.FileSink::new(logs(), acme(), retention=KeepAll)], session => {
      (session.logger() : &@logging.Logger).info("new", [])
      session.close()
    }),
  )
  assert_eq(fs.names("/logs"), ["acme-20261001.log", "acme-20261027.log"])
}

///|
async test "a directory that cannot be created is a create directory failure" {
  let fs = FakeFs::new()
  fs.fail_mkdir = Some("EACCES: permission denied")
  let report = with_files(fs, [@sinks.FileSink::new(logs(), acme())], session => {
    (session.logger() : &@logging.Logger).info("lost", [])
    session.close()
  })
  guard report.destinations()[0].failure() is Some(failure) else {
    fail("no failure")
  }
  assert_eq(failure.operation(), CreateDirectory)
  assert_eq(
    failure.message(),
    "logging: create directory failed for files /logs/acme.log.lock (/logs): EACCES: permission denied",
  )
}

///|
async test "the writer period does not move back with the clock" {
  let fs = FakeFs::new()
  // 2026-10-28T00:00:01.000Z, then 2026-10-27T23:59:58.000Z.
  let times = [1793145601000L, 1793145598000L]
  let calls = Ref(0)
  let clock = () => {
    let millis = times[if calls.val < 2 { 0 } else { 1 }]
    calls.val += 1
    @formatting.LogTimestamp::from_epoch_millis(millis) catch {
      _ => abort("a valid time")
    }
  }
  ignore(
    with_files(
      fs,
      [@sinks.FileSink::new(logs(), acme(), policy=Daily)],
      clock~,
      session => {
        let logger : &@logging.Logger = session.logger()
        logger.info("day two", [])
        ignore(session.drain())
        logger.info("clock moved back", [])
        session.close()
      },
    ),
  )
  assert_eq(fs.names("/logs"), ["acme-20261028.log"])
  let text = fs.text("/logs/acme-20261028.log").unwrap()
  assert_true(text.contains("2026-10-27T23:59:58.000Z [INF] clock moved back"))
}

///|
async test "a new day continues a file of that day from an earlier run" {
  let fs = FakeFs::new()
  fs.add("/logs", Folder)
  fs.add("/logs/acme-20261028.log", Regular, text="earlier run\n")
  // 2026-10-27T23:59:58.000Z, then 2026-10-28T00:00:01.000Z.
  let times = [1793145598000L, 1793145601000L]
  let calls = Ref(0)
  let clock = () => {
    let millis = times[if calls.val < 2 { 0 } else { 1 }]
    calls.val += 1
    @formatting.LogTimestamp::from_epoch_millis(millis) catch {
      _ => abort("a valid time")
    }
  }
  ignore(
    with_files(
      fs,
      [@sinks.FileSink::new(logs(), acme(), policy=Daily)],
      clock~,
      session => {
        let logger : &@logging.Logger = session.logger()
        logger.info("day one", [])
        ignore(session.drain())
        logger.info("day two", [])
        session.close()
      },
    ),
  )
  assert_eq(fs.names("/logs"), ["acme-20261027.log", "acme-20261028.log"])
  let text = fs.text("/logs/acme-20261028.log").unwrap()
  assert_true(text.has_prefix("earlier run\n"), msg=text)
  assert_true(text.contains("[INF] day two"), msg=text)
}

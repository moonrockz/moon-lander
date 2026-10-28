///|
/// An error with fixed `Show` text.
suberror SampleError {
  SampleError(String)
}

///|
impl Show for SampleError with output(self, logger) {
  let SampleError(text) = self
  logger.write_string(text)
}

///|
/// The error text of the examples.
let compiler_error : String =
  #|CompilerError: Unknown identifier calculate_total
  #|  at app.mbt:42

///|
/// The record of the one event that `write` gives, at 2026-10-27T14:23:07 and
/// `millis` milliseconds.
fn sample(
  write : (&@logging.Logger) -> Unit,
  category? : String,
  millis? : Int64 = 0L,
) -> @formatting.LogRecord raise {
  let memory = @logging.MemoryLogger::new()
  let logger : &@logging.Logger = match category {
    Some(name) => @logging.with_category(memory, name)
    None => memory
  }
  write(logger)
  let time = @formatting.LogTimestamp::from_epoch_millis(
    1793110987000L + millis,
  )
  @formatting.LogRecord::capture(memory.events()[0], time)
}

///|
/// The console events of the examples, from `TRC` to `CRT`.
fn console_examples() -> Array[@formatting.LogRecord] raise {
  [
    sample(
      logger => logger.trace("Inspecting {Path}", ["/work/acme/src"]),
      category="workspace.discovery",
      millis=12L,
    ),
    sample(
      logger => logger.debug("Selected environment {Environment}", [
        "Development",
      ]),
      category="config.loader",
      millis=18L,
    ),
    sample(
      logger => logger.info("Loaded {Count} files from {Path}", [3, "src"]),
      category="workspace.loader",
      millis=24L,
    ),
    sample(
      logger => logger.warn("Configuration file {File} was not found", [
        "optional.toml",
      ]),
      category="config.loader",
      millis=35L,
    ),
    sample(
      logger => logger.error(
        "Compilation failed for {File}",
        ["app.mbt"],
        error=SampleError(compiler_error),
      ),
      category="build.compiler",
      millis=41L,
    ),
    sample(
      logger => logger.critical("Startup failed; shutting down", []),
      category="app",
      millis=49L,
    ),
  ]
}

///|
/// `text` without ANSI SGR codes (`ESC [ ... m`).
fn strip_styles(text : String) -> String {
  let chars = text.to_array()
  let out = StringBuilder()
  let mut index = 0
  while index < chars.length() {
    if chars[index] == '\u{1b}' &&
      index + 1 < chars.length() &&
      chars[index + 1] == '[' {
      index += 2
      while index < chars.length() && chars[index] != 'm' {
        index += 1
      }
      index += 1
    } else {
      out.write_char(chars[index])
      index += 1
    }
  }
  out.to_string()
}

///|
/// True when no style is open at a line end or at the end of `text`: each
/// style code has a reset after it, before the next LF.
fn styles_close_before_line_ends(text : String) -> Bool {
  let mut open = false
  let chars = text.to_array()
  let mut index = 0
  while index < chars.length() {
    let char = chars[index]
    if char == '\u{1b}' {
      let start = index
      while chars[index] != 'm' {
        index += 1
      }
      let code = String::from_array(chars[start:index + 1])
      open = code != "\u{1b}[0m"
    } else if char == '\n' && open {
      return false
    }
    index += 1
  }
  !open
}

///|
test "plain console output matches the examples byte for byte" {
  let output = console_examples()
    .map(record => @formatting.format_console(record, Plain))
    .join("")
  inspect(output, content=(
    #|[14:23:07.012Z TRC] workspace.discovery: Inspecting /work/acme/src
    #|[14:23:07.018Z DBG] config.loader: Selected environment Development
    #|[14:23:07.024Z INF] workspace.loader: Loaded 3 files from src
    #|[14:23:07.035Z WRN] config.loader: Configuration file optional.toml was not found
    #|[14:23:07.041Z ERR] build.compiler: Compilation failed for app.mbt
    #|    CompilerError: Unknown identifier calculate_total
    #|      at app.mbt:42
    #|[14:23:07.049Z CRT] app: Startup failed; shutting down
    #|
  ))
}

///|
test "a console event without a category has no category separator" {
  let record = sample(
    logger => logger.info("Loaded {Count} files from {Path}", [3, "src"]),
    millis=24L,
  )
  inspect(@formatting.format_console(record, Plain), content=(
    #|[14:23:07.024Z INF] Loaded 3 files from src
    #|
  ))
  inspect(@formatting.format_text(record), content=(
    #|2026-10-27T14:23:07.024Z [INF] Loaded 3 files from src
    #|
  ))
}

///|
test "text file output matches the examples byte for byte" {
  let records = console_examples()[2:5].to_owned()
  records.push(
    sample(
      logger => logger.info(
        "Build summary:\nCompiled {Modules} modules\nCompleted in {Millis} ms",
        [12, 840],
      ),
      category="build.summary",
      millis=1100L,
    ),
  )
  inspect(records.map(@formatting.format_text).join(""), content=(
    #|2026-10-27T14:23:07.024Z [INF] workspace.loader: Loaded 3 files from src
    #|2026-10-27T14:23:07.035Z [WRN] config.loader: Configuration file optional.toml was not found
    #|2026-10-27T14:23:07.041Z [ERR] build.compiler: Compilation failed for app.mbt
    #|    CompilerError: Unknown identifier calculate_total
    #|      at app.mbt:42
    #|2026-10-27T14:23:08.100Z [INF] build.summary: Build summary:
    #|    Compiled 12 modules
    #|    Completed in 840 ms
    #|
  ))
}

///|
test "control characters become visible text before any style" {
  let record = sample(
    logger => logger.warn("Value {Input}\r\nnext\tline\u{7f}", [
      "\u{1b}[2Jcleared\u{9b}31m\u{0}",
    ]),
    category="cat\u{1b}]0;title\u{7}",
  )
  let plain = @formatting.format_console(record, Plain)
  inspect(plain, content=(
    #|[14:23:07.000Z WRN] cat\x1b]0;title\x07: Value \x1b[2Jcleared\x9b31m\x00\x0d
    #|    next	line\x7f
    #|
  ))
  assert_false(plain.contains("\u{1b}"))
  let literate = @formatting.format_console(record, Literate)
  assert_eq(strip_styles(literate), plain)
  let text = @formatting.format_text(record)
  assert_false(text.contains("\u{1b}"))
  assert_false(text.contains("\r"))
  assert_true(text.contains("\\x1b[2Jcleared"))
}

///|
test "an error with CR LF line ends shows the CR and indents each line" {
  let record = sample(logger => logger.error("Failed", [], error=SampleError(
    "first\r\nsecond",
  )))
  inspect(@formatting.format_text(record), content=(
    #|2026-10-27T14:23:07.000Z [ERR] Failed
    #|    first\x0d
    #|    second
    #|
  ))
}

///|
test "literate output styles each part and plain output has none" {
  let record = console_examples()[2]
  inspect(
    @formatting.format_console(record, Literate).escape(),
    content=(
      #|"\u{1b}[90m[14:23:07.024Z \u{1b}[0m\u{1b}[97mINF\u{1b}[0m\u{1b}[90m]\u{1b}[0m \u{1b}[90mworkspace.loader:\u{1b}[0m \u{1b}[37mLoaded \u{1b}[0m\u{1b}[95m3\u{1b}[0m\u{1b}[37m files from \u{1b}[0m\u{1b}[96msrc\u{1b}[0m\n"
    ),
  )
}

///|
test "each JSON type of a value has its own style" {
  let record = sample(logger => logger.info("{N}{S}{T}{F}{Z}{A}{O}", [
    1.5,
    "s",
    true,
    false,
    Json::null(),
    [1],
    { "k": 1 },
  ]))
  let literate = @formatting.format_console(record, Literate)
  assert_true(literate.contains("\u{1b}[95m1.5\u{1b}[0m"))
  assert_true(literate.contains("\u{1b}[96ms\u{1b}[0m"))
  assert_true(literate.contains("\u{1b}[94mtrue\u{1b}[0m"))
  assert_true(literate.contains("\u{1b}[94mfalse\u{1b}[0m"))
  assert_true(literate.contains("\u{1b}[34mnull\u{1b}[0m"))
  assert_true(literate.contains("\u{1b}[92m[1]\u{1b}[0m"))
  assert_true(literate.contains("\u{1b}[92m{\"k\":1}\u{1b}[0m"))
  assert_eq(strip_styles(literate), @formatting.format_console(record, Plain))
}

///|
test "each level code has its own emphasis" {
  let codes = console_examples().map(record => {
    @formatting.format_console(record, Literate)
  })
  assert_true(codes[0].contains("\u{1b}[90mTRC\u{1b}[0m"))
  assert_true(codes[1].contains("\u{1b}[37mDBG\u{1b}[0m"))
  assert_true(codes[2].contains("\u{1b}[97mINF\u{1b}[0m"))
  assert_true(codes[3].contains("\u{1b}[93mWRN\u{1b}[0m"))
  assert_true(codes[4].contains("\u{1b}[97;41mERR\u{1b}[0m"))
  assert_true(codes[5].contains("\u{1b}[1;97;41mCRT\u{1b}[0m"))
  assert_true(
    codes[4].contains(
      "\n    \u{1b}[91mCompilerError: Unknown identifier calculate_total\u{1b}[0m\n    \u{1b}[91m  at app.mbt:42\u{1b}[0m\n",
    ),
  )
}

///|
test "literate output without styles equals plain output for each event" {
  let records = console_examples()
  records.push(
    sample(logger => logger.info("Multi\nline {Value}\n", ["a\nb"]), millis=1L),
  )
  records.push(sample(logger => logger.info("", []), category="empty"))
  for record in records {
    let literate = @formatting.format_console(record, Literate)
    let plain = @formatting.format_console(record, Plain)
    assert_eq(strip_styles(literate), plain)
    assert_false(plain.contains("\u{1b}"))
    assert_true(styles_close_before_line_ends(literate))
    assert_true(literate.has_suffix("\n"))
  }
}

///|
test "a value with a line break continues on an indented line" {
  let record = sample(
    logger => logger.info("Multi\nline {Value}\n", ["a\nb"]),
    category="c",
  )
  inspect(@formatting.format_console(record, Plain), content=(
    #|[14:23:07.000Z INF] c: Multi
    #|    line a
    #|    b
    #|    
    #|
  ))
}

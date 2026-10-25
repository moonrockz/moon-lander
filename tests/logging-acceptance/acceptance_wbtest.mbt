///|
/// An application logger. It keeps each event and counts the calls to `log`, and
/// enables the levels from `minimum` up, or each level when `minimum` is `None`.
struct AppLogger {
  minimum : @logging.Level?
  received : Array[@logging.LogEvent]
}

///|
impl @logging.Logger for AppLogger with enabled(self, level) {
  match self.minimum {
    Some(minimum) => level >= minimum
    None => true
  }
}

///|
impl @logging.Logger for AppLogger with log(self, event) {
  self.received.push(event)
}

///|
/// An application logger that implements only `log`, so it uses the default
/// `enabled`.
struct LogOnly {
  received : Array[@logging.LogEvent]
}

///|
impl @logging.Logger for LogOnly with log(self, event) {
  self.received.push(event)
}

///|
suberror AcceptanceError {
  AcceptanceError(String)
}

///|
impl Show for AcceptanceError with output(self, logger) {
  let AcceptanceError(text) = self
  logger.write_string(text)
}

///|
struct LoggingWorld {
  memory : @logging.MemoryLogger
  second : @logging.MemoryLogger
  mut app : AppLogger?
  mut log_only : LogOnly?
  mut logger : &@logging.Logger?
}

///|
fn LoggingWorld::LoggingWorld() -> LoggingWorld {
  {
    memory: @logging.MemoryLogger::new(),
    second: @logging.MemoryLogger::new(),
    app: None,
    log_only: None,
    logger: None,
  }
}

///|
/// The logger that the When steps write to: the one a Given step chose, or the
/// in-memory logger.
fn LoggingWorld::target(self : LoggingWorld) -> &@logging.Logger {
  match self.logger {
    Some(logger) => logger
    None => self.memory
  }
}

///|
/// The last event that a backend of this world holds.
fn LoggingWorld::last_event(self : LoggingWorld) -> @logging.LogEvent raise {
  let events = match (self.app, self.log_only) {
    (Some(app), _) => app.received
    (_, Some(log_only)) => log_only.received
    _ => self.memory.events()
  }
  guard events.last() is Some(event) else { fail("no logger holds an event") }
  event
}

///|
fn level_of(name : String) -> @logging.Level raise {
  match name {
    "Trace" => Trace
    "Debug" => Debug
    "Information" => Information
    "Warning" => Warning
    "Error" => Error
    "Critical" => Critical
    _ => fail("unknown level \{name}")
  }
}

///|
fn level_names(events : Array[@logging.LogEvent]) -> String {
  events.map(event => event.level.to_string()).join(", ")
}

///|
/// The lines of the text line of `event`.
fn lines_of(event : @logging.LogEvent) -> Array[String] {
  event.to_line().split("\n").map(part => part.to_owned()).collect()
}

///|
fn write_each_level(logger : &@logging.Logger) -> Unit {
  for
    level in [
      @logging.Level::Trace,
      Debug,
      Information,
      Warning,
      Error,
      Critical,
    ] {
    logger.write(level, "event", [])
  }
}

///|
impl @moonspec.World for LoggingWorld with fn configure(self, setup) {
  setup.given0("an application logger that implements only log", () => {
    let log_only = LogOnly::{ received: [] }
    self.log_only = Some(log_only)
    self.logger = Some(log_only)
  })
  setup.given1(
    "an application logger that enables {word} and higher",
    (name : String) => {
      let app = AppLogger::{ minimum: Some(level_of(name)), received: [] }
      self.app = Some(app)
      self.logger = Some(app)
    },
  )
  setup.given1(
    "the in-memory logger behind the minimum level {word}",
    (name : String) => {
      self.logger = Some(@logging.min_level(self.memory, level_of(name)))
    },
  )
  setup.given1(
    "the application logger behind the minimum level {word}",
    (name : String) => {
      guard self.app is Some(app) else { fail("make the application logger first") }
      self.logger = Some(@logging.min_level(app, level_of(name)))
    },
  )
  setup.given1(
    "a fan-out over the in-memory logger and a second logger behind {word}",
    (name : String) => {
      self.logger = Some(
        @logging.fan_out([
          self.memory,
          @logging.min_level(self.second, level_of(name)),
        ]),
      )
    },
  )
  setup.given1(
    "the in-memory logger with the category {string}",
    (category : String) => {
      self.logger = Some(@logging.with_category(self.memory, category))
    },
  )
  setup.given0("the null logger", () => {
    self.logger = Some(@logging.null_logger())
  })
  setup.when0("code writes one event at each level", () => {
    write_each_level(self.target())
  })
  setup.when2(
    "code writes {string} at {word}",
    (template : String, name : String) => {
      self.target().write(level_of(name), template, [])
    },
  )
  setup.when3(
    "code writes {string} at {word} with the arguments {string}",
    (template : String, name : String, args : String) => {
      guard @json.parse(args) is Array(values) else {
        fail("the arguments are not a JSON array: \{args}")
      }
      self.target().write(level_of(name), template, values)
    },
  )
  setup.when3(
    "code writes {string} at {word} with the error {string}",
    (template : String, name : String, text : String) => {
      self.target().write(level_of(name), template, [], error=AcceptanceError(text))
    },
  )
  setup.then1("the application logger receives {int} events", (count : Int) => {
    let received = match (self.app, self.log_only) {
      (Some(app), _) => app.received
      (_, Some(log_only)) => log_only.received
      _ => fail("no application logger")
    }
    @expect.expect(received.length()).to_equal(count)
  })
  setup.then1("the in-memory logger holds {string}", (levels : String) => {
    @expect.expect(level_names(self.memory.events())).to_equal(levels)
  })
  setup.then1("the second logger holds {string}", (levels : String) => {
    @expect.expect(level_names(self.second.events())).to_equal(levels)
  })
  setup.then1("the event properties are {string}", (expected : String) => {
    let event = self.last_event()
    let shown = event.properties.map(entry => "\{entry.0}=\{entry.1.stringify()}")
    @expect.expect(shown.join(", ")).to_equal(expected)
  })
  setup.then1("the message is {string}", (expected : String) => {
    @expect.expect(self.last_event().message()).to_equal(expected)
  })
  setup.then1("the line is {string}", (expected : String) => {
    @expect.expect(lines_of(self.last_event())[0]).to_equal(expected)
  })
  setup.then1("the error line is {string}", (expected : String) => {
    let lines = lines_of(self.last_event())
    @expect.expect(lines.length()).to_equal(2)
    @expect.expect(lines[1]).to_equal(expected)
  })
  setup.then1("the event category is {string}", (expected : String) => {
    @expect.expect(self.last_event().category).to_equal(Some(expected))
  })
  setup.then1("the event level is {word}", (name : String) => {
    @expect.expect(self.last_event().level).to_equal(level_of(name))
  })
  setup.then0("the null logger enables no level", () => {
    guard self.logger is Some(logger) else { fail("choose the null logger first") }
    @expect.expect(logger.enabled(Critical)).to_be_false()
  })
}

///|
let backend_feature : String =
  #|Feature: Bring your own logger
  #|  Scenario: Application logger receives events
  #|    Given an application logger that implements only log
  #|    When code writes "Disk {Name} is low" at Information with the arguments '["C"]'
  #|    Then the application logger receives 1 events
  #|    And the event level is Information
  #|    And the event properties are "Name=\"C\""
  #|
  #|  Scenario: Default level check enables all levels
  #|    Given an application logger that implements only log
  #|    When code writes one event at each level
  #|    Then the application logger receives 6 events
  #|
  #|  Scenario: Disabled level builds no event
  #|    Given an application logger that enables Warning and higher
  #|    When code writes "Not built" at Debug
  #|    Then the application logger receives 0 events
  #|    When code writes "Built" at Error
  #|    Then the application logger receives 1 events

///|
let template_feature : String =
  #|Feature: Message templates
  #|  Scenario: Two holes bind in order
  #|    When code writes "Loaded {Count} files from {Path}" at Information with the arguments '[3, "src"]'
  #|    Then the event properties are "Count=3, Path=\"src\""
  #|    And the message is "Loaded 3 files from src"
  #|
  #|  Scenario: Escaped braces are not holes
  #|    When code writes "Use {{Name}} for {Value}" at Information with the arguments '[7]'
  #|    Then the event properties are "Value=7"
  #|    And the message is "Use {Name} for 7"
  #|
  #|  Scenario: Missing argument
  #|    When code writes "From {Path} to {Target}" at Information with the arguments '["a"]'
  #|    Then the event properties are "Path=\"a\""
  #|    And the message is "From a to {Target}"
  #|
  #|  Scenario: Extra argument
  #|    When code writes "Done {Count}" at Information with the arguments '[1, 2]'
  #|    Then the event properties are "Count=1"
  #|    And the message is "Done 1"
  #|
  #|  Scenario: Unclosed brace
  #|    When code writes "Value {Name" at Information with the arguments '[5]'
  #|    Then the event properties are ""
  #|    And the message is "Value {Name"
  #|
  #|  Scenario: Object value
  #|    When code writes "Saved {Order}" at Information with the arguments '[{"id": 1}]'
  #|    Then the message is "Saved {\"id\":1}"

///|
let combinator_feature : String =
  #|Feature: Built-in loggers and combinators
  #|  Scenario: Null logger drops events
  #|    Given the null logger
  #|    When code writes "Dropped" at Critical
  #|    Then the null logger enables no level
  #|    And the in-memory logger holds ""
  #|
  #|  Scenario: Lower levels are dropped
  #|    Given the in-memory logger behind the minimum level Warning
  #|    When code writes one event at each level
  #|    Then the in-memory logger holds "Warning, Error, Critical"
  #|
  #|  Scenario: Wrapped logger can disable more
  #|    Given an application logger that enables Error and higher
  #|    And the application logger behind the minimum level Debug
  #|    When code writes "Not passed" at Warning
  #|    Then the application logger receives 0 events
  #|
  #|  Scenario: Two loggers receive one event
  #|    Given a fan-out over the in-memory logger and a second logger behind Trace
  #|    When code writes "Both" at Information
  #|    Then the in-memory logger holds "Information"
  #|    And the second logger holds "Information"
  #|
  #|  Scenario: Each logger keeps its own level
  #|    Given a fan-out over the in-memory logger and a second logger behind Error
  #|    When code writes "Only first" at Warning
  #|    Then the in-memory logger holds "Warning"
  #|    And the second logger holds ""
  #|
  #|  Scenario: Category is set
  #|    Given the in-memory logger with the category "morphir.build"
  #|    When code writes "Loaded {Count} files" at Information with the arguments '[3]'
  #|    Then the event category is "morphir.build"
  #|    And the event level is Information
  #|    And the event properties are "Count=3"

///|
let line_feature : String =
  #|Feature: Text lines
  #|  Scenario: Line with a category
  #|    Given the in-memory logger with the category "morphir.build"
  #|    When code writes "Loaded {Count} files from {Path}" at Information with the arguments '[3, "src"]'
  #|    Then the line is "[INF] morphir.build: Loaded 3 files from src"
  #|
  #|  Scenario: Line without a category
  #|    When code writes "Disk {Name} is low" at Warning with the arguments '["C"]'
  #|    Then the line is "[WRN] Disk C is low"
  #|
  #|  Scenario: Line with an error
  #|    When code writes "Load failed" at Error with the error "NotFound"
  #|    Then the line is "[ERR] Load failed"
  #|    And the error line is "  error: NotFound"

///|
/// Run each scenario of `text` with a fresh world and fail on the first scenario
/// that does not pass. `@moonspec.run_or_fail` is async, and wasm-gc has no
/// async test entry, so this suite drives the synchronous runner steps itself to
/// run on all four targets.
fn[W : @moonspec.World] run_scenarios(
  factory : () -> W,
  uri : String,
  text : String,
) -> Unit raise {
  let cache = @runner.FeatureCache::new()
  cache.load_text(uri, text)
  let pickles = @runner.compile_pickles(cache)
  @expect.expect(pickles.is_empty()).to_be_false()
  for pickle in pickles {
    let setup = @moonspec_core.Setup::new()
    @moonspec.World::configure(factory(), setup)
    let result = @runner.execute_scenario(
      setup.step_registry(),
      feature_name=uri,
      scenario_name=pickle.name,
      pickle_id=pickle.id,
      tags=[],
      steps=pickle.steps,
    )
    if result.status != Passed {
      let failures = result.steps
        .filter(step => !step.status.is_passed())
        .map(step => "\{step.keyword}\{step.text}: \{step.status.to_repr()}")
      fail("\{pickle.name} did not pass:\n\{failures.join("\n")}")
    }
  }
}

///|
test "bring-your-own scenarios" {
  run_scenarios(
    () => LoggingWorld::LoggingWorld(),
    "backend.feature",
    backend_feature,
  )
}

///|
test "template scenarios" {
  run_scenarios(
    () => LoggingWorld::LoggingWorld(),
    "template.feature",
    template_feature,
  )
}

///|
test "combinator scenarios" {
  run_scenarios(
    () => LoggingWorld::LoggingWorld(),
    "combinator.feature",
    combinator_feature,
  )
}

///|
test "line scenarios" {
  run_scenarios(
    () => LoggingWorld::LoggingWorld(),
    "line.feature",
    line_feature,
  )
}

///|
/// A configuration `Secret` has no `ToJson`, so it cannot become a property by
/// accident. Its `Show` text is redacted, so a caller that passes that text gets
/// the redacted text in the line, not the exposed value.
test "a secret text stays redacted in a line" {
  let tree = @config.ConfigValue::from_json({
    "registry": { "token": { "env": "TOKEN" } },
  })
  let config = @config.build([@config.in_memory(tree, name="base")])
  let secret = config.secret(
    "registry.token",
    @config.env_resolver({ "TOKEN": "s3cr3t" }),
  )
  let memory = @logging.MemoryLogger::new()
  (memory : &@logging.Logger).info("Token {Token}", [Json(secret.to_string())])
  let line = memory.events()[0].to_line()
  @expect.expect(line).to_equal("[INF] Token <redacted>")
  @expect.expect(line.contains("s3cr3t")).to_be_false()
}

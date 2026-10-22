///|
/// The inputs of one Morphir preset scenario and the result of its load.
struct MorphirWorld {
  files : Array[(String, String)]
  mut start : String
  mut config : String?
  mut isolated : Bool
  mut project : String?
  mut platform : @config.Platform
  env_vars : Array[(String, String)]
  mut loaded : @config.Config?
  mut error : String?
}

///|
fn MorphirWorld::MorphirWorld() -> MorphirWorld {
  {
    files: [],
    start: "",
    config: None,
    isolated: false,
    project: None,
    platform: Linux,
    env_vars: [("HOME", "/home/user")],
    loaded: None,
    error: None,
  }
}

///|
fn MorphirWorld::case(self : MorphirWorld) -> @preset.Case {
  @preset.Case::new(
    "scenario",
    self.files,
    start=self.start,
    config?=self.config,
    isolated=self.isolated,
    project?=self.project,
    platform=self.platform,
    env_vars=self.env_vars,
  )
}

///|
fn MorphirWorld::result(self : MorphirWorld) -> @config.Config raise {
  match (self.loaded, self.error) {
    (Some(config), _) => config
    (None, Some(error)) => fail("the load failed: \{error}")
    (None, None) => fail("load the preset first")
  }
}

///|
/// The first report with the kind name `kind`.
fn MorphirWorld::report(
  self : MorphirWorld,
  kind : String,
) -> @config.SourceReport raise {
  guard self
    .result()
    .reports()
    .iter()
    .find_first(report => report.kind.report_name() == kind)
    is Some(report) else {
    fail("no \{kind} report")
  }
  report
}

///|
fn status_name(status : @config.SourceStatus) -> String {
  match status {
    Loaded => "loaded"
    NotFound => "not-found"
    Skipped => "skipped"
  }
}

///|
impl @moonspec.World for MorphirWorld with fn configure(self, setup) {
  setup.given2("a file {string} containing:", (
    path : String,
    text : @moonspec.DocString,
  ) => self.files.push((path, text.content)))
  setup.given1("an empty file {string}", (path : String) => {
    self.files.push((path, ""))
  })
  setup.given1("the working directory is {string}", (dir : String) => {
    self.start = dir
  })
  setup.given2("the environment variable {string} is {string}", (
    name : String,
    value : String,
  ) => self.env_vars.push((name, value)))
  setup.given0("no variable is set", () => self.env_vars.clear())
  setup.given1("the platform is {string}", (name : String) => {
    self.platform = match name {
      "Linux" => Linux
      "macOS" => MacOs
      "Windows" => Windows
      _ => fail("unknown platform \{name}")
    }
  })
  setup.given0("isolated mode is on", () => self.isolated = true)
  setup.given1("the explicit configuration file is {string}", (path : String) => {
    self.config = Some(path)
  })
  setup.given1("the project selector is {string}", (selector : String) => {
    self.project = Some(selector)
  })
  setup.when0("the Morphir preset loads", () => {
    let case = self.case()
    try @preset.load(case) catch {
      error => self.error = Some(error.message())
    } noraise {
      config => self.loaded = Some(config)
    }
  })
  setup.then2("the effective text at {string} is {string}", (
    key : String,
    expected : String,
  ) => @expect.expect(@config.get_text(self.result(), key)).to_equal(expected))
  setup.then1("the effective configuration has no key {string}", (key : String) => {
    @expect.expect(self.result().get(@config.KeyPath::parse(key))).to_equal(
      None,
    )
  })
  setup.then1("loading fails with a message that holds {string}", (
    text : String,
  ) => {
    guard self.error is Some(error) else { fail("the load did not fail") }
    @expect.expect(error).to_contain(text)
  })
  setup.then2("the {string} source has the status {string}", (
    kind : String,
    status : String,
  ) => @expect.expect(status_name(self.report(kind).status)).to_equal(status))
  setup.then2("the {string} source path ends with {string}", (
    kind : String,
    suffix : String,
  ) => {
    guard self.report(kind).path is Some(path) else {
      fail("the \{kind} source has no path")
    }
    @expect.expect(path.has_suffix(suffix)).to_be_true()
  })
  setup.then0("the sources are in ascending priority order", () => {
    let priorities = self.result().reports().map(report => report.priority)
    for index in 1..<priorities.length() {
      @expect.expect(priorities[index - 1] <= priorities[index]).to_be_true()
    }
  })
  setup.then2("a {string} candidate is {string}", (
    kind : String,
    candidate : String,
  ) => {
    @expect.expect(self.report(kind).candidates.contains(candidate)).to_be_true()
  })
  setup.then2("no {string} candidate is in {string}", (
    kind : String,
    dir : String,
  ) => {
    @expect.expect(
      self.report(kind).candidates.iter().any(path => path.has_prefix(dir)),
    ).to_be_false()
  })
  setup.then1("the project candidates are:", (table : @moonspec.DocString) => {
    let expected = table.content
      .split("\n")
      .map(line => line.trim().to_owned())
      .filter(line => !line.is_empty())
      .map(line => @preset.at_root(line))
      .collect()
    @expect.expect(self.report("project").candidates).to_equal(expected)
  })
  setup.then1("no source has the kind {string}", (kind : String) => {
    @expect.expect(
      self
      .result()
      .reports()
      .iter()
      .any(report => report.kind.report_name() == kind),
    ).to_be_false()
  })
  setup.then1("no source loads {string}", (path : String) => {
    @expect.expect(
      self
      .result()
      .reports()
      .iter()
      .any(report => report.path == Some(@preset.at_root(path))),
    ).to_be_false()
  })
  setup.then1("the {string} source has no candidates", (kind : String) => {
    @expect.expect(self.report(kind).candidates).to_equal([])
  })
  setup.then1("a warning holds {string}", (text : String) => {
    @expect.expect(
      self
      .result()
      .warnings()
      .iter()
      .any(warning => match warning {
        Note(message~, ..) => message.contains(text)
        KeyRemoved(key, _) => key.to_string().contains(text)
      }),
    ).to_be_true()
  })
  setup.then1("the member source has a removed-key warning for {string}", (
    key : String,
  ) => {
    let warnings = self.report("workspace-member").warnings
    guard warnings is [KeyRemoved(removed, _)] else {
      fail("expected one removed-key warning")
    }
    @expect.expect(removed.to_string()).to_equal(key)
  })
}

///|
async test "Morphir preset acceptance scenarios" {
  @moonspec.run_or_fail(
    () => MorphirWorld::MorphirWorld(),
    @moonspec.RunOptions::RunOptions([
      @moonspec.FeatureSource::File(
        "config-conventions-acceptance/features/morphir.feature",
      ),
    ]),
  )
}

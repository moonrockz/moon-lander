///|
fn file_origin(role : @config.FileRole, path : String) -> @config.Origin {
  { kind: File(role), source: "file", priority: 300, location: Some(path) }
}

///|
fn env_origin(variable : String) -> @config.Origin {
  { kind: Environment, source: "env", priority: 600, location: Some(variable) }
}

///|
fn located(
  path : @config.DecodePath,
  blame : @config.Blame,
) -> @config.Located {
  { path, blame }
}

///|
fn at_key(text : String) -> @config.DecodePath {
  { key: Some(key(text)), suffix: [] }
}

///|
fn ambiguous_load() -> Unit raise @config.ConfigError {
  raise Ambiguous(
    display="App",
    location="/w",
    candidates=["/w/app.toml", "/w/app.yaml"],
  )
}

///|
fn failed_decode() -> Unit raise @config.ConfigError {
  raise Decode(failure={
    at: [
      located(
        { key: Some(key("targets")), suffix: [Index(1), Field("level")] },
        Set([file_origin(Member, "/repo/app/morphir.toml")]),
      ),
    ],
    detail: "Int::from_json: expected number",
  })
}

///|
test "Match an error by case" {
  try ambiguous_load() catch {
    Ambiguous(location~, candidates~, ..) => {
      @expect.expect(location).to_equal("/w")
      @expect.expect(candidates).to_equal(["/w/app.toml", "/w/app.yaml"])
    }
    _ => fail("expected the ambiguity case")
  } noraise {
    _ => fail("expected an ambiguity error")
  }
}

///|
test "Binding failure is a configuration error" {
  try failed_decode() catch {
    Decode(failure~) =>
      @expect.expect(failure.at[0].path.to_string()).to_equal(
        "targets[1].level",
      )
    _ => fail("expected the decode case")
  } noraise {
    _ => fail("expected a decode error")
  }
}

///|
test "a decode path renders list indexes, quoted names, and the root" {
  let paths : Array[@config.DecodePath] = [
    { key: Some(key("ir.strict_mode")), suffix: [] },
    { key: Some(key("targets")), suffix: [Index(1), Field("level")] },
    { key: Some(key("servers.\"eu.west\".port")), suffix: [] },
    { key: Some(key("hosts")), suffix: [Index(0), Field("a.b"), Index(2)] },
    { key: None, suffix: [] },
  ]
  @expect.expect(paths.map(path => path.to_string())).to_equal([
    "ir.strict_mode", "targets[1].level", "servers.\"eu.west\".port", "hosts[0].\"a.b\"[2]",
    "(root)",
  ])
}

///|
test "message for Parse" {
  let error : @config.ConfigError = Parse(
    format="TOML",
    origin="/w/app.toml",
    message="expected a value",
    line=Some(1),
    column=Some(5),
  )
  @expect.expect(error.message()).to_equal(
    "Failed to parse TOML configuration /w/app.toml at line 1, column 5: expected a value",
  )
}

///|
test "message for UnsupportedYaml" {
  let error : @config.ConfigError = UnsupportedYaml(
    origin="/w/app.yaml",
    feature="anchor",
    line=1,
    column=4,
  )
  @expect.expect(error.message()).to_equal(
    "Unsupported YAML feature in /w/app.yaml at line 1, column 4: anchor",
  )
}

///|
test "message for InvalidRoot" {
  let error : @config.ConfigError = InvalidRoot(
    origin="/w/app.json",
    found="list",
  )
  @expect.expect(error.message()).to_equal(
    "The configuration root of /w/app.json must be a struct, not a list",
  )
}

///|
test "message for DuplicateKey" {
  let error : @config.ConfigError = DuplicateKey(
    origin="/w/app.ion",
    key=key("ir.layout"),
  )
  @expect.expect(error.message()).to_equal(
    "Duplicate configuration key ir.layout in /w/app.ion",
  )
}

///|
test "message for FileNotFound" {
  let error : @config.ConfigError = FileNotFound(path="conf/app.toml")
  @expect.expect(error.message()).to_equal(
    "Configuration file not found: conf/app.toml",
  )
}

///|
test "message for UnsupportedFormat" {
  let error : @config.ConfigError = UnsupportedFormat(
    path="app.ion",
    extensions=["toml", "yaml"],
  )
  @expect.expect(error.message()).to_equal(
    "No configuration format reads app.ion; registered extensions: toml, yaml",
  )
  let none : @config.ConfigError = UnsupportedFormat(
    path="app.ion",
    extensions=[],
  )
  @expect.expect(none.message()).to_equal(
    "No configuration format reads app.ion; no format is registered",
  )
}

///|
test "message for Ambiguous" {
  let error : @config.ConfigError = Ambiguous(
    display="Morphir",
    location="/w",
    candidates=["/w/morphir.toml", "/w/morphir.yaml"],
  )
  @expect.expect(error.message()).to_equal(
    "Ambiguous Morphir configuration; found: /w/morphir.toml, /w/morphir.yaml",
  )
}

///|
test "message for InvalidKeyPath" {
  let error : @config.ConfigError = InvalidKeyPath(
    text="ir..layout",
    reason="a name in the key path is empty",
  )
  @expect.expect(error.message()).to_equal(
    "Invalid configuration key path \"ir..layout\": a name in the key path is empty",
  )
}

///|
test "message for InvalidEnvKey" {
  let error : @config.ConfigError = InvalidEnvKey(variable="MORPHIR_A____B")
  @expect.expect(error.message()).to_equal(
    "Invalid configuration environment variable MORPHIR_A____B: a key segment is empty",
  )
}

///|
test "message for MergeKey" {
  let error : @config.ConfigError = MergeKey(
    key=key("servers"),
    index=2,
    source="/w/app.toml",
  )
  @expect.expect(error.message()).to_equal(
    "Cannot merge list servers by key: item 2 from /w/app.toml has no key value or repeats one",
  )
}

///|
test "message for InvalidSecret" {
  let error : @config.ConfigError = InvalidSecret(
    key=key("registry.token"),
    origin="/w/app.toml",
    reason="the command must be text",
  )
  @expect.expect(error.message()).to_equal(
    "Invalid secret reference registry.token in /w/app.toml: the command must be text",
  )
}

///|
test "message for KeyNotFound" {
  let error : @config.ConfigError = KeyNotFound(key=key("project.missing"))
  @expect.expect(error.message()).to_equal(
    "Configuration key not found: project.missing",
  )
}

///|
test "message for Render" {
  let error : @config.ConfigError = Render(
    format="TOML",
    key=key("ir"),
    reason="a null value has no TOML form",
  )
  @expect.expect(error.message()).to_equal(
    "Cannot write configuration key ir as TOML: a null value has no TOML form",
  )
}

///|
test "message for SourceOrder" {
  let error : @config.ConfigError = SourceOrder(
    source="project",
    priority=300,
    previous="environment",
    previous_priority=600,
  )
  @expect.expect(error.message()).to_equal(
    "Configuration source project has priority 300, lower than priority 600 of the source environment before it",
  )
}

///|
test "message for OutsideBoundary" {
  let error : @config.ConfigError = OutsideBoundary(
    start="/srv/other",
    boundary="/tmp/case",
  )
  @expect.expect(error.message()).to_equal(
    "The start directory /srv/other is outside the boundary /tmp/case",
  )
}

///|
test "message for InvalidEnvironmentName" {
  let error : @config.ConfigError = InvalidEnvironmentName(
    name="local",
    reason="the name is reserved (from --environment)",
  )
  @expect.expect(error.message()).to_equal(
    "Invalid environment name \"local\": the name is reserved (from --environment)",
  )
}

///|
test "message for UnknownProject" {
  let error : @config.ConfigError = UnknownProject(
    selector="missing",
    workspace="/repo",
  )
  @expect.expect(error.message()).to_equal(
    "No project in the workspace /repo matches missing",
  )
}

///|
test "message for AmbiguousProject" {
  let error : @config.ConfigError = AmbiguousProject(
    selector="orders",
    matches=["/repo/a", "/repo/b"],
  )
  @expect.expect(error.message()).to_equal(
    "More than one project matches orders: /repo/a, /repo/b; select a member by its path",
  )
}

///|
test "message for Decode" {
  let error : @config.ConfigError = Decode(failure={
    at: [
      located(
        at_key("ir.strict_mode"),
        Set([file_origin(UserOverride, "/repo/morphir.user.toml")]),
      ),
    ],
    detail: "Bool::from_json: expected boolean",
  })
  @expect.expect(error.message()).to_equal(
    "ir.strict_mode: Bool::from_json: expected boolean (set in user-override /repo/morphir.user.toml)",
  )
}

///|
test "message for Validation" {
  let error : @config.ConfigError = Validation(failures=[
    {
      at: [located(at_key("ir.layout"), Default)],
      detail: "must be one of single-file, split",
    },
    {
      at: [
        located(at_key("server.port"), Unset),
        located(at_key("server.host"), Set([env_origin("APP_SERVER__HOST")])),
      ],
      detail: "set both or neither",
    },
  ])
  @expect.expect(error.message()).to_equal(
    (
      #|ir.layout: must be one of single-file, split (from the bind default)
      #|server.port: set both or neither (not set by any source)
      #|server.host: set both or neither (set in environment APP_SERVER__HOST)
    ),
  )
}

///|
test "blame text names tables, list sources, and origins by kind" {
  let decode = (blame : @config.Blame) => (Decode(failure={
    at: [located(at_key("ir"), blame)],
    detail: "Missing field layout",
  }) : @config.ConfigError).message()
  @expect.expect(
    decode(
      Table([
        file_origin(UserOverride, "/repo/morphir.user.toml"),
        env_origin("MORPHIR_IR__STRICT_MODE"),
      ]),
    ),
  ).to_equal(
    "ir: Missing field layout (table set in user-override /repo/morphir.user.toml, environment MORPHIR_IR__STRICT_MODE)",
  )
  @expect.expect(decode(Table([]))).to_equal(
    "ir: Missing field layout (empty table, no source sets keys in it)",
  )
  @expect.expect(
    decode(
      Set([
        file_origin(Workspace, "C:/repo/morphir.toml"),
        file_origin(Member, "/repo/app/morphir.toml"),
        { kind: Defaults, source: "defaults", priority: 0, location: None },
        { kind: InMemory, source: "test", priority: 0, location: None },
        { kind: Overrides, source: "cli", priority: 700, location: None },
        { kind: Environment, source: "env", priority: 600, location: None },
        file_origin(Explicit, "/w/conf.toml"),
        file_origin(Legacy, "/w/morphir.json"),
        file_origin(System, "/etc/morphir/morphir.toml"),
        file_origin(Global, "/home/u/.config/morphir/morphir.toml"),
        file_origin(EnvironmentFile, "/repo/morphir.dev.toml"),
        file_origin(LocalOverride, "/repo/morphir.local.toml"),
      ]),
    ),
  ).to_equal(
    "ir: Missing field layout (set in project C:/repo/morphir.toml, workspace-member /repo/app/morphir.toml, defaults, in-memory, overrides, environment, project /w/conf.toml, project /w/morphir.json, system /etc/morphir/morphir.toml, global /home/u/.config/morphir/morphir.toml, environment-file /repo/morphir.dev.toml, local-override /repo/morphir.local.toml)",
  )
}

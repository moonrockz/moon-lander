// The preset cases. `morphir.feature` in `config-conventions-acceptance` has
// the same cases as Gherkin scenarios, and `config-conventions-laws` runs
// these values as snapshot tests on all four targets.

///|
let project_toml : String =
  #|[project]
  #|name = "acceptance-project"
  #|version = "1.0.0"
  #|
  #|[ir]
  #|format_version = 3

///|
/// Each preset case, in a fixed order.
pub fn cases() -> Array[Case] {
  [
    // Ported from Morphir's config.feature.
    Case::new(
      "Get a configuration value by dotted key",
      [("morphir.toml", project_toml)],
      isolated=true,
    ),
    Case::new(
      "Show a discovered project configuration",
      [("morphir.toml", project_toml), ("src/nested/main.mbt", "")],
      start="src/nested",
      isolated=true,
    ),
    Case::new(
      "Show an explicitly selected configuration",
      [
        (
          "configs/project.yaml",
          "project:\n  name: explicit-project\n  version: 2.0.0\n",
        ),
        ("elsewhere/readme.txt", ""),
      ],
      start="elsewhere",
      config="../configs/project.yaml",
      isolated=true,
    ),
    Case::new(
      "Environment values override project values",
      [("morphir.toml", "[ir]\nformat_version = 3\n")],
      isolated=true,
      env_vars=[("HOME", "/home/user"), ("MORPHIR_IR__FORMAT_VERSION", "4")],
    ),
    Case::new(
      "List configuration sources for a discovered project",
      [("morphir.toml", "[project]\nname = \"json-source-project\"\n")],
      isolated=true,
      env_vars=[("HOME", "/home/user"), ("MORPHIR_UI__COLOR", "false")],
    ),
    Case::new(
      "Reject malformed configuration",
      [("morphir.toml", "[project\nname = \"broken\"\n")],
      isolated=true,
    ),
    Case::new(
      "Reject ambiguous project configuration",
      [
        ("morphir.toml", "[project]\nname = \"toml-project\"\n"),
        ("morphir.yaml", "project:\n  name: yaml-project\n"),
      ],
      isolated=true,
    ),
    Case::new(
      "Discover project configuration in the dot-config layout",
      [(".config/morphir/config.toml", "[project]\nname = \"dot-config\"\n")],
      isolated=true,
    ),
    Case::new(
      "Discover YAML project configuration in the dot-config layout",
      [(".config/morphir/config.yaml", "project:\n  name: dot-config-yaml\n")],
      isolated=true,
    ),
    Case::new("An adjacent user override wins", [
      ("morphir.toml", "[ui]\ntheme = \"shared\"\n"),
      ("morphir.user.toml", "[ui]\ntheme = \"personal\"\n"),
    ]),
    Case::new("An adjacent .morphir user override wins", [
      (".morphir/morphir.toml", "[ui]\ntheme = \"shared\"\n"),
      (".morphir/morphir.user.toml", "[ui]\ntheme = \"personal\"\n"),
    ]),
    Case::new("An adjacent dot-config user override wins", [
      (".config/morphir/config.toml", "[ui]\ntheme = \"shared\"\n"),
      (".config/morphir/config.user.toml", "[ui]\ntheme = \"personal\"\n"),
    ]),
    Case::new("Member user overrides win after workspace user overrides", [
      (
        "morphir.toml",
        "[workspace]\nmembers = [\"members/alpha\"]\ndefault_member = \"members/alpha\"\n\n[ui]\ntheme = \"workspace\"\n",
      ),
      ("members/alpha/morphir.toml", "[ui]\ntheme = \"member\"\n"),
      ("morphir.user.toml", "[ui]\ntheme = \"workspace-user\"\n"),
      ("members/alpha/morphir.user.toml", "[ui]\ntheme = \"member-user\"\n"),
    ]),
    Case::new(
      "Reject multiple primary configurations across layouts",
      [
        ("morphir.toml", "[project]\nname = \"root-project\"\n"),
        (".morphir/morphir.toml", "[project]\nname = \"directory-project\"\n"),
      ],
      isolated=true,
    ),
    Case::new("Reject sibling user override serializations", [
      ("morphir.toml", "[ui]\ntheme = \"shared\"\n"),
      ("morphir.user.toml", "[ui]\ntheme = \"toml-personal\"\n"),
      ("morphir.user.yaml", "ui:\n  theme: yaml-personal\n"),
    ]),
    // Added from Morphir's merge rules.
    Case::new("Six primary candidates", [("readme.txt", "")], isolated=true),
    Case::new("Preset has no local layer", [
      ("morphir.toml", "[ui]\ntheme = \"shared\"\n"),
      ("morphir.local.toml", "[ui]\ntheme = \"local\"\n"),
    ]),
    Case::new("Reject two global files", [
      ("morphir.toml", ""),
      ("/home/user/.config/morphir/morphir.toml", "a = 1\n"),
      ("/home/user/.morphir/morphir.toml", "b = 1\n"),
    ]),
    Case::new(
      "Operational variables are not keys",
      [("morphir.toml", ""), ("/tmp/mh/morphir.toml", "[ui]\ntheme = \"home\"\n")],
      env_vars=[
        ("HOME", "/home/user"),
        ("MORPHIR_HOME", "/tmp/mh"),
        ("MORPHIR_LOG_DIR", "/tmp/logs"),
      ],
    ),
    Case::new(
      "Relative XDG_CONFIG_HOME is ignored",
      [("morphir.toml", "")],
      env_vars=[("HOME", "/home/alice"), ("XDG_CONFIG_HOME", "config")],
    ),
    Case::new(
      "macOS user configuration directory",
      [("morphir.toml", "")],
      platform=MacOs,
      env_vars=[("HOME", "/Users/Alice")],
    ),
    Case::new(
      "Windows directories",
      [("morphir.toml", "")],
      platform=Windows,
      env_vars=[
        ("APPDATA", "D:\\Profiles\\Alice\\Roaming"),
        ("USERPROFILE", "C:\\Users\\Alice"),
        ("PROGRAMDATA", "E:\\Data"),
      ],
    ),
    Case::new(
      "Windows system directory fallback",
      [("morphir.toml", "")],
      platform=Windows,
      env_vars=[],
    ),
    Case::new("Legacy morphir.json fallback", [
      ("morphir.json", "{ project: { name: \"legacy\" } }"),
      ("morphir.user.toml", "[ui]\ntheme = \"personal\"\n"),
    ]),
    Case::new(
      "Member selected from inside the member",
      [
        ("morphir.toml", "[workspace]\nmembers = [\"packages/*\"]\n"),
        ("packages/billing/morphir.toml", "[project]\nname = \"billing\"\n"),
        ("packages/orders/morphir.toml", "[project]\nname = \"orders\"\n"),
      ],
      start="packages/billing/src",
    ),
    Case::new(
      "Member entries stay in the workspace",
      [
        ("morphir.toml", "[workspace]\nmembers = [\"../outside\", \"packages/*\"]\n"),
        ("packages/orders/morphir.toml", "[project]\nname = \"orders\"\n"),
      ],
      isolated=true,
    ),
    Case::new(
      "A member cannot relocate the workspace output",
      [
        (
          "morphir.toml",
          "[workspace]\nmembers = [\"packages/*\"]\nout_dir = \"build\"\n",
        ),
        ("packages/orders/morphir.toml", "[workspace]\nout_dir = \"mine\"\n"),
      ],
      isolated=true,
    ),
    Case::new(
      "Project selection by name",
      [
        ("morphir.toml", "[workspace]\nmembers = [\"packages/*\"]\n"),
        ("packages/billing/morphir.toml", "[project]\nname = \"billing\"\n"),
        ("packages/orders/morphir.toml", "[project]\nname = \"orders\"\n"),
      ],
      isolated=true,
      project="orders",
    ),
    // The inherited filter differs from the Morphir Rust loader (design D9):
    // the member does not inherit the root project table.
    Case::new(
      "The member does not inherit the workspace project table",
      [
        (
          "morphir.toml",
          "[workspace]\nmembers = [\"packages/*\"]\n\n[project]\nname = \"root\"\n\n[ui]\ntheme = \"dark\"\n",
        ),
        ("packages/orders/morphir.toml", "[ir]\nformat_version = 3\n"),
      ],
      isolated=true,
    ),
  ]
}

///|
/// The case named `name`.
pub fn case_named(name : String) -> Case {
  guard cases().iter().find_first(case => case.name == name) is Some(case) else {
    abort("no preset case named \{name}")
  }
  case
}

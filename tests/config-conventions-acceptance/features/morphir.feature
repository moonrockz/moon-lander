Feature: The Morphir preset reproduces Morphir configuration discovery
  The Morphir preset uses only public convention parts. These scenarios port
  the discovery, precedence, member and ambiguity cases of Morphir's
  config.feature, and add cases from Morphir's merge rules. Each scenario
  starts in the root of an empty case tree on Linux with HOME=/home/user.
  config-conventions-laws runs the same cases as snapshots on all targets.

  # Ported from Morphir's config.feature

  Scenario: Get a configuration value by dotted key
    Given a file "morphir.toml" containing:
      """
      [project]
      name = "acceptance-project"
      version = "1.0.0"
      """
    And isolated mode is on
    When the Morphir preset loads
    Then the effective text at "project.name" is "acceptance-project"

  Scenario: Show a discovered project configuration
    Given a file "morphir.toml" containing:
      """
      [project]
      name = "acceptance-project"
      version = "1.0.0"

      [ir]
      format_version = 3
      """
    And the working directory is "src/nested"
    And isolated mode is on
    When the Morphir preset loads
    Then the effective text at "project.name" is "acceptance-project"
    And the effective text at "ir.format_version" is "3"

  Scenario: Show an explicitly selected configuration
    Given a file "configs/project.yaml" containing:
      """
      project:
        name: explicit-project
        version: 2.0.0
      """
    And the working directory is "elsewhere"
    And the explicit configuration file is "../configs/project.yaml"
    And isolated mode is on
    When the Morphir preset loads
    Then the effective text at "project.name" is "explicit-project"
    And the "project" source path ends with "configs/project.yaml"

  Scenario: Environment values override project values
    Given a file "morphir.toml" containing:
      """
      [ir]
      format_version = 3
      """
    And the environment variable "MORPHIR_IR__FORMAT_VERSION" is "4"
    And isolated mode is on
    When the Morphir preset loads
    Then the effective text at "ir.format_version" is "4"

  Scenario: List configuration sources for a discovered project
    Given a file "morphir.toml" containing:
      """
      [project]
      name = "json-source-project"
      version = "1.0.0"
      """
    And the environment variable "MORPHIR_UI__COLOR" is "false"
    And isolated mode is on
    When the Morphir preset loads
    Then the "project" source has the status "loaded"
    And the "environment" source has the status "loaded"
    And the "defaults" source has the status "loaded"
    And the sources are in ascending priority order

  Scenario: Reject malformed configuration
    Given a file "morphir.toml" containing:
      """
      [project
      name = "broken"
      """
    And isolated mode is on
    When the Morphir preset loads
    Then loading fails with a message that holds "Failed to parse TOML configuration"

  Scenario: Reject ambiguous project configuration
    Given a file "morphir.toml" containing:
      """
      [project]
      name = "toml-project"
      """
    And a file "morphir.yaml" containing:
      """
      project:
        name: yaml-project
      """
    And isolated mode is on
    When the Morphir preset loads
    Then loading fails with a message that holds "Ambiguous Morphir configuration"

  Scenario: Discover project configuration in the dot-config layout
    Given a file ".config/morphir/config.toml" containing:
      """
      [project]
      name = "dot-config-project"
      """
    And isolated mode is on
    When the Morphir preset loads
    Then the "project" source path ends with ".config/morphir/config.toml"

  Scenario: Discover YAML project configuration in the dot-config layout
    Given a file ".config/morphir/config.yaml" containing:
      """
      project:
        name: dot-config-yaml-project
      """
    And isolated mode is on
    When the Morphir preset loads
    Then the "project" source path ends with ".config/morphir/config.yaml"

  Scenario: An adjacent user override wins
    Given a file "morphir.toml" containing:
      """
      [ui]
      theme = "shared"
      """
    And a file "morphir.user.toml" containing:
      """
      [ui]
      theme = "personal"
      """
    When the Morphir preset loads
    Then the effective text at "ui.theme" is "personal"

  Scenario: An adjacent .morphir user override wins
    Given a file ".morphir/morphir.toml" containing:
      """
      [ui]
      theme = "shared"
      """
    And a file ".morphir/morphir.user.toml" containing:
      """
      [ui]
      theme = "personal"
      """
    When the Morphir preset loads
    Then the effective text at "ui.theme" is "personal"

  Scenario: An adjacent dot-config user override wins
    Given a file ".config/morphir/config.toml" containing:
      """
      [ui]
      theme = "shared"
      """
    And a file ".config/morphir/config.user.toml" containing:
      """
      [ui]
      theme = "personal"
      """
    When the Morphir preset loads
    Then the effective text at "ui.theme" is "personal"

  Scenario: Member user overrides win after workspace user overrides
    Given a file "morphir.toml" containing:
      """
      [workspace]
      members = ["members/alpha"]
      default_member = "members/alpha"

      [ui]
      theme = "workspace"
      """
    And a file "members/alpha/morphir.toml" containing:
      """
      [ui]
      theme = "member"
      """
    And a file "morphir.user.toml" containing:
      """
      [ui]
      theme = "workspace-user"
      """
    And a file "members/alpha/morphir.user.toml" containing:
      """
      [ui]
      theme = "member-user"
      """
    When the Morphir preset loads
    Then the effective text at "ui.theme" is "member-user"

  Scenario: Reject multiple primary configurations across layouts
    Given a file "morphir.toml" containing:
      """
      [project]
      name = "root-project"
      """
    And a file ".morphir/morphir.toml" containing:
      """
      [project]
      name = "directory-project"
      """
    And isolated mode is on
    When the Morphir preset loads
    Then loading fails with a message that holds "Ambiguous Morphir configuration"

  Scenario: Reject sibling user override serializations
    Given a file "morphir.toml" containing:
      """
      [ui]
      theme = "shared"
      """
    And a file "morphir.user.toml" containing:
      """
      [ui]
      theme = "toml-personal"
      """
    And a file "morphir.user.yaml" containing:
      """
      ui:
        theme: yaml-personal
      """
    When the Morphir preset loads
    Then loading fails with a message that holds "Ambiguous Morphir configuration"

  # Added from Morphir's merge rules

  Scenario: Six primary candidates
    Given an empty file "readme.txt"
    And isolated mode is on
    When the Morphir preset loads
    Then the "project" source has the status "not-found"
    And the project candidates are:
      """
      morphir.toml
      morphir.yaml
      .morphir/morphir.toml
      .morphir/morphir.yaml
      .config/morphir/config.toml
      .config/morphir/config.yaml
      """

  Scenario: Preset has no local layer
    Given a file "morphir.toml" containing:
      """
      [ui]
      theme = "shared"
      """
    And a file "morphir.local.toml" containing:
      """
      [ui]
      theme = "local"
      """
    When the Morphir preset loads
    Then the effective text at "ui.theme" is "shared"
    And no source loads "morphir.local.toml"
    And no source has the kind "local-override"

  Scenario: Reject two global files
    Given an empty file "morphir.toml"
    And a file "/home/user/.config/morphir/morphir.toml" containing:
      """
      a = 1
      """
    And a file "/home/user/.morphir/morphir.toml" containing:
      """
      b = 1
      """
    When the Morphir preset loads
    Then loading fails with a message that holds "Ambiguous Morphir configuration"

  Scenario: Operational variables are not keys
    Given an empty file "morphir.toml"
    And a file "/tmp/mh/morphir.toml" containing:
      """
      [ui]
      theme = "home"
      """
    And the environment variable "MORPHIR_HOME" is "/tmp/mh"
    And the environment variable "MORPHIR_LOG_DIR" is "/tmp/logs"
    When the Morphir preset loads
    Then a "global" candidate is "/tmp/mh/morphir.toml"
    And no "global" candidate is in "/home/user/.morphir"
    And the effective text at "ui.theme" is "home"
    And the effective configuration has no key "home"
    And the effective configuration has no key "log_dir"

  Scenario: Relative XDG_CONFIG_HOME is ignored
    Given an empty file "morphir.toml"
    And no variable is set
    And the environment variable "HOME" is "/home/alice"
    And the environment variable "XDG_CONFIG_HOME" is "config"
    When the Morphir preset loads
    Then a "global" candidate is "/home/alice/.config/morphir/morphir.yaml"

  Scenario: macOS user configuration directory
    Given an empty file "morphir.toml"
    And the platform is "macOS"
    And no variable is set
    And the environment variable "HOME" is "/Users/Alice"
    When the Morphir preset loads
    Then a "global" candidate is "/Users/Alice/Library/Application Support/morphir/morphir.toml"
    And a "global" candidate is "/Users/Alice/.morphir/morphir.toml"

  Scenario: Windows directories
    Given an empty file "morphir.toml"
    And the platform is "Windows"
    And no variable is set
    And the environment variable "APPDATA" is "D:\Profiles\Alice\Roaming"
    And the environment variable "USERPROFILE" is "C:\Users\Alice"
    And the environment variable "PROGRAMDATA" is "E:\Data"
    When the Morphir preset loads
    Then a "global" candidate is "D:/Profiles/Alice/Roaming/morphir/morphir.toml"
    And a "global" candidate is "C:/Users/Alice/.morphir/morphir.toml"
    And a "system" candidate is "E:/Data/morphir/morphir.toml"

  Scenario: Windows system directory fallback
    Given an empty file "morphir.toml"
    And the platform is "Windows"
    And no variable is set
    When the Morphir preset loads
    Then a "system" candidate is "C:/ProgramData/morphir/morphir.toml"

  Scenario: Legacy morphir.json fallback
    Given a file "morphir.json" containing:
      """
      { project: { name: "legacy" } }
      """
    And a file "morphir.user.toml" containing:
      """
      [ui]
      theme = "personal"
      """
    When the Morphir preset loads
    Then the "project" source path ends with "/morphir.json"
    And the "project" source has no candidates
    And the effective text at "project.name" is "legacy"
    And no source has the kind "user-override"

  Scenario: Member selected from inside the member
    Given a file "morphir.toml" containing:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a file "packages/billing/morphir.toml" containing:
      """
      [project]
      name = "billing"
      """
    And the working directory is "packages/billing/src"
    When the Morphir preset loads
    Then the "project" source path ends with "/case/morphir.toml"
    And the "workspace-member" source path ends with "packages/billing/morphir.toml"
    And the effective text at "project.name" is "billing"

  Scenario: Member entries stay in the workspace
    Given a file "morphir.toml" containing:
      """
      [workspace]
      members = ["../outside", "packages/*"]
      """
    And a file "packages/orders/morphir.toml" containing:
      """
      [project]
      name = "orders"
      """
    And isolated mode is on
    When the Morphir preset loads
    Then a warning holds "../outside"
    And the "workspace-member" source path ends with "packages/orders/morphir.toml"

  Scenario: A member cannot relocate the workspace output
    Given a file "morphir.toml" containing:
      """
      [workspace]
      members = ["packages/*"]
      out_dir = "build"
      """
    And a file "packages/orders/morphir.toml" containing:
      """
      [workspace]
      out_dir = "mine"
      """
    And isolated mode is on
    When the Morphir preset loads
    Then the member source has a removed-key warning for "workspace.out_dir"
    And the effective text at "workspace.out_dir" is ".morphir/out"

  Scenario: Project selection by name
    Given a file "morphir.toml" containing:
      """
      [workspace]
      members = ["packages/*"]
      """
    And a file "packages/billing/morphir.toml" containing:
      """
      [project]
      name = "billing"
      """
    And a file "packages/orders/morphir.toml" containing:
      """
      [project]
      name = "orders"
      """
    And the project selector is "orders"
    And isolated mode is on
    When the Morphir preset loads
    Then the effective text at "project.name" is "orders"

  # The inherited filter differs from the Morphir Rust loader (design D9). The
  # Rust loader keeps the workspace project table in the member view, so its
  # member would have project.name = "root".
  Scenario: The member does not inherit the workspace project table
    Given a file "morphir.toml" containing:
      """
      [workspace]
      members = ["packages/*"]

      [project]
      name = "root"

      [ui]
      theme = "dark"
      """
    And a file "packages/orders/morphir.toml" containing:
      """
      [ir]
      format_version = 3
      """
    And isolated mode is on
    When the Morphir preset loads
    Then the effective configuration has no key "project.name"
    And the effective text at "ui.theme" is "dark"

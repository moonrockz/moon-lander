// Snapshot tests of the Morphir preset cases on all four targets. Run
// `mise exec -- moon test tests/config-conventions-laws --update` to rewrite
// a snapshot after an intended change, and review the diff.

///|
test "morphir preset: Get a configuration value by dotted key" {
  inspect(@preset.observe(@preset.case_named("Get a configuration value by dotted key")), content=(
    #|defaults 0 loaded -
    #|system 100 skipped -
    #|global 200 skipped -
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 skipped -
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"3"},"project":{"name":"acceptance-project","version":"1.0.0"}}
  ))
}

///|
test "morphir preset: Show a discovered project configuration" {
  inspect(@preset.observe(@preset.case_named("Show a discovered project configuration")), content=(
    #|defaults 0 loaded -
    #|system 100 skipped -
    #|global 200 skipped -
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 skipped -
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"3"},"project":{"name":"acceptance-project","version":"1.0.0"}}
  ))
}

///|
test "morphir preset: Show an explicitly selected configuration" {
  inspect(@preset.observe(@preset.case_named("Show an explicitly selected configuration")), content=(
    #|defaults 0 loaded -
    #|system 100 skipped -
    #|global 200 skipped -
    #|project 300 loaded /case/configs/project.yaml
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"project":{"name":"explicit-project","version":"2.0.0"}}
  ))
}

///|
test "morphir preset: Environment values override project values" {
  inspect(@preset.observe(@preset.case_named("Environment values override project values")), content=(
    #|defaults 0 loaded -
    #|system 100 skipped -
    #|global 200 skipped -
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 skipped -
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"}}
  ))
}

///|
test "morphir preset: List configuration sources for a discovered project" {
  inspect(@preset.observe(@preset.case_named("List configuration sources for a discovered project")), content=(
    #|defaults 0 loaded -
    #|system 100 skipped -
    #|global 200 skipped -
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 skipped -
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"project":{"name":"json-source-project"},"ui":{"color":false}}
  ))
}

///|
test "morphir preset: Reject malformed configuration" {
  inspect(@preset.observe(@preset.case_named("Reject malformed configuration")), content=(
    #|error: Failed to parse TOML configuration /case/morphir.toml: Failure(parser.mbt:219:20-219:70@moonbit-community/toml FAILED: Expected ']' at { start: { line: 1, column: 9 }, end: { line: 2, column: 1 } })
  ))
}

///|
test "morphir preset: Reject ambiguous project configuration" {
  inspect(@preset.observe(@preset.case_named("Reject ambiguous project configuration")), content=(
    #|error: Ambiguous Morphir configuration; found: /case/morphir.toml, /case/morphir.yaml
  ))
}

///|
test "morphir preset: Discover project configuration in the dot-config layout" {
  inspect(@preset.observe(@preset.case_named("Discover project configuration in the dot-config layout")), content=(
    #|defaults 0 loaded -
    #|system 100 skipped -
    #|global 200 skipped -
    #|project 300 loaded /case/.config/morphir/config.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 skipped -
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"project":{"name":"dot-config"}}
  ))
}

///|
test "morphir preset: Discover YAML project configuration in the dot-config layout" {
  inspect(@preset.observe(@preset.case_named("Discover YAML project configuration in the dot-config layout")), content=(
    #|defaults 0 loaded -
    #|system 100 skipped -
    #|global 200 skipped -
    #|project 300 loaded /case/.config/morphir/config.yaml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 skipped -
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"project":{"name":"dot-config-yaml"}}
  ))
}

///|
test "morphir preset: An adjacent user override wins" {
  inspect(@preset.observe(@preset.case_named("An adjacent user override wins")), content=(
    #|defaults 0 loaded -
    #|system 100 not-found -
    #|  candidate /etc/morphir/morphir.toml
    #|  candidate /etc/morphir/morphir.yaml
    #|global 200 not-found -
    #|  candidate /home/user/.config/morphir/morphir.toml
    #|  candidate /home/user/.config/morphir/morphir.yaml
    #|  candidate /home/user/.morphir/morphir.toml
    #|  candidate /home/user/.morphir/morphir.yaml
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 loaded /case/morphir.user.toml
    #|  candidate /case/morphir.user.toml
    #|  candidate /case/morphir.user.yaml
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"ui":{"theme":"personal"}}
  ))
}

///|
test "morphir preset: An adjacent .morphir user override wins" {
  inspect(@preset.observe(@preset.case_named("An adjacent .morphir user override wins")), content=(
    #|defaults 0 loaded -
    #|system 100 not-found -
    #|  candidate /etc/morphir/morphir.toml
    #|  candidate /etc/morphir/morphir.yaml
    #|global 200 not-found -
    #|  candidate /home/user/.config/morphir/morphir.toml
    #|  candidate /home/user/.config/morphir/morphir.yaml
    #|  candidate /home/user/.morphir/morphir.toml
    #|  candidate /home/user/.morphir/morphir.yaml
    #|project 300 loaded /case/.morphir/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 loaded /case/.morphir/morphir.user.toml
    #|  candidate /case/.morphir/morphir.user.toml
    #|  candidate /case/.morphir/morphir.user.yaml
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"ui":{"theme":"personal"}}
  ))
}

///|
test "morphir preset: An adjacent dot-config user override wins" {
  inspect(@preset.observe(@preset.case_named("An adjacent dot-config user override wins")), content=(
    #|defaults 0 loaded -
    #|system 100 not-found -
    #|  candidate /etc/morphir/morphir.toml
    #|  candidate /etc/morphir/morphir.yaml
    #|global 200 not-found -
    #|  candidate /home/user/.config/morphir/morphir.toml
    #|  candidate /home/user/.config/morphir/morphir.yaml
    #|  candidate /home/user/.morphir/morphir.toml
    #|  candidate /home/user/.morphir/morphir.yaml
    #|project 300 loaded /case/.config/morphir/config.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 loaded /case/.config/morphir/config.user.toml
    #|  candidate /case/.config/morphir/config.user.toml
    #|  candidate /case/.config/morphir/config.user.yaml
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"ui":{"theme":"personal"}}
  ))
}

///|
test "morphir preset: Member user overrides win after workspace user overrides" {
  inspect(@preset.observe(@preset.case_named("Member user overrides win after workspace user overrides")), content=(
    #|defaults 0 loaded -
    #|system 100 not-found -
    #|  candidate /etc/morphir/morphir.toml
    #|  candidate /etc/morphir/morphir.yaml
    #|global 200 not-found -
    #|  candidate /home/user/.config/morphir/morphir.toml
    #|  candidate /home/user/.config/morphir/morphir.yaml
    #|  candidate /home/user/.morphir/morphir.toml
    #|  candidate /home/user/.morphir/morphir.yaml
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|workspace-member 350 loaded /case/members/alpha/morphir.toml
    #|  candidate /case/members/alpha/morphir.toml
    #|  candidate /case/members/alpha/morphir.yaml
    #|  candidate /case/members/alpha/.morphir/morphir.toml
    #|  candidate /case/members/alpha/.morphir/morphir.yaml
    #|  candidate /case/members/alpha/.config/morphir/config.toml
    #|  candidate /case/members/alpha/.config/morphir/config.yaml
    #|user-override 400 loaded /case/morphir.user.toml
    #|  candidate /case/morphir.user.toml
    #|  candidate /case/morphir.user.yaml
    #|user-override 400 loaded /case/members/alpha/morphir.user.toml
    #|  candidate /case/members/alpha/morphir.user.toml
    #|  candidate /case/members/alpha/morphir.user.yaml
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"ui":{"theme":"member-user"}}
  ))
}

///|
test "morphir preset: Reject multiple primary configurations across layouts" {
  inspect(@preset.observe(@preset.case_named("Reject multiple primary configurations across layouts")), content=(
    #|error: Ambiguous Morphir configuration; found: /case/morphir.toml, /case/.morphir/morphir.toml
  ))
}

///|
test "morphir preset: Reject sibling user override serializations" {
  inspect(@preset.observe(@preset.case_named("Reject sibling user override serializations")), content=(
    #|error: Ambiguous Morphir configuration; found: /case/morphir.user.toml, /case/morphir.user.yaml
  ))
}

///|
test "morphir preset: Six primary candidates" {
  inspect(@preset.observe(@preset.case_named("Six primary candidates")), content=(
    #|defaults 0 loaded -
    #|system 100 skipped -
    #|global 200 skipped -
    #|project 300 not-found -
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"}}
  ))
}

///|
test "morphir preset: Preset has no local layer" {
  inspect(@preset.observe(@preset.case_named("Preset has no local layer")), content=(
    #|defaults 0 loaded -
    #|system 100 not-found -
    #|  candidate /etc/morphir/morphir.toml
    #|  candidate /etc/morphir/morphir.yaml
    #|global 200 not-found -
    #|  candidate /home/user/.config/morphir/morphir.toml
    #|  candidate /home/user/.config/morphir/morphir.yaml
    #|  candidate /home/user/.morphir/morphir.toml
    #|  candidate /home/user/.morphir/morphir.yaml
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 not-found -
    #|  candidate /case/morphir.user.toml
    #|  candidate /case/morphir.user.yaml
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"ui":{"theme":"shared"}}
  ))
}

///|
test "morphir preset: Reject two global files" {
  inspect(@preset.observe(@preset.case_named("Reject two global files")), content=(
    #|error: Ambiguous Morphir configuration; found: /home/user/.config/morphir/morphir.toml, /home/user/.morphir/morphir.toml
  ))
}

///|
test "morphir preset: Operational variables are not keys" {
  inspect(@preset.observe(@preset.case_named("Operational variables are not keys")), content=(
    #|defaults 0 loaded -
    #|system 100 not-found -
    #|  candidate /etc/morphir/morphir.toml
    #|  candidate /etc/morphir/morphir.yaml
    #|global 200 loaded /tmp/mh/morphir.toml
    #|  candidate /home/user/.config/morphir/morphir.toml
    #|  candidate /home/user/.config/morphir/morphir.yaml
    #|  candidate /tmp/mh/morphir.toml
    #|  candidate /tmp/mh/morphir.yaml
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 not-found -
    #|  candidate /case/morphir.user.toml
    #|  candidate /case/morphir.user.yaml
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"ui":{"theme":"home"}}
  ))
}

///|
test "morphir preset: Relative XDG_CONFIG_HOME is ignored" {
  inspect(@preset.observe(@preset.case_named("Relative XDG_CONFIG_HOME is ignored")), content=(
    #|defaults 0 loaded -
    #|system 100 not-found -
    #|  candidate /etc/morphir/morphir.toml
    #|  candidate /etc/morphir/morphir.yaml
    #|global 200 not-found -
    #|  candidate /home/alice/.config/morphir/morphir.toml
    #|  candidate /home/alice/.config/morphir/morphir.yaml
    #|  candidate /home/alice/.morphir/morphir.toml
    #|  candidate /home/alice/.morphir/morphir.yaml
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 not-found -
    #|  candidate /case/morphir.user.toml
    #|  candidate /case/morphir.user.yaml
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"}}
  ))
}

///|
test "morphir preset: macOS user configuration directory" {
  inspect(@preset.observe(@preset.case_named("macOS user configuration directory")), content=(
    #|defaults 0 loaded -
    #|system 100 not-found -
    #|  candidate /etc/morphir/morphir.toml
    #|  candidate /etc/morphir/morphir.yaml
    #|global 200 not-found -
    #|  candidate /Users/Alice/Library/Application Support/morphir/morphir.toml
    #|  candidate /Users/Alice/Library/Application Support/morphir/morphir.yaml
    #|  candidate /Users/Alice/.morphir/morphir.toml
    #|  candidate /Users/Alice/.morphir/morphir.yaml
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 not-found -
    #|  candidate /case/morphir.user.toml
    #|  candidate /case/morphir.user.yaml
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"}}
  ))
}

///|
test "morphir preset: Windows directories" {
  inspect(@preset.observe(@preset.case_named("Windows directories")), content=(
    #|defaults 0 loaded -
    #|system 100 not-found -
    #|  candidate E:/Data/morphir/morphir.toml
    #|  candidate E:/Data/morphir/morphir.yaml
    #|global 200 not-found -
    #|  candidate D:/Profiles/Alice/Roaming/morphir/morphir.toml
    #|  candidate D:/Profiles/Alice/Roaming/morphir/morphir.yaml
    #|  candidate C:/Users/Alice/.morphir/morphir.toml
    #|  candidate C:/Users/Alice/.morphir/morphir.yaml
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 not-found -
    #|  candidate /case/morphir.user.toml
    #|  candidate /case/morphir.user.yaml
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"}}
  ))
}

///|
test "morphir preset: Windows system directory fallback" {
  inspect(@preset.observe(@preset.case_named("Windows system directory fallback")), content=(
    #|defaults 0 loaded -
    #|system 100 not-found -
    #|  candidate C:/ProgramData/morphir/morphir.toml
    #|  candidate C:/ProgramData/morphir/morphir.yaml
    #|global 200 not-found -
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|user-override 400 not-found -
    #|  candidate /case/morphir.user.toml
    #|  candidate /case/morphir.user.yaml
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"}}
  ))
}

///|
test "morphir preset: Legacy morphir.json fallback" {
  inspect(@preset.observe(@preset.case_named("Legacy morphir.json fallback")), content=(
    #|defaults 0 loaded -
    #|system 100 not-found -
    #|  candidate /etc/morphir/morphir.toml
    #|  candidate /etc/morphir/morphir.yaml
    #|global 200 not-found -
    #|  candidate /home/user/.config/morphir/morphir.toml
    #|  candidate /home/user/.config/morphir/morphir.yaml
    #|  candidate /home/user/.morphir/morphir.toml
    #|  candidate /home/user/.morphir/morphir.yaml
    #|project 300 loaded /case/morphir.json
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"project":{"name":"legacy"}}
  ))
}

///|
test "morphir preset: Member selected from inside the member" {
  inspect(@preset.observe(@preset.case_named("Member selected from inside the member")), content=(
    #|defaults 0 loaded -
    #|system 100 not-found -
    #|  candidate /etc/morphir/morphir.toml
    #|  candidate /etc/morphir/morphir.yaml
    #|global 200 not-found -
    #|  candidate /home/user/.config/morphir/morphir.toml
    #|  candidate /home/user/.config/morphir/morphir.yaml
    #|  candidate /home/user/.morphir/morphir.toml
    #|  candidate /home/user/.morphir/morphir.yaml
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|workspace-member 350 loaded /case/packages/billing/morphir.toml
    #|  candidate /case/packages/billing/morphir.toml
    #|  candidate /case/packages/billing/morphir.yaml
    #|  candidate /case/packages/billing/.morphir/morphir.toml
    #|  candidate /case/packages/billing/.morphir/morphir.yaml
    #|  candidate /case/packages/billing/.config/morphir/config.toml
    #|  candidate /case/packages/billing/.config/morphir/config.yaml
    #|user-override 400 not-found -
    #|  candidate /case/morphir.user.toml
    #|  candidate /case/morphir.user.yaml
    #|user-override 400 not-found -
    #|  candidate /case/packages/billing/morphir.user.toml
    #|  candidate /case/packages/billing/morphir.user.yaml
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"project":{"name":"billing"}}
  ))
}

///|
test "morphir preset: Member entries stay in the workspace" {
  inspect(@preset.observe(@preset.case_named("Member entries stay in the workspace")), content=(
    #|defaults 0 loaded -
    #|system 100 skipped -
    #|global 200 skipped -
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|workspace-member 350 loaded /case/packages/orders/morphir.toml
    #|  candidate /case/packages/orders/morphir.toml
    #|  candidate /case/packages/orders/morphir.yaml
    #|  candidate /case/packages/orders/.morphir/morphir.toml
    #|  candidate /case/packages/orders/.morphir/morphir.yaml
    #|  candidate /case/packages/orders/.config/morphir/config.toml
    #|  candidate /case/packages/orders/.config/morphir/config.yaml
    #|user-override 400 skipped -
    #|user-override 400 skipped -
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"project":{"name":"orders"}}
    #|warning note discovery skips the workspace entry ../outside, because it is not in the workspace directory
  ))
}

///|
test "morphir preset: A member cannot relocate the workspace output" {
  inspect(@preset.observe(@preset.case_named("A member cannot relocate the workspace output")), content=(
    #|defaults 0 loaded -
    #|system 100 skipped -
    #|global 200 skipped -
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|workspace-member 350 loaded /case/packages/orders/morphir.toml
    #|  candidate /case/packages/orders/morphir.toml
    #|  candidate /case/packages/orders/morphir.yaml
    #|  candidate /case/packages/orders/.morphir/morphir.toml
    #|  candidate /case/packages/orders/.morphir/morphir.yaml
    #|  candidate /case/packages/orders/.config/morphir/config.toml
    #|  candidate /case/packages/orders/.config/morphir/config.yaml
    #|  warning key-removed workspace.out_dir from /case/packages/orders/morphir.toml
    #|user-override 400 skipped -
    #|user-override 400 skipped -
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"}}
    #|warning key-removed workspace.out_dir from /case/packages/orders/morphir.toml
  ))
}

///|
test "morphir preset: Project selection by name" {
  inspect(@preset.observe(@preset.case_named("Project selection by name")), content=(
    #|defaults 0 loaded -
    #|system 100 skipped -
    #|global 200 skipped -
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|workspace-member 350 loaded /case/packages/orders/morphir.toml
    #|  candidate /case/packages/orders/morphir.toml
    #|  candidate /case/packages/orders/morphir.yaml
    #|  candidate /case/packages/orders/.morphir/morphir.toml
    #|  candidate /case/packages/orders/.morphir/morphir.yaml
    #|  candidate /case/packages/orders/.config/morphir/config.toml
    #|  candidate /case/packages/orders/.config/morphir/config.yaml
    #|user-override 400 skipped -
    #|user-override 400 skipped -
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"4"},"project":{"name":"orders"}}
  ))
}

///|
test "morphir preset: The member does not inherit the workspace project table" {
  inspect(@preset.observe(@preset.case_named("The member does not inherit the workspace project table")), content=(
    #|defaults 0 loaded -
    #|system 100 skipped -
    #|global 200 skipped -
    #|project 300 loaded /case/morphir.toml
    #|  candidate /case/morphir.toml
    #|  candidate /case/morphir.yaml
    #|  candidate /case/.morphir/morphir.toml
    #|  candidate /case/.morphir/morphir.yaml
    #|  candidate /case/.config/morphir/config.toml
    #|  candidate /case/.config/morphir/config.yaml
    #|workspace-member 350 loaded /case/packages/orders/morphir.toml
    #|  candidate /case/packages/orders/morphir.toml
    #|  candidate /case/packages/orders/morphir.yaml
    #|  candidate /case/packages/orders/.morphir/morphir.toml
    #|  candidate /case/packages/orders/.morphir/morphir.yaml
    #|  candidate /case/packages/orders/.config/morphir/config.toml
    #|  candidate /case/packages/orders/.config/morphir/config.yaml
    #|user-override 400 skipped -
    #|user-override 400 skipped -
    #|environment 600 loaded -
    #|value {"workspace":{"out_dir":".morphir/out"},"ir":{"format_version":"3"},"ui":{"theme":"dark"}}
  ))
}

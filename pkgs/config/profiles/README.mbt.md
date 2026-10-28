# Configuration profiles

Import `moonrockz/moon-lander-config/profiles` as `@profiles` for pure policy and
control resolution. Shared names, selections, errors, and loaded metadata live
at `moonrockz/moon-lander-config` (`@config`). Profiles compose independent
capabilities. The existing environment selector stays separate.

A profile name has 1 to 64 lowercase ASCII characters. It starts with a letter;
later characters can also be digits, `_`, or `-`. `local`, `user`, and `default`
are ordinary profile names. There is no implicit default profile.

```mbt check
///|
test "compose includes and a group with explicit later roots" {
  let metrics = @config.ProfileName::parse("metrics")
  let production = @config.ProfileName::parse("production")
  let postgres = @config.ProfileName::parse("postgres")
  let policy = @profiles.Policy::new()
    |> @profiles.includes(@config.ProfileNames::new([metrics]))
    |> @profiles.group(production, @config.ProfileNames::new([postgres, metrics]))
  let resolution = @profiles.resolve(
    policy,
    Selected(@config.ProfileNames::new([production, postgres])),
  )
  assert_eq(
    resolution.active().names().map(name => name.to_string()),
    ["production", "metrics", "postgres"],
  )
  assert_true(resolution.contains(postgres))
  assert_eq(resolution.selector(), Discovery)
}
```

Includes precede selected roots. Groups expand depth-first in listed order and
keep the group name active. Repeated names keep their last occurrence. Thus an
explicit later root can override a name reached through an include or group.
Each group's base-file definition replaces its whole policy definition.

Selection precedence is discovery/CLI, the present `<PREFIX>_PROFILES` variable,
base `profiles.active`, base `profiles.default`, then policy fallback. An explicit
empty selection keeps includes and suppresses defaults. Disabled suppresses
includes, groups, controls, and profile files. A present empty selector variable
also disables profiles; an absent variable does not.

```mbt check
///|
test "explicit empty selection differs from disabled processing" {
  let common = @config.ProfileName::parse("common")
  let development = @config.ProfileName::parse("development")
  let policy = @profiles.Policy::new()
    |> @profiles.includes(@config.ProfileNames::new([common]))
    |> @profiles.fallback(@config.ProfileNames::new([development]))
  let empty = @profiles.resolve(policy, Selected(@config.ProfileNames::new([])))
  assert_eq(empty.active().names(), [common])
  assert_false(empty.disabled())
  let disabled = @profiles.resolve(policy, Disabled)
  assert_eq(disabled.active().names(), [])
  assert_true(disabled.disabled())
  let variable = @profiles.resolve(
    policy,
    Unspecified,
    variable=("ACME_PROFILES", " \t"),
  )
  assert_true(variable.disabled())
  assert_eq(variable.selector(), Variable("ACME_PROFILES"))
}
```

For normal applications, enable the policy on the convention set. Conventions
selects the authoritative standard-layout project or workspace primary, resolves
controls once, and inserts profile files at priority 380, after environment files
and before local overrides. Within each active name, workspace precedes member.
A later workspace profile can override an earlier member profile. Missing files
produce not-found reports, so a profile can be a code-only marker.

With ordered formats enabled, every eligible base document participates in
format order. Within each active name, workspace format groups precede member
format groups. The authoritative base accepts these literal controls:

```toml
[profiles]
default = ["development"]
include = ["common"]

[profiles.groups]
production = ["postgres", "metrics"]
```

Controls are reserved only when profiles are enabled. They do not become
application settings or ordinary leaf origins. Controls in later layers or
selected-member primaries fail before key filters can hide them. Disabled
processing strips the subtree without interpreting it. With profiles off, the
same `profiles` key remains ordinary application data.

The resolver takes a parsed whole base value plus its origin. This direct API
supports pure callers that already own discovery. Passing `controls` does not
perform I/O.

```mbt check
///|
test "base controls retain selection and reason origins" {
  let source : @config.Origin = {
    kind: File(Workspace),
    source: "acme",
    priority: 300,
    location: Some("/work/acme.toml"),
  }
  let root = @config.ConfigValue::from_json({
    "profiles": {
      "default": ["development"],
      "include": ["common"],
      "groups": { "development": ["metrics"] },
    },
  })
  let resolution = @profiles.resolve(
    @profiles.Policy::new(),
    Unspecified,
    controls=(root, source),
  )
  assert_eq(resolution.selector(), BaseDefault(source))
  assert_eq(
    resolution.active().names().map(name => name.to_string()),
    ["common", "development", "metrics"],
  )
  assert_true(resolution.controls().contains(
    Control(source, @config.KeyPath::parse("profiles.groups.development")),
  ))
}
```

`Config::profiles()` exposes `Off` or `Resolved(resolution)` after a successful
complete load. The host factory, hooks, and command can inspect that same value
through their configuration. Returned arrays are copies. Membership uses parsed
`ProfileName` values and never repeats discovery.

Pure callers with several base documents use `ControlLayer`, `ControlLayers`,
and `resolve_layers`. Each document has its original source origin. Objects in
the reserved metadata merge by field; other values, including null, replace.
Lists and individual group definitions therefore come from their last supplied
value. Controls are parsed after this merge. A winning null control has a shape
error; ordinary configuration's null-as-unset rule cannot hide it.

```mbt check
///|
test "layered controls preserve each supplying origin" {
  let json : @config.Origin = {
    kind: File(Workspace), source: "acme", priority: 300,
    location: Some("/work/acme.json"),
  }
  let toml = { ..json, location: Some("/work/acme.toml") }
  let layers = @profiles.ControlLayers::new([
    @profiles.ControlLayer::new(@config.ConfigValue::from_json({
      "profiles": { "default": ["development"] },
    }), json),
    @profiles.ControlLayer::new(@config.ConfigValue::from_json({
      "profiles": { "groups": { "development": ["metrics"] } },
    }), toml),
  ])
  let input = @profiles.SelectionInput::new(Unspecified)
  let resolution = @profiles.resolve_layers(@profiles.Policy::new(), input, layers)
  assert_eq(resolution.selector(), BaseDefault(json))
  assert_true(resolution.controls().contains(
    Control(toml, @config.KeyPath::parse("profiles.groups.development")),
  ))
  assert_true(resolution.permits_controls(json))
}
```

Control authority and winning metadata are separate: every eligible input
document remains authorized even when another replaces all its controls. The
single-base `resolve(..., controls=...)` API retains its behavior.

With the convention `selected_file_policy(Overlay)`, a discovered base selected
by the host keeps its original control origins and authority. Its ordinary
values and one source report move to `Explicit` at priority 325. This does not
grant authority to an external selected file or a selected member. Those
locations still fail before filters, and disabled processing still strips their
controls. Pure source providers that move an already resolved base can use
`ProfileResolution::with_control_authority` to add its new ordinary source
identity without changing the winning metadata.

A complete effective graph has at most 64 groups, 64 members per group, 32 group
definitions on a path, and 128 distinct active names. All definitions are checked,
including inactive cycles. Shared subgroup expansion is memoized and deduplicated
before it can multiply across paths. Errors are `ConfigError::Profile` values;
inspect `failure.rule()`, `failure.origin()`, and `failure.cycle()` instead of
parsing the message.

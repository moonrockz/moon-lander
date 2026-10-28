# Proposal

## Why

Moon-Lander can select one deployment environment, but applications cannot compose
independent configuration choices such as `postgres`, `metrics`, and `tracing`.
Add ordered configuration profiles and groups so applications can reuse those
choices while keeping deterministic discovery, merge order, and provenance.

## What Changes

- Add opt-in profiles alongside the existing environment selector. Enabling
  `Production` does not implicitly activate a profile.
- Activate an ordered list through typed discovery options, `--profiles`,
  `<PREFIX>_PROFILES`, or an eligible base file. Support defaults, includes,
  reusable groups, and an explicit way to disable all profile processing.
- Use separate files such as `acme.profile.metrics.toml`. The owner selected
  separate files, activation, and groups for the first version on 2026-10-28.
- Resolve activation once from permitted base inputs. Reject cycles and profile
  controls in overlays so file selection cannot change during the merge.
- Load profile layers after environment layers and before local/user overrides.
  Define workspace/member ordering, missing-file reports, and exact name matching.
- Expose immutable active-profile information and typed membership queries to
  standalone consumers, service factories, hooks, and commands.
- **BREAKING, source API:** add a profile file-role case to the public enum.
  Consumers with exhaustive matches must handle it. `ConfigError` adds a typed
  profile-failure case. Custom providers use `Expansion::new` in place of public
  record literals, and accessors in place of field reads. Complete
  `DiscoveryOptions` literals add `profiles: Unspecified`; the constructor keeps
  that default. Existing environment-only behavior remains unchanged when
  profiles are off. The design records the verified migration.

See [examples](examples.md) for file layout, TOML controls, activation commands,
and a worked precedence example. See [design](design.md) for the author decisions.

## Capabilities

### New Capabilities

- `configuration-profiles`: profile names and activation, defaults/includes,
  groups, file selection, resolution reports, and host access to active profiles.

### Modified Capabilities

- `configuration-conventions`: profile options, project-layer order, isolated
  mode, workspace filters, and profile display priority.
- `configuration-core`: a typed profile file role and report name, priority, and
  immutable profile-resolution metadata on the loaded configuration.

## Impact

The change affects `pkgs/config`, a pure `pkgs/config/profiles` package,
`pkgs/config/conventions`, `pkgs/hosting`, its argparse adapter, and the umbrella
entry. It adds compiled guides and unpublished acceptance fixtures. It adds no
framework module, dependency, parser syntax, process API, or filesystem adapter.
Portable behavior must agree on wasm, wasm-gc, js, and native. Existing native,
Node/Bun, and browser adapters answer the ordinary typed file requests.

## Out of scope

Conditional sections within a file, YAML multi-document activation, profile
expression syntax, automatic service registration, annotations, configuration
reload, external config imports, and full Spring Boot compatibility. Applications
can choose services in their existing factory using typed profile queries.
Implementation, beads creation, release preparation, and publication are not part
of this proposal-writing task.

## References

- [Existing environment conventions](../../../../pkgs/config/conventions/README.mbt.md#environments).
- [Existing host configuration](../../../../pkgs/hosting/README.mbt.md#configuration-and-services).
- [Spring Boot profiles](https://docs.spring.io/spring-boot/reference/features/profiles.html),
  the reference for active profiles, includes, and groups. The namespace,
  filenames, ordering, and compatibility rules here belong to Moon-Lander.

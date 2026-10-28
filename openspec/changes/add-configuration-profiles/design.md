# Design

## Context

The config conventions package currently resolves one optional environment before
discovery. It adds one adjacent environment layer for the workspace and selected
member. Local/user overlays follow those layers. The host parses arguments once,
loads configuration, and then builds services. No profile registry exists.

Discovery already reads base files to choose a workspace and member. It runs over
the pure `FileTree` request protocol. A source provider currently returns sources
and warnings, but no typed activation metadata. The first slice must prove that
resolved profile information can reach both a standalone loaded configuration and
the host factory without a second independent resolution or hidden mutable state.

Labels marked Owner record the user's scope choice. Labels marked Call are author
decisions proposed for review. API spellings below are sketches, not implemented
interfaces.

## Goals and scope

Compose deployment capabilities, explain the result, retain the existing merge
rules, and keep all four portable targets. Preserve the environment feature and
the module dependency direction. See the proposal for exclusions.

### D1. Separate files in the first version (Owner)

Use separate profile files, activation, and groups. Do not change parser syntax
or introduce conditional sections or multi-document YAML. The YAML parser's
existing `Profile::Default | Strict` selects parser restrictions and is unrelated
to application configuration profiles.

### D2. Keep environment and profile names separate (Call)

An environment remains one deployment label with its existing selection and
case rules. Profiles are an ordered collection of optional capabilities. Neither
automatically activates the other. Files use a separate namespace:

| Primary | Profile `metrics` |
| --- | --- |
| `acme.toml` | `acme.profile.metrics.toml` |
| `.acme/acme.toml` | `.acme/acme.profile.metrics.toml` |
| `.config/acme/config.toml` | `.config/acme/config.profile.metrics.toml` |

Search only registered extensions. One candidate loads; multiple formats for one
profile at one location are ambiguous. No candidate is a `NotFound` report, not
an error: an active profile can be a code-only marker or have a file at only one
workspace location. A profile file never marks a project root. System/global,
legacy, and nonstandard explicit primaries gain no adjacent profile files.

### D3. Parse profile values at their boundary (Call)

Keep shared types needed by file roles, core reports, and host contexts at the
config module root. Put resolution and control-table parsing in the pure
`config/profiles` package. Conventions imports it; neither imports hosting.

- `ProfileName` has private fields. Accept 1 to 64 ASCII characters, starting
  with a lowercase letter, followed by lowercase letters, digits, `_`, or `-`.
  Reject uppercase instead of silently folding it. This avoids case aliases
  across filesystems and keeps file matching exact. `local` and `user` are valid
  profiles because `.profile.` distinguishes their files from overrides.
- Use typed immutable ordered name collections, an activation-selection enum,
  a parsed group registry, and a resolution result. Return defensive copies.
  A name already parsed for an option, registry, or filename is passed as a type.
- Errors carry the input or control key, a typed rule, and its source. Cycles
  also carry the closed cycle path. Never require callers to inspect prose.
- Bound groups to 64 definitions, members to 64 per group, group depth to 32,
  and distinct names in the resulting active set to 128. Group depth counts
  group definitions on a path, including the root group but not leaf names. Fail
  at a limit rather than truncate. Shared subgroups need memoized expansion or another bounded
  algorithm so a valid acyclic graph cannot cause exponential work.

`default` is an ordinary name, with no implicit activation. Empty active state
is valid. Unknown group names are ordinary leaf profiles; files are optional.

### D4. Enable explicitly and resolve selection precedence (Call)

An opt-in profile policy belongs to a convention set. It carries typed fallback
names, includes, and group definitions. The host supplies an equivalent builder
step over its host-owned conventions, plus standard argparse options. A bare
builder gains no discovery parts automatically. Only one enabled profile policy
is allowed in one configuration pipeline; duplicate providers fail explicitly.

Activation selection is `Unspecified | Selected(names) | Disabled`, not an
ambiguous optional array. Selection chooses a complete list, not an append across
different precedence levels:

1. Explicit discovery options, filled by the host's `--profiles` or `--no-profiles`.
2. `<PREFIX>_PROFILES` from the immutable run variable set.
3. `profiles.active` in the authoritative base file, including an empty list.
4. `profiles.default` in that base file.
5. The profile policy's fallback list, empty by default.

Repeated `--profiles <a,b>` occurrences concatenate in command-line order.
Split on commas and trim surrounding ASCII whitespace; reject empty elements and
invalid names. `--profiles=` is a usage error. `--no-profiles` conflicts with every
`--profiles` occurrence. A present empty or ASCII-whitespace-only variable means
Disabled; an absent variable means Unspecified. This differs deliberately from
the empty-as-unset environment selector and gives deployments an explicit off.

Disabled suppresses all includes, defaults, groups, and profile files. It still
returns an empty resolution with its disabling source. Do not read base-file
profile controls or any profile file to honor a disabled selection. The base file
still loads normally, and its reserved control subtree is excluded from values.
An invalid supplied CLI list fails before discovery, even if profiles are off.
With the feature off, ordinary environment variables and application data retain
their old interpretation, and no profile files or metadata are added. A valid
profile CLI selection with no enabled policy gives a note that it was ignored,
as the existing environment discovery option does. It must not enable discovery
implicitly. Off is distinct from an enabled policy with a disabled selection.

### D5. Read controls from one authoritative base (Call)

The authoritative base is the standard-layout workspace primary, or the standard
project primary when there is no selected workspace. Choose workspace/member
identity using the existing base-only discovery rules before reading profile
controls. A member primary in a selected workspace cannot redefine activation.

The reserved table is `profiles`, interpreted only when the feature is enabled:

| Field | Type and rule |
| --- | --- |
| `active` | Ordered string list; presence, including `[]`, overrides defaults |
| `default` | Ordered string list used only when no active selection is supplied |
| `include` | Ordered string list added before the chosen active/default roots |
| `groups` | Map from parsed group name to an ordered string list |

Reject unknown control fields and wrong types at their key path. Control values
must be literal values, not secret references or interpolation expressions.
File includes follow policy includes. For duplicate group definitions, the base
file replaces the policy's entire member list for that group; it does not append
implicitly. Validate the complete effective registry, including inactive cycles.
Well-typed lower-priority selectors are not additional active lists.

Profile controls are forbidden in profile/environment/local/user overlays,
system/global files, legacy/nonstandard explicit files, and selected-member
primaries. Inspect before filters so a filter cannot hide an invalid control.
Generic overrides and environment mappings cannot set reserved `profiles` data
once this feature is enabled. Reject them instead of showing an apparent
activation that has no effect. Reserve the exact `<PREFIX>_PROFILES` selector in
the host variable source; standalone callers explicitly reserve it too.

Remove the control subtree before ordinary values merge, bind, show, or receive
leaf provenance. Retain control origins in the resolution report. When disabled,
do not interpret controls in otherwise loaded sources; remove that subtree so it
cannot appear as effective application data. When profiles are off entirely,
`profiles` remains an ordinary application key.

### D6. Freeze a deterministic group expansion (Call)

Start with policy includes, then base-file includes, then the chosen active or
default roots. Expand each root depth-first in listed order, emitting the root
before its group members. Group names remain active and can have files. Remove
duplicate names by keeping their last occurrence. Thus an explicit later root
can override an included profile even if both reach it through groups.

For `include=[metrics]`, active roots `[production,postgres]`, and
`production=[postgres,metrics]`, expansion before deduplication is
`[metrics,production,postgres,metrics,postgres]`; the final order is
`[production,metrics,postgres]`. The last profile has highest profile precedence.

Validate group definitions in lexical name order and their members in listed
order. Detect cycles with a path stack before applying deduplication;
deduplication must not hide a cycle. Default roots are used only when no active selection is
present. An explicit empty selection suppresses defaults but keeps includes;
Disabled suppresses both. No fixed-point activation, implicit wildcard scan, or
re-read of controls after an overlay. Each load resolves from its own snapshot.

### D7. Insert one ordered profile stage (Call)

| Stage | Display priority | Order within stage |
| --- | --- | --- |
| Workspace/project primary | 300 | Existing rules |
| Selected member primary | 350 | Existing rules |
| Environment files | 375 | Workspace, then member |
| Profile files | 380 | For each active name in order: workspace, then member |
| Local overrides | 390 | Workspace, then member |
| User overrides | 400 | Workspace, then member |
| Environment variables | 600 | Existing rules |
| CLI configuration overrides | 700 | Existing rules |

Do not allocate a new integer priority per profile. Equal priority is already
allowed; source order controls precedence. A later workspace profile can override
an earlier member profile. The member wins within the same profile. Apply the
same member-scope and inherited filters to profile layers as to their respective
existing layers. Profiles cannot change workspace membership or trigger a second
project selection. Existing isolated mode keeps project profile files and skips
its existing machine/user/local sources.

Add `FileRole::ProfileFile(ProfileName)` with report kind `profile-file` and default
priority 380. Adding the public enum case can require downstream match updates.
Source reports remain in merge order; origins retain file path and typed role.
An inaccessible selected profile candidate must fail through the existing host
protocol. Never request or parse an inactive profile file's contents.

### D8. Publish the resolved state without repeating discovery (Call)

The loaded configuration exposes an immutable profile state: Off, or a resolution
with the winning selection source, roots, expanded active order, control origins,
and inclusion/group reasons. Typed membership queries use that state. The host
factory, hooks, and command receive the same resolution after configuration load.
They can choose service implementations explicitly; no automatic service filter
or annotation system is added.

Carry resolution with the source-provider expansion into the loaded configuration.
The first slice must settle the smallest typed API addition for this metadata and
show compatibility examples for custom providers. Do not encode it in warning
strings, application configuration, a global cache, or a callback side effect.
Two enabled profile providers are an error rather than a last-wins report.

Host parsing remains once per run. Profile flag syntax errors are usage failures;
invalid file controls, group graphs, and selected file errors are configuration
failures. Both end before factory/hooks and use the existing host exit policy.
Help and version finish without configuration or profile I/O. Profile option IDs
and the exact selector variable must not be mapped into ordinary config overrides.

### D9. Verification and delivery (Call)

Group 1 is a thin path through typed selection, a file overlay, source reports,
resolution metadata, and a host factory, plus the incomplete-tree protocol.
It must compile on all four targets before the full control/group feature grows.

Then implement the remaining task groups with their tests and compiled examples.
Verify all supported formats, stable equal-priority ordering, exact limits,
cycles/diamonds, include-versus-active duplicates, workspace filters, environment
compatibility, and repeat loads with different snapshots. Native/Node/Bun tests
use actual temporary files on Linux, macOS, and Windows; browser tests use existing
mounts with no Node shim. A cross-build is not runtime evidence.

## Workflow

The owner approved implementation and landing on 2026-10-28. Epic `lander-ntc`
and its five dependent stories track the numbered task groups. No release or
publication is authorized. Use as few reviewable PRs as needed. The last implementation PR
archives this change; after merges close and sync the beads with PR/merge evidence.
Do not archive the separate unfinished `add-host-lifecycle` change here.

## Vertical proof and source migration

The first slice passed discovery and host tests on wasm, wasm-gc, js and native.
The existing native, Node and Bun adapters loaded actual temporary profile files
on macOS. Incomplete snapshots returned typed requests without final state.

`Expansion` now has private fields and `Expansion::new(sources, warnings?,
profiles?)`. Custom providers replace `{ sources, warnings }` literals with this
constructor and omit `profiles` to retain Off. Provider decorators replace direct
field reads with defensive `sources()`, `warnings()` and `profiles()` accessors. `Config::profiles()` exposes the
recorded state; factories, hooks and commands read it through their existing
configuration. `DiscoveryOptions::new(profiles?)` defaults to Unspecified; callers
that use a complete public record literal add that field. Exhaustive matches on
`FileRole` add `ProfileFile(ProfileName)`, and exhaustive configuration-error
matches add `Profile(failure)`. No new module or adapter is needed.

# Tasks

Approved implementation, tracked by epic `lander-ntc` and one story per
numbered group. Each group includes its
tests, compiled guide changes, and generated public interfaces.

## 1. Prove one profile through discovery and a host factory

Bead: lander-ntc.1

- [x] 1.1 Add the minimal parsed profile selection and one adjacent profile overlay through public APIs; prove final values, priority 380, typed role/provenance, and recorded membership on all four targets with an injected complete tree.
- [x] 1.2 Prove one standard CLI selection reaches a host factory and the same resolution reaches later contexts; preserve help/version short-circuiting and environment-only callers. Settle the typed provider-to-config metadata API without a second resolution, global state, warning-string encoding, or application-data encoding; document any public source migration in the spec and compiled custom-provider example.
- [x] 1.3 Exercise the incomplete-tree request path through the existing native and Node/Bun adapters and pure embedded entry; verify no final state escapes Need, unknown candidates become typed requests, and two enabled profile providers fail visibly. Record any required design revision before the remaining groups.

## 2. Resolve activation, controls, includes, and groups

Bead: lander-ntc.2

- [x] 2.1 Implement typed policy/control parsing and activation precedence, including explicit empty versus disabled, run-variable semantics, authoritative base selection, reserved control removal, and forbidden locations; test shadowed invalid controls, literal-only values, unknown fields, selector-variable reservation, and every smart-constructor rule at each boundary.
- [x] 2.2 Implement ordered includes, recursive groups, group replacement, last-occurrence deduplication, default fallback, and typed resolution reasons; test diamonds, overlapping includes/roots, explicit repeated roots, empty groups, marker profiles, inactive cycles, and deterministic map-order independence.
- [x] 2.3 Enforce group/member/depth/name limits and bounded expansion work; verify exact and one-over boundaries, complete cycle paths and control origins, invalid names before file selection, explicit disable without profile reads, immutable returned state, and no implicit default profile on all four targets.

## 3. Integrate file order, reports, and workspace filters

Bead: lander-ntc.3

- [x] 3.1 Implement all three profile layouts using registered extensions and exact names; test missing markers, ambiguous formats, inactive malformed files, inaccessible selected candidates, no profile root markers, and no implicit profile siblings for global/legacy/nonstandard explicit sources.
- [x] 3.2 Insert profiles after all environment files and before local overrides, by name then workspace/member; verify equal-priority order, later workspace versus earlier member precedence, list policies, null overlays, ordinary provenance, source reports, and local/user/variable/CLI precedence.
- [x] 3.3 Apply inherited and member-scope filters to profile layers after forbidden-control checks; verify isolated mode retains project profiles, profiles cannot reselect members, explicit standard primaries work, and profiles-off preserves the full existing environment/Morphir/custom-provider acceptance corpus.

## 4. Complete standard host and argparse integration

Bead: lander-ntc.4

- [x] 4.1 Add the opt-in host policy step, global repeatable --profiles option, and mutually exclusive --no-profiles flag using the existing argparse adapter; test subcommands, comma/ASCII-whitespace rules, empty/invalid lists, prefix overrides, reserved selector names, conflicts with generic override mappings, and one parse per run. Do not edit vendored argparse.
- [x] 4.2 Expose the final immutable state to factories, hooks, commands, and the umbrella entry; add a compiled example choosing a service implementation explicitly, with no implicit registration or environment/profile coupling. Verify usage/configuration failures happen before construction and retain the existing exit policy on native/js and embedded targets.
- [x] 4.3 Verify repeated loads and host runs with different variable/file snapshots cannot share profile state; test profiles-off flag behavior, default-free bare builders, configure callbacks with custom providers, explicit disable, and help/version with no configuration I/O.

## 5. Qualify the public feature and prepare landing

Bead: lander-ntc.5

- [x] 5.1 Add public acceptance fixtures for activation, groups, precedence, errors, and reports in TOML, YAML, JSON/JSON5, and Ion; run equivalent pure observations on all four targets and real native/Node/Bun file tests on Linux/macOS/Windows, plus profile reads through existing browser mounts without Node shims.
- [x] 5.2 Extend existing MoonBit mise checks with nonzero profile acceptance coverage and consumer parity checks; convert the reviewed output/configuration examples into compiled guides and focused assertions, verify parser trimming and no new module/dependency, and record actual OS runtime evidence rather than using a cross-build as proof.
- [x] 5.3 Run formatting, strict all-spec validation, and mise run check; review domain types, I/O boundaries, compatibility and generated interfaces with the repository checklist. Tick verified tasks and archive this change in the last implementation PR; after merges close each story with PR/merge SHA, close the completed epic, and sync beads successfully.

## Dependencies and PR shape

Group 1 precedes all remaining groups. Group 2 precedes group 3. Group 4 completes
the host path proven in group 1 after groups 2 and 3 define final behavior. Group 5
follows the feature groups. Use as few PRs as remain reviewable; task groups are
tracker units, not a requirement to create five PRs. Do not archive the unrelated
unfinished host-lifecycle change or include a release in this work.

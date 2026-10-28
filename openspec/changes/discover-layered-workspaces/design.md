# Design

## Context

See proposal.md for the consumer requirement. The published 0.6.0 conventions use one `ProjectFile` per location. `Scan::config_at` returns `Several` when primary candidates of different formats coexist. `Conventions::declaration` recognizes a workspace only from members or default-member keys. `project_sources` searches for an enclosing workspace before it classifies the first file itself. `Scan::enclosing` passes over parse errors, ambiguous locations and excluded projects.

The configuration core already has pure sources, parser registration, provenance and the `Need`/`Done` load protocol. The existing native and JS adapter answers file requests. This design extends those parts. It does not create another loader.

## Goals / Non-Goals

The goal is one public discovery result that a consumer can use on all targets, with explicit policies for root selection and format groups. Policy defaults must keep the existing tests and source order valid.

The result must not force an application to use automatic single-member selection. Morphir needs to walk all members itself. This design does not give the framework a Morphir command model or permission to write configuration.

## Decisions

### Owner: Find the first workspace by inspecting documents

The Morphir maintainer requested this rule on 2026-10-28. In workspace-first mode, inspect each location in upward order. Keep the nearest project as a fallback. A configured workspace section in the merged primary documents, including an empty section, selects that location as the workspace. Inspect the first location itself before its parent. Stop there; a more distant workspace must not replace it.

This differs from using the first file as the workspace and from choosing an ancestor only when it selects the project as a member. Member selection follows the root decision. It cannot cause a search for a more distant container.

### Call: Add typed opt-in policies

Use closed alternatives for the existing root policy and workspace-first policy. The latter carries a validated section path. Use validated format-group definitions with an explicit order. Do not infer order from parser registration. Reject unknown formats, duplicate assignments and invalid paths before the load starts.

The current modes remain defaults. Making the new policy the default would change the legacy preset and excluded-member behavior for existing consumers.

### Call: Represent a location as ordered primary sources

Replace the one-file assumption inside the new path with a location result that holds ordered sources and a common root. Check alternatives inside each group before merging groups. A supplemental file precedes the ordinary primary in its group. It has a separate identity and report.

For Morphir, groups are JSON/JSON5, YAML/YML, then TOML. `morphir-workspace.json` is supplemental in the JSON group. JSON files still use the registered JSON5 parser; Morphir owns the manifest-field translation through a public value transform. The framework must not hard-code those application names or mappings.

A second independent convention set per format was considered. It can choose different roots, ignore a higher ancestor, or classify a workspace from only one document. It cannot establish the required common root or selected-source deduplication.

### Call: Preserve stage priorities and source identities

Within each existing stage, emit sources in format order at the same stage priority. Keep the existing stable order for equal priorities. The selected-file overlay has a position above workspace primaries and below member primaries. Use normalized file-tree paths to remove the selected source from its ordinary position before it loads. A supplemental selected source follows the same rule.

Do not load the source and then merge its values again. That would duplicate reports and could lose provenance or apply transforms twice.

### Call: Expose root evidence without forcing member selection

Return selected workspace and nearest-project roots through a public typed result. Keep discovery on the existing load protocol so partial trees request only missing entries. Allow a consumer to obtain root and primary-stage sources without enabling the framework's single-member loading path. The consumer uses public source and merge APIs for its own member walk.

Use an application-level adapter over that result for warnings about lower-format files. Warning suppression and command-line ownership remain Morphir responsibilities.

### Call: Fail on an examined invalid candidate in the new mode

Workspace classification needs a parsed document. A parse error or same-group ambiguity at an examined location must remain visible. Do not silently choose an ancestor. Preserve the existing skip behavior when the old policy is selected.

### Owner: Compose the enabled profile policy

The Morphir maintainer approved configuration profiles for its adoption release on 2026-10-28. Keep the published 0.6.0 activation, includes, groups, graph limits and disabling rules. Compose those rules with ordered base documents and profile files. The consumer keeps its frontend `--profile` separate from configuration `--profiles`.

### Call: Resolve controls from the discovered base with individual origins

Merge the eligible workspace primary documents, or standalone project primaries, in format order before resolving profile controls. Keep the origin of each winning control and group definition. Extend the resolver input with typed control origins while retaining the existing one-base/one-origin API as a compatible adapter. Do not assign every control the origin of the highest-format file.

Merge reserved control metadata literally before its one semantic parse: objects merge by field and other supplied values, including null, replace. Ordinary configuration's null-as-unset rule must not conceal an invalid control shape. Retain original document origins for empty containers as well as leaves. Authorize every eligible base identity separately from the winning control metadata, including a base whose controls were entirely replaced.

Keep control authority by original discovered source identity. If that file is selected as an ordinary-value overlay, parse it once, assess its controls as part of the base, strip the controls from its ordinary values, and emit one ordinary source report at priority 325 with role Explicit. This does not grant control authority to an arbitrary selected file. Controls from member, system/global, user, profile and selected non-base layers retain the existing refusal. Disabled processing retains the published stripping behavior.

### Call: Keep active-profile order outside format order

For each resolved active name, emit workspace JSON/YAML/TOML sources, then member JSON/YAML/TOML sources, all at priority 380, before advancing to the next active name. Check ambiguity inside each name/location/format group. A supplemental-only base gives the standard application layout for profile candidates; it does not invent a supplemental-file profile stem. Reuse loaded file identities across layouts so no profile file is read twice.

Profiles do not determine workspace identity or member selection. Isolated mode retains eligible profile files within the selected boundary. Missing active files remain not-found reports, and inactive file contents are never requested. Keep profile metadata separate from ordinary effective values and origins, and do not change source-report fields or host wire protocols.

## Risks / Trade-offs

- More file reads during workspace search: stop at the first declared workspace and reuse the parsed value in the final load. Test that no source is parsed twice.
- Existing policy changes by accident: retain unchanged default-mode tests and compare their reports byte for byte where they are serialized.
- Different roots across formats: resolve one location graph before building stage sources. Test lower-format workspace declarations and higher-format overrides.
- A selected file appears twice under normalized spellings: deduplicate file-tree identities before source execution and test `.` and `..` spellings on POSIX and Windows.
- New public policy types affect consumers: update generated interfaces and documentation in each implementation group. Keep host adapters and wire formats unchanged.

## Migration Plan

1. Add policy and result types plus a pure tracer test for one member under one workspace. Keep default behavior unchanged.
2. Add common-root format groups and supplemental sources, then extend all enabled stages.
3. Add selected-file overlay deduplication and complete-tree/partial-tree parity tests.
4. Extend the Morphir preset and native/JS adapter tests. Run the four-target gate and publish through the existing owner-approved release workflow in a later release PR.

Each group has its own tests and docs. Rollback is to select the existing policy or pin the prior release. Do not archive this proposal or claim implementation in this PR.

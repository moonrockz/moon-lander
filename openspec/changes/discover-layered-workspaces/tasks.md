# Tasks

## 1. Find a declared workspace through the public pure API

Bead: pending maintainer approval.

- [ ] 1.1 Add typed root policies and a public root result in `pkgs/config/conventions`, with a tracer test from a project to its nearest workspace; verify the same result on wasm, wasm-gc, js and native.
- [ ] 1.2 Inspect the selected workspace section in candidate documents before searching a parent, retain the nearest project fallback, and enforce boundaries; verify empty sections, nested workspaces, exclusions, missing tree entries and parse/ambiguity failures as pure tests.
- [ ] 1.3 Keep automatic member loading optional when root evidence is requested; verify an application can use the public result with its own member walk, and update `pkg.generated.mbti` plus the conventions README with a tested example.

## 2. Load ordered format groups at one root

Bead: pending maintainer approval.

- [ ] 2.1 Add validated format-group policies and supplemental sources; verify parser registration order has no precedence effect, same-group alternatives fail, and JSON/YAML/TOML layers merge with correct origins on all four targets.
- [ ] 2.2 Use the merged primary documents for workspace classification and one root decision; verify a workspace declared in JSON remains selected when TOML supplies other keys and no ancestor can replace the nearest workspace.
- [ ] 2.3 Apply declared format order inside enabled machine, global, member and adjacent-override stages while retaining stage priorities and roles; verify report order, two-layout ambiguity and YAML/YML ambiguity.
- [ ] 2.4 Document format groups and supplemental source ownership with executable examples, update public interfaces, and run unchanged default-policy convention tests to prove compatibility.

## 3. Add selected-file overlays without duplicate loads

Bead: pending maintainer approval.

- [ ] 3.1 Add an explicit selected-file overlay policy above primary layers and below member primaries; verify selected JSON overrides TOML while TOML-only keys and origins remain.
- [ ] 3.2 Deduplicate normalized file-tree identities before sources execute; verify an ordinary or supplemental selected file has one report and one transform/parse invocation, including relative path variants and Windows paths.
- [ ] 3.3 Retain the default explicit-primary behavior and typed missing/unreadable-file failures; verify existing explicit-file tests and document both policies with tested examples and updated public interfaces.

## 4. Qualify adapters and the Morphir preset

Bead: pending maintainer approval.

- [ ] 4.1 Extend the public-parts Morphir acceptance preset for workspace-first discovery, JSON5/JSON, YAML/YML, TOML, the supplemental workspace JSON file and selected overlays; verify effective values, origins and roots against complete and partial trees on all four targets.
- [ ] 4.2 Add native and JS adapter tests for a temporary member under a declared workspace, format layering and isolated boundary behavior; verify that no ancestor above the selected root or boundary is read.
- [ ] 4.3 Run `mise run check` and strict OpenSpec validation; record the actual results and retain existing source-report schemas and default-policy behavior. Update the acceptance README with the tested preset.

## Workflow follow-up

- After maintainer approval, create the epic and one dependent story bead per group, and replace the pending Bead lines before implementation.
- Keep the specification proposal separate from implementation. Archive only when implementation groups are reviewed and landed, following CONTRIBUTING.md.
- Publish through the existing owner-approved release process in a later release PR. The Morphir consumer must resolve the resulting registry version with exact pins before its group 3 implementation.

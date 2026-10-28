# Proposal

## Why

Morphir must find the first workspace by reading configuration documents, even when a nearer file defines only a project. Its approved migration also needs JSON, YAML and TOML files at one location to load as ordered layers. Version 0.6.0 has neither complete behavior, so Morphir cannot use its conventions without a local discovery implementation.

## What Changes

- Add an opt-in workspace-first root policy. It reads candidate documents, recognizes a configured workspace section, and stops at the nearest declared workspace within the boundary. With no workspace, it uses the nearest project.
- Add explicit format groups and their order. One file per group can load at each location; alternatives inside a group remain ambiguous.
- Let an application name a supplemental source below a format group, such as `morphir-workspace.json` below `morphir.json` or `morphir.json5`.
- Add an opt-in selected-file overlay above primary layers. A selected discovered file loads once in that overlay position.
- Expose selected roots and source reports through the public pure API. Applications can retain their own member walk without copying discovery code.
- Keep the current policies as defaults. Keep host I/O in the existing adapters.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `configuration-conventions`: workspace-first discovery, ordered format groups, supplemental sources, selected-file overlays, root results and compatibility defaults.

## Impact

The changes affect `pkgs/config/conventions/discovery.mbt`, `workspaces.mbt`, convention types, source reports, pure tests and native/JS adapter tests. The Morphir acceptance preset must cover the new policy. No new dependency, host package, UI or wire format is required.

Downstream: finos/morphir-moonbit [PR #268](https://github.com/finos/morphir-moonbit/pull/268), OpenSpec `adopt-moon-lander` group 3. The maintainer requested workspace-first discovery on 2026-10-28. The [Cargo workspace reference](https://doc.rust-lang.org/cargo/reference/workspaces.html) is the model for reading a workspace declaration during the upward search.

## Out of Scope

Do not implement Morphir command flags, warning suppression, TOML editing or its all-member walk here. Do not change the default legacy fallback policy, profiles, global source order, or existing MEP and Workbench protocols. Do not publish a release from this proposal PR. Implementation and publication need separate approval.

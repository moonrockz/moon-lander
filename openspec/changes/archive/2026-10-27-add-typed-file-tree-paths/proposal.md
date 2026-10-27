# Proposal

## Why

The file-tree protocol accepts raw strings although its paths have separator and
root rules. Review of PR #101 found that `C:\w\acme.toml` can request the wrong
directory, and Windows testing showed why `C:` must not stand for `C:/`.
Bead `lander-4us.47` tracks this intent.

## What Changes

- Add a config-owned `FileTreePath` with private fields, a smart constructor,
  typed parse errors, and pure path operations.
- **BREAKING**: use that type in every `FileTree` path parameter and every
  `FileRequest` payload. Migrate providers, conventions, native and JS hosts,
  browser request handling, fixtures, and compiled examples together.
- Parse portable text once where it enters the protocol. Convert Windows native
  separators at an explicit platform boundary before making the typed path.
- Preserve POSIX, Windows drive-root, UNC, and current-directory-relative paths.
  Preserve exact case, absence records, candidate error handling, and browser
  mount restrictions.
- Test constructor rules and path operations on all four targets. Verify the
  migrated adapters on Windows, macOS, Linux, Node, Bun, and real browsers through
  the existing checks.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `configuration-core`: parsed paths throughout the file-tree protocol and
  explicit conversion of Windows native paths at its boundaries.

## Impact

This changes public interfaces in `pkgs/config/` and their consumers. It adds no
runtime dependency or filesystem I/O to the pure core. Published notebooks and
OpenRPC are outside the change. The framework modules remain unpublished.

The host conversion and shared path operations overlap the path work in
`lander-4us.28` and item 7 of `lander-4us.27`. Record the covered portions there
when implementation lands; do not close either broader bead for this work alone.

## Out of scope

- Other domain types in `.27`, including configuration keys, format extensions,
  directory-entry names, and provenance location variants.
- The host error, platform fallback, warning, and interface questions in `.28`.
- New discovery rules, merge priorities, mount permissions, or filesystem access.
- Resolving symbolic links, filesystem identity, or case-insensitive matching.
- Implementation, release preparation, and package publication in this proposal.

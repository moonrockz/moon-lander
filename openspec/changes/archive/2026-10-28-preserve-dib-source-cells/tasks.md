# Preserve DIB source cells

Epic: lander-zcd

## 1. Add a compatible public lossless source mode

Bead: lander-zcd.1

- [x] 1.1 Reproduce #109 through the public notebook API and add a failing regression; verify the current writer returns one cell after a two-cell input
- [x] 1.2 Add typed source mode to construction, parse and writing with unchanged normalized defaults; verify empty, consecutive, boundary-only and zero-cell lossless round trips on all four targets
- [x] 1.3 Verify custom registries, aliases, metadata, source metadata directives and existing selector refusal through the lossless mode; retain all normalized tests
- [x] 1.4 Add runnable public examples and update the generated interface; verify documentation examples, formatting, strict OpenSpec validation and mise run check

## Workflow follow-up

- Archive this change in the implementation pull request after its tasks pass.
- After merge, close its bead and epic with the PR and merge SHA and sync beads.
- Publish only through the authorized shared-version release workflow.

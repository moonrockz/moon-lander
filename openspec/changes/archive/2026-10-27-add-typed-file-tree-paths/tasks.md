# Tasks

## 1. Type and migrate the file-tree protocol

Bead: lander-4us.47

- [x] 1.1 Add a tracer from parsed POSIX and Windows paths through a typed `ReadFile` request to a supplied tree answer and one loaded value; verify the path type, request, and value on wasm, wasm-gc, js, and native, and include a compiled usage example.
- [x] 1.2 Add the private path representation, smart constructor, typed error rules, and explicit Windows conversion; test empty text, NUL, backslashes, valid and invalid drive roots, valid and incomplete UNC roots, `.`, and existing relative files on all four targets, with accepted and rejected cases for every rule.
- [x] 1.3 Add pure parent, name, join, root, equality, hash, and segment-containment operations; verify drive and UNC roots have no parent, exact case is kept, source-relative paths use the given base, and parent segments are not folded across symbolic-link semantics; document these rules with the type.
- [x] 1.4 Migrate all seven file-tree path methods, request payloads, internal keys, load/provider paths, and conventions to the type; update their tests and compiled examples, verify no public raw-string bypass remains in the generated interfaces, and compare request rounds, merged values, origins, and reports on all four targets.
- [x] 1.5 Migrate native and JS host boundaries, including explicit file and candidate inputs, and replace duplicate protocol join/split helpers; verify native and portable Windows spellings select the same file, preserve UNC roots, reject drive-relative input before I/O, and retain PR #101's locked-entry, ambiguity, and missing-path regressions; update host documentation with the boundary conversion.
- [x] 1.6 Migrate browser request handling and explicit tree fixtures; verify mount input rejection, outside-mount errors, bounded reads, and the no-Node dependency check through the existing real-browser suite, and update the browser examples with typed requests.
- [x] 1.7 Verify Windows native, Node, and Bun execution in the existing Windows CI job, and macOS/Linux adapter runs in the existing jobs; record the runs and constructor-rule coverage in the PR, without using cross-built executables as Windows runtime proof.
- [x] 1.8 Run `mise run format`, `mise exec -- openspec validate --all --strict`, and `mise run check`; review and include generated interface changes, and complete the repository code review before the implementation PR lands.

## Workflow follow-up

- Archive this change in the PR that completes the group. Do not archive the
  separate `add-host-lifecycle` change as part of this work.
- After merge, close `.47` with the PR and merge SHA. Record which path portions
  of `.27` and `.28` landed, leave their other findings open, and sync beads.

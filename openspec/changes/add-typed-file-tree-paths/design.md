# Design

## Context

See [the proposal](proposal.md) for the problem and scope. The accepted protocol
is in `configuration-core`. `FileTree` currently uses string keys and
`FileRequest` holds strings. Core load, conventions, native/JS hosts, and browser
adapters all construct or consume these paths.

The core already supports a relative explicit file when no working directory is
given. `AbsolutePath` in `pkgs/core` represents an absolute host location; it
cannot represent this case. Browser mounts impose additional canonical-path and
containment rules. The Windows fix in PR #101 also requires a path to retain a
drive root when discovery asks for its parent.

## Goals / Non-Goals

The implementation must make the protocol typed without adding I/O to its path
operations. A valid typed path does not imply existence or permission.

Do not widen this change into all configuration path-bearing public APIs. In
particular, source-input text, report text, environment variable names, and URLs
are separate boundaries. A source can accept text and resolve it once before
the protocol; a report can render an already parsed path.

## Decisions

### D1. One config-owned protocol type (Call)

Add `FileTreePath` in `moonrockz/moon-lander-config`. Its private representation
distinguishes POSIX, drive, UNC, and current-directory roots. It supplies equality,
hashing, display, parent/name access, and relative joins. A typed suberror holds
the original input and an enum that identifies its broken rule.

Use the type for all seven path-taking `FileTree` methods and both `FileRequest`
cases. Use it for internal tree keys and the paths passed between load and its
providers. String-compatible overloads on these APIs would leave the bypass open
and are not part of the migration.

Reusing `AbsolutePath` alone would lose the relative-file case. Moving general
filesystem paths into the shared core would widen this change unnecessarily.
When an existing `AbsolutePath` enters the protocol, provide a direct checked
conversion or a conversion from its trusted components; do not weaken its rules.

### D2. Separate portable parsing from native conversion (Call)

The portable constructor rejects empty text, NUL, and backslashes. It accepts
POSIX paths, ASCII-letter drive roots followed by `/`, UNC paths with server and
share, and current-directory-relative paths. `.` represents the relative root;
an existing relative source such as `acme.toml` remains supported. A colon after
an ASCII drive letter without the root separator is a drive-relative error.

The host boundary converts backslashes only for a declared Windows run and then
parses once. The same boundary handles supplied file sources and candidates,
not only the process working directory. The pure conversion can be tested on
every target. Node and native adapters render native separators only at I/O.

Paths retain case and segment order. Do not remove `..` by pretending that a
lexical parent is the filesystem parent through a symbolic link. Browser inputs
continue to reject dot and parent segments under their existing rules. Supporting
a portable path is not authority to escape a mount.

### D3. Derive paths without printing and parsing (Call)

Implement parent, root, name, join, and segment-aware containment in the type.
Operations over trusted components return valid values without repeating a
parse. A join that accepts new text must parse that input once and return a
typed failure if it is invalid. Root parent access returns `None` for `/`, a
drive root, a UNC share root, and `.`.

Use these operations in load, conventions, and hosts instead of the duplicate
join/split helpers. Keep URL encoding and browser-specific access checks in the
browser adapter. Directory-entry names remain strings in this intent. If a name
cannot form a protocol path, an unrelated entry must not make a directory load
fail; a requested candidate must retain an explicit error. Do not silently map
such text onto a different path.

### D4. Migrate one protocol in one implementation PR (Call)

Start with a tracer test from parsed input through a typed `ReadFile` request to
a supplied tree answer. Complete the migration of all file-tree methods,
request producers, adapters, tests, consumers, and compiled examples in the same
PR. The framework modules are unpublished, so do not add an unchecked string
compatibility API. Regenerate interfaces and let compiler errors find missed
callers.

Only the path-normalization and shared-operation portions of `.28` and item 7 of
`.27` are covered. Record that overlap when this lands. Those beads remain open
for their other findings; this intent does not require their unrelated fixes.

### D5. Discovery keeps its rule for `..` in run inputs (Call)

`FileTreePath` never applies `..`. Discovery keeps its accepted rule for the
paths that a run gives it: the working directory, a relative boundary, an
explicit file such as `../configs/project.yaml`, and a relative directory
variable. It applies each `..` name to the name before it, never above the root,
as a typed step over the parsed names, and it does not print and parse the path.
The scenario "Explicit file from another directory" of `configuration-conventions`
depends on this rule. A change to it is a new discovery rule, which is out of
scope.

### D6. Native separators and listed names at the host (Call)

The host gives the process working directory in its native form, and the pure
load parses it and every file source with `FileTreePath::from_native` for the
platform of the run. A host renders native text with `to_native` only for a file
call. A host joins a listed entry name to the native directory text for its
inspection, so an entry name that cannot form a file-tree path, such as a Linux
name with `\`, never makes a listing fail. A wildcard member pattern that selects
such a name raises `InvalidFilePath` for it. A variable that gives a directory
and is not a valid path counts as not set and gives a `Note` warning.
`FileTreePath::from_absolute` converts a `@lander_core.AbsolutePath` with the path
rules, because `AbsolutePath` allows `\` in a POSIX path.

## Risks / Trade-offs

- A typed request can compile while changing lookup identity. Compare values,
  origins, reports, and request rounds before and after migration, including
  incomplete trees, roots, relative files, and similarly named directories.
- A broad catch of path failures could hide a candidate. Retain the locked-entry,
  explicit-file, ambiguity, and member-directory negative controls from PR #101.
- Browser paths have stricter rules than host paths. Retain construction-time
  rejection and outside-mount checks, and run real browser acceptance tests.
- Windows native spelling can enter through more than the working directory.
  Cover explicit files, candidate lists, and UNC paths under Windows Node, Bun,
  and native execution in the existing CI jobs.

## Migration Plan

1. Introduce the type and its boundary/operation tests with the protocol tracer.
2. Migrate the whole protocol and its adapters; update fixtures and documentation
   with the changes that need them.
3. Run strict OpenSpec validation, formatting, the required workspace check, and
   the existing platform acceptance checks. Review generated interfaces.
4. Archive this change in its final implementation PR. After merge, close `.47`
   with the PR and merge SHA, record the overlap on `.27` and `.28`, and sync.

If verification finds incompatible behavior, fix the migration before merge.
After merge, rollback is a normal source revert; there is no stored data format
or package publication in this change.

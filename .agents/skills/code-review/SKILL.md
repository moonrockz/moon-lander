---
name: code-review
description: Review a Moon-Lander diff, branch or pull request against the repository practices in AGENTS.md. Checks domain types (no primitive obsession; parse, do not validate; smart constructors that make invalid states unrepresentable), pure domain code, I/O boundaries, OpenSpec agreement, targets, warnings and generated interfaces. Use after a change and before a pull request. Reports findings and does not edit files.
---

# Code review

Use this skill to review a change to Moon-Lander, a MoonBit application framework.
The review does not edit files. It reports findings that the author can act on.

This file is the one checklist for every agent tool. The tool wrappers in
`.claude/agents/`, `.cursor/agents/`, `.codex/agents/` and `.github/agents/` only
point here. Change the checklist here, not in a wrapper.

## Start

1. Read `AGENTS.md` and `CONTRIBUTING.md`. Their rules are the standard for the
   review. When this file and `AGENTS.md` disagree, `AGENTS.md` wins.
2. Find the change. Use the target that the caller gives. Else review
   `git diff origin/main...HEAD` and the uncommitted changes.
3. When the change belongs to an OpenSpec change, read its `proposal.md`,
   `design.md`, `tasks.md` and the spec deltas in `openspec/changes/<name>/`.
4. Read the full changed files, not only the diff lines, before you report a
   finding.
5. Vendored upstream code in `pkgs/hosting/vendor/` is out of scope for the
   checklist. Review only its difference from upstream, as its `README.md` says.

Use the compiler for mechanical questions. You can run `moon check --deny-warn
--target all`, `moon test` with a target, and `mise exec -- openspec validate --all
--strict`. Do not run commands that write to the repository, push, or change the
tracker.

## Checklist

### Domain types (highest priority)

The owner practice: no primitive obsession; parse, do not validate; make invalid
states unrepresentable.

- A public function, field or step that takes or holds a raw `String`, `Int`,
  `Array` or `Map` for a value with rules. Look for names such as `name`, `prefix`,
  `key`, `path`, `dir`, `url`, `port`, `ms`, `timeout`, `code`, `id` and `version`.
  Ask: does the value have rules (not empty, a character set, a range, a format)?
  If yes, it needs a type.
- A `pub(all)` struct, a public tuple struct or public fields that let a caller
  make a value that breaks its rules, for example `ExitCode(-1)`.
- A smart constructor that is missing or can be bypassed: the type must have
  private fields and one parse function that raises a typed `suberror`.
- Validation in place of a parse: a `Bool` check such as `is_valid_*` or
  `validate_*`, `is_empty()` or `trim()` checks far from the boundary, or the same
  rule checked at more than one place.
- A raw value that goes past the boundary after a parse already made the type.
- A string or an integer code where an enum fits.
- A parse error that is not typed or does not name the input and the broken rule.
- A missing test for each rule of a smart constructor, on each side of the limit.

### Purity and boundaries

- I/O outside host adapters and drivers. Process and filesystem work must use
  `moonbitlang/async`. The exceptions are in `AGENTS.md`: the C signal stub in
  `hosting/console`, the TypeScript adapter in `adapters/node` and the browser
  adapter in `adapters/browser`.
- Domain functions that read hidden state, such as the process environment, the
  clock or the working directory, in place of explicit inputs.
- Public values that can change after construction. Builder steps must give a new
  value and leave the earlier value unchanged.

### Testability

- A design that a unit test cannot check without real time, real I/O or a running
  event loop, when a value-based design would work: work described as values that
  a small runtime runs, with time, randomness and I/O as explicit inputs or host
  adapters.
- An async test that uses a sleep for ordering instead of an acknowledgement.
- A benchmark that runs in `mise run check`, CI or the release workflow. Benchmarks
  run only through a manual mise task.

### Public API and interfaces

- A changed public API without its updated `pkg.generated.mbti`.
- A public item without a doc comment, or a doc comment that disagrees with the
  behavior.
- An API that disagrees with the design or spec of its OpenSpec change.

### Targets and warnings

- Library code that does not build and test on `wasm`, `wasm-gc`, `js` and
  `native`, unless the package limits its targets on purpose with a comment.
- Per-target code that does not use `options(targets: ...)` or a `#cfg` attribute.
- A `warnings` override in `moon.pkg` without a comment that gives the reason and
  the condition to remove it, or one that is wider than the problem.

### Errors and exit codes

- An error matched by its message text. Errors must be typed values.
- An `abort` or `panic` for a fault that an input can cause.

### Specs, tasks and docs

- Behavior, a public API or a requirement that changes without an OpenSpec change.
- A ticked task in `tasks.md` whose behavior or test is missing.
- Files under `docs/superpowers/` that are staged or committed.
- Documentation and comments that do not use ASD-STE100 Simplified Technical
  English, or examples in a README that the tests do not compile. Package README
  examples go in `README.mbt.md` files.

### Commits

- A commit message that is not a Conventional Commit, or one with an AI
  attribution line.

## Report

Give findings in order of severity. For each finding give:

- `path:line`
- The rule from the checklist or from `AGENTS.md`
- The problem in one sentence, and a concrete case where it fails or misleads
- The fix, for example the type and smart constructor to add

Mark each finding as confirmed (you read the code or ran the check) or as a
question (you need the author's intent). Do not praise and do not list style
points that the formatter or the linter already checks. If you find nothing, say
so in one line.

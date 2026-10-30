# Spec Delta

## Purpose

Let a stock Moonx parent preserve original POSIX stop signals, retain actual
Windows cancellation outcomes, and own a private on-disk Node payload through
final process cleanup.

## ADDED Requirements

### Requirement: Typed immutable launch plans

The module SHALL construct immutable command, argument, payload and shutdown
policy values at the input boundary. Construction failures MUST name the input
and the broken rule with typed error cases. Valid constants and values derived
from valid values MUST have constructors that cannot fail.

#### Scenario: Opaque application arguments

- **WHEN** an argument list contains empty strings, delimiters, spaces, quotes, newlines and Unicode
- **THEN** construction preserves each element and its order without splitting or normalization

#### Scenario: Invalid process inputs

- **WHEN** an executable is empty, an executable or argument contains NUL, or a shutdown deadline is not positive
- **THEN** construction fails with the input and the corresponding typed rule

### Requirement: Portable payload file paths

Payload file paths SHALL be portable ASCII names relative to the owned root.
Construction MUST reject absolute paths, traversal, empty or dot segments,
backslashes, controls, non-ASCII, reserved syntax, names and short-name aliases.
Layouts MUST reject duplicate identities, inconsistent directory case,
file-directory conflicts and an entry that is not one of their files.

#### Scenario: Asset-name restriction leaves application inputs opaque

- **WHEN** an asset path contains non-ASCII text
- **THEN** construction rejects that name while Unicode remains supported in application arguments, cwd, host temporary paths and file bytes

#### Scenario: Reject traversal before I/O

- **WHEN** a file path contains a leading separator, `..`, `.`, a repeated separator or a backslash
- **THEN** construction fails before a directory or file is created

#### Scenario: Reject an ambiguous file layout

- **WHEN** two file entries have the same portable path identity or one file path is a parent of another file
- **THEN** payload construction fails with a typed collision error

#### Scenario: Preserve a valid layout

- **WHEN** a payload contains `package.json`, a nested entry and nested runtime files
- **THEN** construction retains each file's relative name and exact bytes

### Requirement: Exact child transport and finite status

The launcher SHALL pass argument arrays and binary standard streams without
interpretation. Standard output and standard error MUST remain separate. A
finite child status MUST select the corresponding parent status after cleanup.
An unexpected child signal MUST use its conventional process status.

#### Scenario: Finite binary process

- **WHEN** a child receives binary stdin, writes binary stdout and separate stderr, and exits 23
- **THEN** the observed bytes and channels are unchanged and the parent exits 23 after cleanup

#### Scenario: No shell argument interpretation

- **WHEN** the launch plan has empty arguments, option-looking strings, delimiters and Unicode
- **THEN** the child receives the same array and no shell interprets its contents

### Requirement: Original cancellation signal

On POSIX process hosts, the launcher SHALL forward the first received SIGINT
or SIGTERM to its owned child. On every supported host the observation MUST remain typed,
non-consuming and available during protected cleanup. Ordinary task
cancellation MUST NOT be reported as an observed OS signal.

#### Scenario: Interrupt a genuine Node-owned host

- **WHEN** POSIX SIGINT is sent only to a ready launcher whose Node child owns a Moon-Lander host
- **THEN** that host reports Interrupt and completion 130 after its finalizer, and the parent selects 130

#### Scenario: Terminate a genuine Node-owned host

- **WHEN** POSIX SIGTERM is sent only to a ready launcher whose Node child owns a Moon-Lander host
- **THEN** that host reports Terminate and completion 143 after its finalizer, and the parent selects 143

#### Scenario: Repeated signal reads

- **WHEN** cleanup reads the signal more than once after a second signal arrives
- **THEN** the observed cancellation identity remains the first received signal

### Requirement: Truthful Windows console semantics

The Windows launcher SHALL retain actual child and parent cancellation outcomes.
Stock Moonrun Ctrl-C delivery MUST be documented as Ctrl-Break, with genuine
Quit/131 and the parent's original Interrupt observation and full status.
It MUST NOT claim original Windows Ctrl-C forwarding or describe SIGTERM as a
console event. Finite transport, payload lifetime, Ctrl-Break and bounded forced
cleanup MUST remain supported. Existing framework hosts MUST remain unchanged.

#### Scenario: Ordinary-console Node baseline

- **WHEN** direct Node owning a Moon-Lander host receives Ctrl-C in an isolated ordinary Windows console with handling enabled
- **THEN** its genuine host reports Interrupt and completion 130, establishing a baseline separate from the launcher

#### Scenario: Stock Moonrun receives Ctrl-C

- **WHEN** Ctrl-C reaches a ready Moonrun launcher at commit `2284bd2` or `3778465` whose Node child owns a Moon-Lander host
- **THEN** the parent records Interrupt, the genuine Node host reports Quit and completion 131, and the parent retains status bits `0xc000013a` after worker, service and finalizer completion and child reaping

#### Scenario: Targeted Ctrl-Break

- **WHEN** targeted Ctrl-Break reaches a ready Moonrun or native launcher whose Node child owns a Moon-Lander host
- **THEN** its genuine Node host reports Quit and completion 131, the parent records Break and its full Windows status, and finalization and reaping complete with idle stdin held open

#### Scenario: Ignored Ctrl-Break

- **WHEN** an owned Node payload acknowledges but ignores Ctrl-Break through the graceful deadline
- **THEN** the launcher records the actual hard-termination request and child status, reaps the child, removes its payload, and finalizes once while preserving the parent's real Windows cancellation status

### Requirement: Bounded owned-child cleanup

The launcher SHALL wait for its child to terminate before parent exit. If the
child does not complete within the selected graceful-stop deadline, the
launcher MUST force termination and reap it. Idle stdin MUST NOT prevent
cancellation or reaping. The Node owner MUST remain able to stop worker work
that does not yield.

#### Scenario: Ignore the graceful signal

- **WHEN** the child ignores the forwarded signal until the graceful deadline expires
- **THEN** forced cleanup reaps it before the parent exits and protected finalization still runs once

#### Scenario: Held-open stdin

- **WHEN** the parent receives a signal while its stdin writer remains open and sends no data
- **THEN** the child completes or is forced to stop without waiting for stdin EOF

#### Scenario: Non-yielding Node worker

- **WHEN** the Node owner receives the forwarded signal while its hosted worker polls a shared stop probe without yielding
- **THEN** the genuine host observes the delivered signal and reports its actual completion after cleanup under the platform's documented signal contract

### Requirement: Private Node payload lifetime

The launcher SHALL create a new exclusively owned payload directory, with
owner-only access on POSIX hosts. It MUST materialize only validated relative
file entries, preserve their exact bytes and layout, and invoke Node with the
selected entry and application arguments. The caller's working directory and
stdin MUST remain available to the application.

#### Scenario: Package and worker layout

- **WHEN** a payload has a package manifest, entry wrapper, worker and runtime files
- **THEN** Node resolves those files in the retained layout while the application sees the caller's working directory and opaque stdin

#### Scenario: Partial materialization failure

- **WHEN** a file write fails after the private directory is created
- **THEN** the launcher starts no child and removes its partially materialized directory during protected finalization

### Requirement: Unconditional finalization and owned-file cleanup

The launcher SHALL finalize one time after child reaping or startup failure.
Payload cleanup MUST remove only the owned directory and MUST NOT follow
symlinks out of it. Cleanup and optional finalization MUST be protected from
cancellation. A finalization failure MUST turn selected success into failure
and preserve an already selected nonzero or signal status.

#### Scenario: Node is unavailable

- **WHEN** Node is missing or process startup fails after payload creation
- **THEN** the launcher reports the failure, selects failure and removes its private directory without leaving a child

#### Scenario: Child creates a symlink

- **WHEN** the stopped child left a symlink to an external directory inside its payload directory
- **THEN** cleanup removes the symlink and owned files while the external directory remains unchanged

#### Scenario: Preserve finite failure through finalization

- **WHEN** a child exits 23 and optional finalization raises
- **THEN** finalization runs once, owned files are removed and the selected status stays 23

### Requirement: Typed completion after cleanup

The public driver SHALL report a typed outcome after child reaping, payload
cleanup and optional finalization. The outcome MUST distinguish a child that
never started from a child that started, retain startup failure or cancellation
cause, and report child completion, forced termination and the selected process
status. It MUST preserve the full Windows status bit pattern. The application
owns result formatting; the driver MUST NOT interpret child output or emit an
application result document.

#### Scenario: Cancellation during materialization

- **WHEN** cancellation stops materialization before process creation
- **THEN** completion reports not-started with the observed cancellation cause after removing the partial payload

#### Scenario: Application-owned startup reporting

- **WHEN** the completion callback receives a not-started failure or cancellation
- **THEN** it can format its own startup result from typed values without inspecting stdout or reimplementing process lifetime

#### Scenario: Started child owns its output

- **WHEN** the child has started and has written an application result
- **THEN** the parent completion identifies it as started and adds no application document to stdout

### Requirement: Isolated optional parent runtime

The optional launcher SHALL own one runtime in the parent process and MUST NOT
mix it with canonical async in that executable. Async values and type
identities MUST NOT cross the process boundary. Existing host, actor and
embedded consumers MUST retain their APIs, dependency identities and behavior.

#### Scenario: Separate parent and Node host

- **WHEN** the launcher and a canonical Node host are built and run
- **THEN** the parent executable contains only its owned runtime and the child contains only canonical async

#### Scenario: Existing framework consumers

- **WHEN** an application uses the existing native, JS or embedded host without importing the optional module
- **THEN** its dependency graph, public API and default lifecycle behavior are unchanged

### Requirement: Licensed runtime provenance and return path

The compatibility source SHALL identify its immutable upstream archive and
checksum, selected source files, license, retained tests and local changes.
It MUST retain required notices and define an update and removal procedure.
An external upstream release MUST NOT be a prerequisite for this release.

#### Scenario: Source drift

- **WHEN** a frozen source file differs from the recorded source plus its declared mechanical or semantic patch
- **THEN** provenance verification fails before release

#### Scenario: Upstream observer becomes available

- **WHEN** a public upstream release supplies the required observer on both supported stock toolchains
- **THEN** the documented return procedure requires the same isolation, lifecycle and registry acceptance proof before removing the frozen subset

### Requirement: Public generic Moonx launcher command

The optional module SHALL provide `/launch` as a thin caller of the public
driver. It MUST preserve child argv and streams. Its `--json` mode SHALL own
help, usage-error and not-started reports only. Once a child starts, its output
MUST remain opaque and the launcher MUST NOT append an application document.
The command MUST document its report schema and argument boundary.

#### Scenario: JSON startup failure

- **WHEN** `/launch --json --` cannot start the selected executable
- **THEN** it emits one versioned not-started JSON report and exits with the selected failure status

#### Scenario: Child JSON ownership

- **WHEN** `/launch --json --` starts a child that emits JSON and exits 23
- **THEN** stdout contains only those exact child bytes and the parent exits 23

#### Scenario: Help and opaque child options

- **WHEN** the launcher receives `--help --json`, or child arguments after the executable contain `--json` and `--help`
- **THEN** the former reports JSON help without starting a child and the latter forwards those arguments unchanged

### Requirement: Stock and public artifact qualification

Release qualification SHALL exercise stock `0.10.16+b1a0e846e` and
`0.10.17+d971670cd`, including genuine top-level Moonx and real Node-host
completion under the declared platform contract. After publication, fresh
consumers MUST use the default public
registry with no source override. Every released archive checksum MUST match
the actual approved release artifact.

#### Scenario: Platform-specific signal evidence

- **WHEN** host qualification runs on both required stock toolchains
- **THEN** POSIX proves original SIGINT/130 and SIGTERM/143, while Windows retains actual Ctrl-C-to-Ctrl-Break delivery, full parent status, graceful and forced cleanup, and opaque finite transport

#### Scenario: Local candidate proof

- **WHEN** a candidate is tested through a loopback registry
- **THEN** its evidence is identified as candidate proof and does not count as actual public publication proof

#### Scenario: Fresh public consumers

- **WHEN** the approved release has published
- **THEN** independent cold consumers resolve and execute the public module on both stock toolchains and verify the actual released archive identities

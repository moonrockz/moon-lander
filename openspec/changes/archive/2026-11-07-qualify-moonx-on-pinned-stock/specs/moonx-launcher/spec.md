# Moonx launcher specification delta

## ADDED Requirements

### Requirement: Pinned stock and public artifact qualification

Release qualification SHALL exercise the stock toolchain of the primary MoonBit
pin, including genuine top-level Moonx and real Node-host completion under the
declared platform contract. After publication, fresh consumers MUST use the
default public registry with no source override. Every released archive
checksum MUST match the actual approved release artifact.

#### Scenario: Platform-specific signal evidence

- **WHEN** host qualification runs on the pinned stock toolchain, `0.10.20+65efd5b93` at this change
- **THEN** POSIX proves original SIGINT/130 and SIGTERM/143, while Windows retains actual Ctrl-C-to-Ctrl-Break delivery, full parent status, graceful and forced cleanup, and opaque finite transport

#### Scenario: Other stock toolchains

- **WHEN** a stock toolchain other than the primary pin, such as `0.10.17+d971670cd`, is given to the qualification
- **THEN** the qualification refuses it as an unsupported stock toolchain before it builds a consumer

#### Scenario: Local candidate proof

- **WHEN** a candidate is tested through a loopback registry
- **THEN** its evidence is identified as candidate proof and does not count as actual public publication proof

#### Scenario: Fresh public consumers

- **WHEN** the approved release has published
- **THEN** independent cold consumers resolve and execute the public module on the pinned stock toolchain and verify the actual released archive identities

## MODIFIED Requirements

### Requirement: Truthful Windows console semantics

The Windows launcher SHALL retain actual child and parent cancellation outcomes.
Ctrl-C delivery of the qualified stock Moonrun MUST be documented as Ctrl-Break, with genuine
Quit/131 and the parent's original Interrupt observation and full status.
It MUST NOT claim original Windows Ctrl-C forwarding or describe SIGTERM as a
console event. Finite transport, payload lifetime, Ctrl-Break and bounded forced
cleanup MUST remain supported. Existing framework hosts MUST remain unchanged.

#### Scenario: Ordinary-console Node baseline

- **WHEN** direct Node owning a Moon-Lander host receives Ctrl-C in an isolated ordinary Windows console with handling enabled
- **THEN** its genuine host reports Interrupt and completion 130, establishing a baseline separate from the launcher

#### Scenario: Stock Moonrun receives Ctrl-C

- **WHEN** Ctrl-C reaches a ready Moonrun launcher of the pinned stock toolchain whose Node child owns a Moon-Lander host
- **THEN** the parent records Interrupt, the genuine Node host reports Quit and completion 131, and the parent retains status bits `0xc000013a` after worker, service and finalizer completion and child reaping

#### Scenario: Targeted Ctrl-Break

- **WHEN** targeted Ctrl-Break reaches a ready Moonrun or native launcher whose Node child owns a Moon-Lander host
- **THEN** its genuine Node host reports Quit and completion 131, the parent records Break and its full Windows status, and finalization and reaping complete with idle stdin held open

#### Scenario: Ignored Ctrl-Break

- **WHEN** an owned Node payload acknowledges but ignores Ctrl-Break through the graceful deadline
- **THEN** the launcher records the actual hard-termination request and child status, reaps the child, removes its payload, and finalizes once while preserving the parent's real Windows cancellation status

### Requirement: Licensed runtime provenance and return path

The compatibility source SHALL identify its immutable upstream archive and
checksum, selected source files, license, retained tests and local changes.
It MUST retain required notices and define an update and removal procedure.
An external upstream release MUST NOT be a prerequisite for this release.

#### Scenario: Source drift

- **WHEN** a frozen source file differs from the recorded source plus its declared mechanical or semantic patch
- **THEN** provenance verification fails before release

#### Scenario: Upstream observer becomes available

- **WHEN** a public upstream release supplies the required observer on the pinned stock toolchain
- **THEN** the documented return procedure requires the same isolation, lifecycle and registry acceptance proof before removing the frozen subset

## REMOVED Requirements

### Requirement: Stock and public artifact qualification

**Reason**: MoonBit 0.10.20 uses the `#derive(...)` attribute, which stock
`0.10.16+b1a0e846e` and `0.10.17+d971670cd` do not apply, so one source cannot
build on both those stocks and the pinned toolchain. The owner chose
qualification on the pinned stock toolchain.

**Migration**: Use "Pinned stock and public artifact qualification". A consumer
on stock 0.10.16 or 0.10.17 keeps `moonrockz/moon-lander-moonx@0.11.0`.

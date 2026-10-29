# configured-dib-codec Specification

## Purpose
Reuse typed kernel descriptors and one immutable source policy across DIB construction, reading and writing.

## Requirements

### Requirement: Typed reusable kernel description

A public open kernel descriptor trait SHALL return an immutable KernelInfo.
KernelInfo SHALL implement that trait. A configured codec SHALL accept descriptors
without requiring wrapper types. It SHALL retain typed registry collision errors.

#### Scenario: Consumer-provided kernel

- **WHEN** a consumer registers Python and MoonBit descriptors with aliases
- **THEN** the configured codec recognizes their selectors and aliases

### Requirement: Consistent source policy

A configured codec SHALL apply one source mode to construction, reading and
writing. Existing functions SHALL retain Normalized defaults. A lossless
constructor SHALL select Lossless without further source-mode arguments.
An omitted custom default SHALL use the standard registry. A supplied descriptor
SHALL start a custom registry with that default, with Markdown available.

#### Scenario: Empty custom-kernel cells

- **WHEN** empty and boundary-only custom cells are constructed and round-tripped through a lossless codec
- **THEN** their sources and boundaries are retained without repeated options

#### Scenario: Duplicate registration

- **WHEN** a descriptor conflicts with an existing name or alias
- **THEN** the codec raises the existing typed duplicate-kernel error

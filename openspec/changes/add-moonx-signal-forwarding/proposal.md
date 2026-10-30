# Proposal

## Why

Stock Moonx runs a Wasm parent. The public async cancellation policy can send
one configured child signal, so parent SIGINT can become Node SIGTERM and
change the real application host's stop reason and completion code.
Applications need an original-signal launcher and a private lifetime for an
embedded Node payload without waiting for a third-party release.

## What Changes

- Add the optional `moonrockz/moon-lander-moonx` module in `pkgs/moonx`.
- Provide portable immutable command, argument, relative-file, payload and
  shutdown policy values with typed construction errors.
- Add a synchronous process driver for stock Wasm and native hosts. It forwards
  the first received SIGINT or SIGTERM, preserves process transport and statuses,
  reaps its child and completes protected finalization before the parent exits.
- Materialize immutable Node payload files in a newly owned private directory,
  preserve their layout and the caller's working directory, launch the selected
  entry with opaque application arguments, and remove the directory after reaping.
- Freeze the approved production dependency subset of Apache-2.0
  `moonbitlang/async@0.22.5` under this module. Retain source provenance and tests.
  Use a public explicit runtime entry and a typed first-signal observer.
- Extend candidate and public registry checks to the new library. Qualify both
  stock compilers and real Node-owned host completion, including top-level Moonx.

Out of scope are Morphir-specific payload assembly, hashing and embed generation,
application output schemas, a Node installer, new UI, actor changes, changes to
canonical async or the existing host drivers, and a custom compiler or Moonrun.
The external async contribution is nonblocking.

## Capabilities

### New Capabilities

- `moonx-launcher`: typed process plans, original-signal child forwarding, private
  Node payload lifetime, isolated runtime provenance and stock consumer proof.

### Modified Capabilities

- `framework-modules`: register the optional parent-only module and its isolated
  dependency direction at the shared workspace version.
- `framework-publication`: publish and audit the eleventh library and require
  its candidate and public consumer proof before release promotion.

## Tracking

Epic: `lander-pq1`.
Public request: [Moon-Lander #140](https://github.com/moonrockz/moon-lander/issues/140).
Nonblocking return path: [async #706](https://github.com/moonbitlang/async/issues/706).
The owner approved the frozen 21-package production subset and maintenance cost,
implementation, reviewed green CI, merge, release and independent public proof.
The owner also approved a thin `/launch` executable inside this optional module
as a narrow exception to executable placement under `apps/`. It enables genuine
public Moonx asset proof, calls only the public driver, and owns command help,
usage errors and typed not-started reporting. It does not own application output.

## Impact

The new module owns the parent's compatibility runtime. Existing hosting,
actors and embedded APIs keep their dependencies and behavior. The umbrella
does not import the new module. Runtime values do not cross the process boundary.

Workspace, version, publication and registry validation gain one module. The
existing CI category gains focused launcher checks. Release proof covers the
actual archives and fresh default-registry consumers on stock
`0.10.16+b1a0e846e` and `0.10.17+d971670cd`.

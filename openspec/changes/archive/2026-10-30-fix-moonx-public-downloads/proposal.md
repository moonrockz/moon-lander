# Proposal

## Why

The actual 0.9.0 release and independent public qualification stop at the
registry's HTTP 302 response. The pinned async HTTP client sends one request;
the checker must follow the registry's CDN redirect before it checks bytes.

## What Changes

- Follow a bounded HTTP redirect chain for the public source archive, Wasm
  asset and checksum sidecar.
- Use the stock client's default `/prebuild/` endpoint and read the first
  checksum token from its SHA256SUM sidecar, as the stock client does.
- Keep the approved archive digest and advertised asset digest checks.
- Test redirects, bad responses and redirect loops with a local HTTP server.
- Correct task descriptions to name all eleven release libraries, and update
  the root README's version and public Moonx command.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

None. This tooling repair implements the existing stock and public artifact
qualification requirement. It changes no specification requirement.

## Tracking

- Bug: `lander-pq1.5`.
- Keep the separate public release gate `lander-pq1.4` open.
- Follow-up to issue #140 and the archived `add-moonx-signal-forwarding` change.

## Impact

Only qualification tooling, its tests, task descriptions and the root README change. Published
package files, versions, APIs, native and embedded behavior, actor and Sigstore
work, downstream code and toolchains are out of scope. Existing 0.9.0 uploads
must remain unchanged. A fresh Release workflow run must prove that its archive
approval map equals the original map before release promotion.

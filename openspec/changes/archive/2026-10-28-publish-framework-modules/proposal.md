# Publish framework modules

## Why

The 0.3 through 0.5 releases omitted the framework libraries. External applications need exact registry versions of these modules.

## What changes

- Publish all seven framework libraries, notebooks and OpenRPC at the shared release version, in dependency order.
- Keep tooling and tests private and enforce the publication list.
- Verify candidate archives before merge and public archives before creating the GitHub release.

## Capabilities

### New capabilities

- `framework-publication`: library publication policy and registry consumer release gates.

### Modified capabilities

None.

## Impact

Release scripts, module manifests, CI, registry consumers and release documentation. No library API changes.

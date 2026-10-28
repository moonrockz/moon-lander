# Design

## Context

Workspace builds can hide missing registry packages and archive files. The current publisher lists only notebooks and OpenRPC.

## Decisions

### D1: Publish nine libraries, Owner

Use the seven framework names in moon.work and their manifests, plus notebooks and OpenRPC. Use 0.6.0 for every member and sibling import. Publish core, logging, config, mediator, logging-hosting-async, hosting, umbrella, notebooks, then OpenRPC.

### D2: Enforce the boundary, Call

Keep an explicit allowlist in the publisher. Mark every other workspace module and generated consumer private. Check the allowlist, workspace membership, manifest names and sibling pins before packaging or publishing. The pinned toolchain rejects private publication.

### D3: Qualify registry archives, Call

Use the existing task-script CI category and full local/release check for candidate consumers. Serve packaged archives through a loopback registry with isolated dependency caches and no workspace overrides. Each library has a consumer on all four targets; target-limited adapters get additional supported-target consumers. Audit archive entries, licenses and versioned sibling imports. Log archive checksums and resolved graphs. The release publisher records the approved checksums before upload. The public check compares every downloaded archive with those checksums and blocks GitHub release creation on failure. Retain the OpenRPC consumer and public format override gate.

### D4: Recover without overwriting, Owner

Only GitHub Actions may publish. Stop on a failed dependency. An existing version is acceptable on a retry only when its public archive matches the approved checksum. Do not overwrite tags, releases or registry entries.

## Execution and risk

Missing archives or adapter files would break external consumers after publication, a high-impact release failure. Candidate registry checks belong in the existing task-script category before merge. Public checks require publication and therefore run only between publishing and GitHub release creation. Release maintainers own failures. No nightly evidence substitutes for the exact release candidate. Runtime remains unmeasured until the first run; no new job or target matrix is needed.

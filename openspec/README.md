# OpenSpec

## Shared OpenSpec bundle

`html-design` comes from Mission Control's tools CLI, `mission-control-tools`, pinned in
`.config/mise/config.toml`. The schema, templates and licenses are managed snapshots, with their
digests in `openspec/extensions.lock.json`; keep repository overrides in `openspec/config.yaml` and
`AGENTS.md`.

- Run `mise run openspec:check` to verify the committed file digests, the default schema and the
  tool version in the lock (`mission-control-tools openspec check --bundle`). The CI lint job runs it too.
- Run `mise run openspec:setup` to regenerate the core agent skills with isolated global preferences.
- Run `mise run openspec:validate` (`openspec schema validate html-design` and
  `openspec validate --all --strict`) before review, or `mise run openspec:verify` for both tasks.
- New designs are offline `design.html` with inline CSS. Existing changes keep
  their schema metadata and original designs, including Markdown designs.
- OpenSpec requirements and change artifacts are committed project documentation.
  Scratch documents remain local under the existing repository rules.

To update the snapshots, change the `github:moonrockz/mission-control` version in
`.config/mise/config.toml`, run `mise install`, then `mise exec -- mission-control-tools openspec install`,
and run this repository's checks. The managed files are compared byte for byte, so
`.gitattributes` keeps LF line endings for `openspec/schemas/html-design/**`.
See [the tools guide](https://github.com/moonrockz/mission-control/blob/tools-v0.1.1/apps/tools/README.md).

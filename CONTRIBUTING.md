# Contributing to Moon-Lander

Read [the README](README.md) first to set up the toolchain. This guide tells you how
to plan a change, track it, and get it ready for review.

## How work moves

1. Write or update an OpenSpec change. It holds the requirements and the design.
2. Track the implementation in beads (`bd`). Each task group in the change has one bead.
3. Implement one bead at a time. Tick its tasks in the change.
4. Run the checks and open a pull request.
5. Archive the change after it merges.

A typo fix, a dependency bump or a build-only change does not need an OpenSpec change.
A change to public behavior, a public API or a requirement needs one.

## OpenSpec

[OpenSpec](https://github.com/Fission-AI/OpenSpec) is pinned in
`.config/mise/config.toml`. `mise install` installs it. Run it through mise:

```shell
mise exec -- openspec list                  # changes in progress
mise exec -- openspec list --specs          # accepted specifications
mise exec -- openspec show <change>         # one change
mise exec -- openspec view                  # interactive dashboard
mise exec -- openspec validate --all --strict
```

The files are in `openspec/`:

| Path | Contents |
| --- | --- |
| `openspec/config.yaml` | Project context and rules that every change follows |
| `openspec/specs/<capability>/spec.md` | Accepted requirements, one folder for each capability |
| `openspec/changes/<change>/` | A change in progress |
| `openspec/changes/archive/` | Changes that are complete |

A change folder has these files:

| File | Contents |
| --- | --- |
| `proposal.md` | Why the change is necessary, what it changes, and what is out of scope |
| `design.md` | How the change works. Each decision has a label: "Owner" for a maintainer decision, or "Call" for a decision of the author |
| `specs/<capability>/spec.md` | Requirement changes under `## ADDED`, `## MODIFIED` or `## REMOVED Requirements` headings. Each `### Requirement:` uses SHALL or MUST and has one or more `#### Scenario:` blocks with **WHEN** and **THEN** lines |
| `tasks.md` | Task groups. Each group is one story and has a `Bead:` line with its beads ID |

### Write a change

Use kebab-case names that start with a verb, for example `add-configuration-core`.

With Claude Code, use the commands that `openspec init` installed in `.claude/`:

| Command | Use |
| --- | --- |
| `/opsx:explore` | Examine an idea or a problem before you write a change |
| `/opsx:propose` | Make a change and write all of its files |
| `/opsx:update` | Revise the files of a change and keep them consistent |
| `/opsx:apply` | Implement the tasks of a change |
| `/opsx:sync` | Copy the requirement changes into `openspec/specs/` without archiving |
| `/opsx:archive` | Archive a complete change |

Without an agent, run `mise exec -- openspec new change <name>`. Then run
`mise exec -- openspec instructions <artifact> --change <name>` to see the template
and the rules for each file.

Follow these rules:

- Write in ASD-STE100 Simplified Technical English.
- Make each scenario specific enough that a test can check it.
- Put the first task group as a tracer bullet: a thin path through the full change.
  If a decision depends on something nobody has tried yet, make the first group a
  spike that tries it.
- Do not put the content of `openspec/config.yaml` into the change files.
- Run `mise exec -- openspec validate <change> --strict` before you ask for review.

### Track the work in beads

After a maintainer approves the change, make one bead for each task group. Put the
beads under one epic for the change, and write each ID on the `Bead:` line of its group.
Add a dependency between beads when one group needs the result of another.

```shell
bd ready                     # beads with no open blockers
bd show <id>                 # one bead and its dependencies
bd update <id> --claim       # start work on a bead
bd close <id>                # after its tasks are done and verified
```

### Implement and finish

1. Claim a bead. Do the tasks of its group, then tick each one in `tasks.md` (`- [x]`).
2. Run `mise run format` and `mise run check`.
3. Close the bead.
4. When all groups are done, archive the change:
   `mise exec -- openspec archive <change>`. This moves the change to
   `openspec/changes/archive/` and merges its requirement changes into
   `openspec/specs/`.

Releases run only in GitHub Actions (`.github/workflows/release.yml`, adapted
from [Smithy's release flow](https://github.com/moonrockz/smithy/blob/main/.github/workflows/release.yml)).
Ask the owner before opening or merging a release pull request; merging it is
the publication approval. The pull request sets the shared version with
`scripts/versions.mbtx set X.Y.Z` and adds the `## X.Y.Z` section to
`CHANGELOG.md`, and the workflow dry-runs its checks on it. After the merge the
workflow runs `mise run check`, publishes `pkgs/notebooks` and `pkgs/openrpc`
with the `MOONCAKES_USER_TOKEN` organization secret (an existing version counts
as published), runs `mise run check:openrpc-published -- --checksum <sha>`
against the archive it built, and only then creates the GitHub release `vX.Y.Z`.
Repository access to that secret must be verified before the first run.

`moonrockz/moon-lander` stays unpublished. Before publishing it, run
`mise run check:formats-registry` on the exact candidate, and keep release gate
`lander-4us.9` open until `mise run check:formats-published` passes on all four
targets for that candidate with its source SHA and published archive checksum
recorded in the bead.

## Commits and pull requests

- Use [Conventional Commits](https://www.conventionalcommits.org/), for example
  `feat(config): add the TOML source` or `docs(openspec): propose add-host-lifecycle`.
- Do not add AI attribution lines to commits, pull requests or issues.
- Install the hooks with `mise run hooks:install`. Pre-commit checks formatting,
  compiler warnings and generated interfaces. Pre-push runs lint, workspace validation
  and tests.
- Commit the `pkg.generated.mbti` file of each package, as MoonBit convention
  recommends. `mise run lint` writes these files and fails when one is new or changed
  and not staged. Review the interface change, stage the file, and run lint again.
- CI must pass. The `ci-ok` job is the aggregate check.

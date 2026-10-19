# Moon-Lander

Moon-Lander is an application framework for MoonBit. It has no user interface.

Build an application once and land it on a host. A host can be the web, WebAssembly, or a native process.

[Moonbase](https://github.com/moonrockz/Moonbase) holds the web UI and the Proton desktop shell.

## Development setup

The build setup follows Moonbase and smithy. Install [mise](https://mise.jdx.dev/), then run:

```shell
mise trust
mise install
mise exec -- moon version --all
```

The MoonBit version is pinned in `.config/mise/config.toml`. The mise archive can
omit the core library and `moonx`. If the version check fails or `moonx` is missing,
complete that same installation with the official installer:

```shell
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | \
  MOON_HOME="$(mise where http:moonbit)" bash -s -- "$(mise current http:moonbit)"
```

Then install the hooks and check the workspace:

```shell
mise run hooks:install
mise run check
```

Pre-commit checks formatting and compiler warnings. Pre-push runs lint, workspace
validation, and tests. Local tool overrides belong in
`.config/mise/config.local.toml`, which is gitignored.

## Tasks

Tasks are MoonBit scripts under `scripts/`, run through `moonx` by mise.

| Command | Purpose |
| --- | --- |
| `mise run check` | Lint, validate, test the library and task scripts, and build |
| `mise run build` | Build `wasm`, `wasm-gc`, `js`, and `native` |
| `mise run test` | Test all four targets |
| `mise run build -- js --release` | Build a selected target in release mode |
| `mise run test -- native` | Test a selected target |
| `mise run format` | Format the workspace |
| `mise run lint` | Check YAML, MoonBit formatting, and compiler warnings |
| `mise run validate` | Check workspace membership and shared versions |
| `mise run test:scripts` | Test the build tooling |
| `mise run test:native-zig` | Test native code using external `moonrockz/zig-cross@0.1.2` |
| `mise run clean` | Remove build artifacts |

## Layout and current scope

- `moon.mod` holds the shared version, initially `0.0.1`.
- `moon.work` lists the workspace members.
- `pkgs/lander/` contains the provisional `moonrockz/moon-lander` library, imported
  as `@lander`. Its initial `version()` export provides a build and test smoke check.
- `.config/mise/config.toml` pins the tools and declares tasks.
- `.github/workflows/ci.yml` checks lint, validation, builds, tests, and task scripts.
  The `ci-ok` job is the aggregate check for branch protection.

The application model, host adapters, and CLI remain to be designed. No UI packages
are included. CI has read-only permissions and no publishing or release workflow.
Module and CLI names must be confirmed before publishing. Nothing has been released.

License: Apache-2.0.

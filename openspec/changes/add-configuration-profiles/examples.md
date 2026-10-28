# Configuration profiles

These examples describe configuration profiles. The application opts in to
profiles, registers its formats, and installs the standard argparse options.
Compiled examples are in the config profiles, conventions and hosting guides.

## Files

An `acme` application could use:

```text
acme.toml
acme.Production.toml
acme.profile.common.toml
acme.profile.development.toml
acme.profile.production.toml
acme.profile.postgres.toml
acme.profile.metrics.toml
acme.local.toml
```

`acme.Production.toml` belongs to the existing environment feature. Files with
`.profile.` belong to the new profile feature. Profile names are lowercase and
match exactly. Local overrides retain their current meaning.

## Defaults, includes, and groups

`acme.toml` supplies ordinary defaults and the profile controls:

```toml
[profiles]
default = ["development"]
include = ["common"]

[profiles.groups]
production = ["postgres", "metrics"]

[database]
driver = "memory"
host = "localhost"
pool_size = 5

[telemetry]
enabled = false
```

The group name production is itself active and can have a file. With CLI selection
`--profiles production`, the resolved order is:

```text
common -> production -> postgres -> metrics
```

Each name's file loads in that order. The default development profile is not
active because the explicit selection replaces the fallback. Without a selector,
the order is common then development. There is no implicit `default` profile.

The `[profiles]` controls do not appear in the effective application settings;
the resolved names and their reasons are available through profile metadata.

## Environment and profiles together

```sh
acme --environment Production --profiles production
```

For this run, `acme.Production.toml` could set:

```toml
[database]
host = "database.production.internal"
```

`acme.profile.production.toml` could set:

```toml
[database]
pool_size = 10
```

`acme.profile.postgres.toml` could set:

```toml
[database]
driver = "postgres"
pool_size = 20
```

`acme.profile.metrics.toml` could set:

```toml
[telemetry]
enabled = true
```

Assuming the common profile adds no conflicting values and no later override
exists, the effective application settings are:

```toml
[database]
driver = "postgres"
host = "database.production.internal"
pool_size = 20

[telemetry]
enabled = true
```

A local override setting pool_size to 3 wins over these files. An environment
variable `ACME_DATABASE__POOL_SIZE=40` wins over that local override. An ordinary
mapped CLI configuration override has the existing highest precedence.

## Activation and disable

```sh
# Select independent profiles through the run variable.
ACME_PROFILES=postgres,metrics acme

# CLI selection replaces the variable's list; common still comes from include.
ACME_PROFILES=postgres acme --profiles metrics

# Repeated options concatenate within the CLI selection.
acme --profiles postgres --profiles metrics,tracing

# Disable all profiles, including configured defaults and includes.
acme --no-profiles

# An explicitly empty selector variable also disables profile processing.
ACME_PROFILES= acme
```

An explicit `profiles.active = []` in the base suppresses fallback profiles but
keeps includes. `--no-profiles` suppresses both. An empty comma element, such as
`--profiles postgres,,metrics`, is an error.

## Later roots and workspace order

For include metrics, active roots production then postgres, and the production
group above, expansion gives metrics, production, postgres, metrics, postgres.
Keeping each name's last occurrence gives:

```text
production -> metrics -> postgres
```

The explicit later postgres root has the highest profile precedence. With a
selected workspace member, files are applied for each name in turn:

```text
workspace profile production
member profile production
workspace profile metrics
member profile metrics
workspace profile postgres
member profile postgres
```

Environment files precede that stage; local and user overrides follow it. The
member wins within one profile, while a later profile wins over an earlier one.
The resolution report explains the selector and group/include reasons; source
reports and ordinary key provenance explain which file supplied each setting.

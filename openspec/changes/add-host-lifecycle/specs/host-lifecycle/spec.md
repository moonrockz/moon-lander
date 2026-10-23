# Spec Delta

## Purpose

Gives MoonBit applications a host that builds typed services from layered
configuration, starts and stops hosted services in a known order, handles stop
requests and signals, and gives exit codes that do not change.

## ADDED Requirements

### Requirement: Typed services record

The host SHALL build the application services record `S` one time, after the
configuration is complete and before the first hosted-service hook. The host MUST give
the same `S` instance to each hook, each lifetime event handler and the command. The
host MUST NOT use a dependency-injection container.

#### Scenario: One services instance for the full run

- **WHEN** the services factory counts its calls, and the application has two hosted services and one command
- **THEN** the factory runs one time, and the two services and the command get the same `S` instance

#### Scenario: Services see the final configuration

- **WHEN** an overrides source sets `log.format = "json"` and the services factory reads `log.format`
- **THEN** the factory gets the value `"json"`

### Requirement: Arguments are parsed first

The host SHALL parse the arguments one time with `moonbitlang/core/argparse` before
it reads a configuration file or a variable for configuration. The command MUST get
the parse result through its context. When argparse cannot parse the arguments, the
host MUST write the argparse message to standard error and MUST end with exit code 2.
No configuration file read and no hosted-service hook MUST occur before that exit.

#### Scenario: Unknown option

- **WHEN** the arguments contain `--no-such-option`
- **THEN** standard error contains the argparse message, the exit code is 2, no configuration file is read, and no hook runs

#### Scenario: Command reads its subcommand

- **WHEN** the application registers the subcommand `build`, and the arguments are `build`
- **THEN** the command finds the subcommand `build` in the parse result of its context

### Requirement: Standard flags

The argparse adapter SHALL supply the standard flags `--environment <name>`,
`--config <path>`, `--isolated` and `--project <path|name>`. Under `@lander` they MUST
be on. On the bare `@hosting.builder` the application MUST add each one. Each flag
MUST be global to subcommands. The host MUST NOT copy a standard flag value into a
configuration layer.

#### Scenario: Environment flag after a subcommand

- **WHEN** the application adds the environment option, and the arguments are `build --environment Staging`
- **THEN** argparse accepts the arguments, the environment name is `Some("Staging")`, and the configuration contains no key `environment`

### Requirement: Standard flags fill the discovery options

The host SHALL give the standard flag values to conventions as `DiscoveryOptions`:
`--environment` as `environment`, `--config` as `config` with `Explicit(path)`,
`--isolated` as `isolated`, and `--project` as `project`. A flag that is not given
MUST leave its field at "not given".

#### Scenario: Explicit configuration file

- **WHEN** the application adds the config option, and the arguments contain `--config ../configs/project.yaml`
- **THEN** conventions gets `DiscoveryOptions.config` as `Explicit("../configs/project.yaml")`

#### Scenario: Isolated run

- **WHEN** the application adds the isolated flag, the arguments contain `--isolated`, and a global configuration file and the variable `ACME_LOG__FORMAT=json` exist
- **THEN** the configuration has no layer from the global file, and `log.format` is `"json"`

#### Scenario: Project selector

- **WHEN** the application adds the project option, and the arguments contain `--project core`
- **THEN** conventions gets `DiscoveryOptions.project` as `Some("core")`

### Requirement: Empty standard flag value

An empty value for `--environment`, `--config` or `--project` SHALL give a usage
error with exit code 2 before any file read.

#### Scenario: Empty environment value

- **WHEN** the arguments contain `--environment=`
- **THEN** the run ends with a usage error and exit code 2, and no hook runs

### Requirement: Host environment

The host SHALL give a host environment that holds the application name, an optional
environment name, and the content root. The application name MUST be the name given
to `@lander.cli` or `@hosting.builder`. The content root MUST be the value the builder sets.
Without that value, it MUST be the working directory of the run. The content root MUST
use `/` as the separator on every platform.

#### Scenario: No environment name

- **WHEN** the builder has no default environment, and no `--environment` flag or `<PREFIX>_ENVIRONMENT` variable exists
- **THEN** the environment name is `None`, and each check for a named environment, such as `is_development()`, gives `false`

#### Scenario: Builder default

- **WHEN** the builder pipeline contains `@hosting.default_environment("Production")` and no flag or variable sets a name
- **THEN** the environment name is `Some("Production")`, and environment files are enabled

#### Scenario: Content root on native

- **WHEN** a native application starts in `/work/repo` and the builder sets no content root
- **THEN** the content root is `/work/repo`

#### Scenario: Content root on Windows

- **WHEN** a native application on Windows starts in `C:\work\repo` and the builder sets no content root
- **THEN** the content root is `C:/work/repo`

### Requirement: Environment name resolution order

The host SHALL take the environment name from the first of these that has a value:
the `--environment` argument, the `<PREFIX>_ENVIRONMENT` variable in the variable set
of the run, the builder default. The host MUST check the name with the name rules of
`configuration-conventions`. An invalid name MUST stop the run with exit code 2
before any hosted-service hook.

#### Scenario: Flag wins over variable

- **WHEN** the arguments contain `--environment Staging` and `ACME_ENVIRONMENT=Production` exists
- **THEN** the environment name is `Some("Staging")`

#### Scenario: Starting environment is the default

- **WHEN** the application calls `@lander.cli(AppName::parse("acme"), args, environment="Production")`, and the variable set holds `ACME_ENVIRONMENT=Staging`
- **THEN** the environment name is `Some("Staging")`, and without that variable it is `Some("Production")`

#### Scenario: Invalid name

- **WHEN** the arguments contain `--environment ../x`
- **THEN** the run ends with exit code 2, and no hosted-service hook runs

### Requirement: Environment name before application configuration

The host SHALL find the environment name before it loads the application
configuration sources. The configuration sources MUST get the resolved environment
name as an input.

#### Scenario: Environment files use the resolved name

- **WHEN** environments are on, the arguments contain `--environment Staging`, and `acme.Staging.toml` sits next to `acme.toml`
- **THEN** the configuration contains the layer from `acme.Staging.toml`

### Requirement: Parsed names and exit codes

The host SHALL take the application name as an `AppName`, each service name as a
`ServiceName`, and each exit code as an `ExitCode`. Each type MUST have one smart
constructor, which is the only way to make a value. A parse that fails MUST raise a
`HostError` that names the text and the broken rule.

#### Scenario: Application name with a space

- **WHEN** a program calls `AppName::parse("my tool")`
- **THEN** the call raises `HostError::InvalidAppName` with the text `my tool` and a reason that names the character, and no builder exists

### Requirement: Name and exit code rules

An application name SHALL start with an ASCII letter and SHALL hold only ASCII
letters, digits, `-` and `_`. A service name MUST be safe as one file path component: it
MUST start with a Unicode letter, MUST hold only Unicode letters, combining marks,
digits, `_`, `-` and `.`, MUST NOT end with `.`, MUST NOT be a Windows device name
before any extension, and MUST be at most 128 bytes in UTF-8. An exit
code MUST be in the range 0 to 255.

#### Scenario: Service name with surrounding whitespace

- **WHEN** a program calls `ServiceName::parse(" db")`
- **THEN** the call raises `HostError::InvalidServiceName`

#### Scenario: Windows device name

- **WHEN** a program calls `ServiceName::parse("nul.log")`
- **THEN** the call raises `HostError::InvalidServiceName`

#### Scenario: Exit code out of range

- **WHEN** a program calls `ExitCode::from_int(256)`
- **THEN** the call raises `HostError::InvalidExitCode`

### Requirement: Unique service names

Each service of a host SHALL have its own name, without regard to letter case. A
step that adds a service whose name equals a name of the builder, or differs from
it only in letter case, MUST raise `HostError::DuplicateService`.

#### Scenario: Two services with one name

- **WHEN** a builder has a service named `db`, and the program adds a second service named `db`
- **THEN** the step raises `HostError::DuplicateService`, and the builder keeps one service named `db`

#### Scenario: Names that differ only in letter case

- **WHEN** a builder has a service named `Données`, and the program adds a service named `DONNÉES`
- **THEN** the step raises `HostError::DuplicateService`

### Requirement: Application name and variable prefix

The application name SHALL be given one time, as an `AppName`, in
`@lander.cli(name, args)` or `@hosting.builder(name, args)`. The
variable prefix MUST default to the application name in upper case, with `-` changed
to `_`. `@hosting.env_prefix` MUST change the prefix. The host MUST give the name and
the prefix to the conventions parts.

#### Scenario: Default prefix

- **WHEN** the application name is `my-tool`, and `MY_TOOL_LOG__FORMAT=json` exists
- **THEN** the configuration holds `log.format = "json"`

#### Scenario: Prefix override

- **WHEN** the application name is `my-tool`, the pipeline contains `@hosting.env_prefix("MT")`, and `MT_LOG__FORMAT=json` exists
- **THEN** the configuration holds `log.format = "json"`

### Requirement: Environment-variable source

The host SHALL add the environment-variable source of `configuration-core` with the
variable prefix, at priority 600, after the application sources and before the
overrides source. Its reserved names MUST include `<PREFIX>_ENVIRONMENT` and
`<PREFIX>_HOME`, and each name that the application adds with `@hosting.reserve_env`.
The source MUST read the variable set of the run. The application MUST be able to skip
the source.

#### Scenario: Reserved names are not keys

- **WHEN** the prefix is `ACME`, and `ACME_ENVIRONMENT=Staging` and `ACME_HOME=/tmp/acme` exist
- **THEN** the configuration contains no key `environment` and no key `home`

#### Scenario: Variables beat files

- **WHEN** `acme.toml` sets `log.format = "text"`, and `ACME_LOG__FORMAT=json` exists
- **THEN** the configuration holds `log.format = "json"`, and the source report shows the variable source with priority 600

### Requirement: Host starting settings

`@lander.cli` and `@hosting.builder` SHALL accept the optional labelled arguments
`env_vars`, `working_dir` and `environment`. On native and js, an omitted `env_vars` or `working_dir` MUST come
from the process. On wasm and wasm-gc, an omitted `env_vars` MUST be the empty set and
an omitted `working_dir` MUST be `/`. When both are given, the host MUST NOT read the
process environment or the process working directory.

#### Scenario: Explicit settings on every target

- **WHEN** the application gives `env_vars` with `ACME_LOG__FORMAT=json` and `HOME=/home/test`, and `working_dir` `/w`, and `/w/acme.toml` exists (on wasm and wasm-gc, in the injected complete tree)
- **THEN** wasm, wasm-gc, js and native give equal configuration and reports, and the host reads no process variable and no process working directory

#### Scenario: Omitted settings on native

- **WHEN** a native or js application omits `env_vars` and `working_dir`, starts in `/work/repo`, and the process holds `ACME_LOG__FORMAT=json`
- **THEN** the working directory is `/work/repo`, and the configuration holds `log.format = "json"`

#### Scenario: Omitted settings on wasm

- **WHEN** a wasm-gc application omits `env_vars` and `working_dir`
- **THEN** the variable set is empty, and the working directory is `/`

### Requirement: Later steps replace the starting settings

A `@hosting.env_vars` step SHALL replace the variable set of the run. A
`@hosting.working_dir` step SHALL replace the working directory. The last step before
the build MUST win.

#### Scenario: A later env_vars step replaces the set

- **WHEN** `@lander.cli` gets `env_vars` with `ACME_A=1`, and a later step `@hosting.env_vars` gives `ACME_B=2`
- **THEN** the configuration holds `b = 2`, does not hold `a`, and `ctx.env_vars` holds only `ACME_B`

#### Scenario: A later working_dir step

- **WHEN** `@lander.cli` gets `working_dir` `/a`, and a later step `@hosting.working_dir("/b")` follows
- **THEN** walk-up discovery starts at `/b`, and `ctx.working_dir` is `/b`

### Requirement: One variable set and one working directory per run

The variable set of the run SHALL feed the environment-variable source, the
environment-name bootstrap, the conventions directory resolution and the core
`config/host` adapter. Walk-up discovery MUST start at the working directory of the
run. `BuildContext` and `Context[S]` MUST give both values as `env_vars` and
`working_dir`. The host MUST NOT change them after the run starts.

#### Scenario: Every reader sees one set

- **WHEN** the variable set holds `ACME_ENVIRONMENT=Staging`, `ACME_LOG__FORMAT=json` and `HOME=/home/test`, and the process holds other values for these names
- **THEN** the environment name is `Some("Staging")`, `log.format` is `"json"`, a global candidate is `/home/test/.acme/acme.toml`, and `ctx.env_vars` equals the given set

### Requirement: Variable set from a map or JSON

The `hosting` package SHALL give the trait `IntoEnvVars` with the method
`into_env_vars(Self) -> Map[String, String] raise`, and implementations for
`Map[String, String]` and `Json`. The `env_vars` arguments MUST take `&IntoEnvVars`.

#### Scenario: Map literal

- **WHEN** the application gives `env_vars={ "ACME_LOG__FORMAT": "json" }`
- **THEN** the variable set holds `ACME_LOG__FORMAT=json`

#### Scenario: JSON fixture

- **WHEN** a test parses the fixture `{"ACME_LOG__FORMAT": "json"}` with `@json.parse` and gives the result as `env_vars`
- **THEN** the variable set holds `ACME_LOG__FORMAT=json`

### Requirement: JSON variable rules

The root of a JSON variable set SHALL be an object, else the run MUST end with a
`UsageError` and exit code 2. A string value MUST stay as it is. A Boolean, a number,
an array or an object MUST become its JSON text. `null` MUST mean that the variable is
not set. Nested objects MUST NOT be flattened. Keys MUST stay exactly as written.

#### Scenario: Mixed values

- **WHEN** the application gives `env_vars=({ "ACME_PORT": 8080, "ACME_DEBUG": true, "ACME_TAGS": ["a", "b"] } : Json)`
- **THEN** the variable set holds `ACME_PORT=8080`, `ACME_DEBUG=true` and `ACME_TAGS=["a","b"]`, and the configuration holds `port = 8080`, `debug = true` and `tags` as the list `["a", "b"]`

#### Scenario: Null value

- **WHEN** the JSON variable set holds `"ACME_PORT": null`
- **THEN** the variable set does not hold `ACME_PORT`

#### Scenario: Root that is not an object

- **WHEN** the application gives the JSON array `["ACME_PORT"]` as `env_vars`
- **THEN** the run ends with a usage error and exit code 2, and no configuration file is read

### Requirement: Configuration from an injected file tree on wasm

On wasm and wasm-gc, the host SHALL load the configuration from the `FileTree` that
the application gives with `@hosting.files`. When the tree is not complete and the
load asks for more files, the host MUST end the run with exit code 2 and MUST name the
requested paths on standard error.

#### Scenario: Complete tree

- **WHEN** a wasm-gc application gives a complete tree that holds `acme.toml` with `log.format = "text"`
- **THEN** the configuration holds `log.format = "text"`

#### Scenario: Incomplete tree

- **WHEN** a wasm application gives a tree that is not complete and has no listing of the start directory
- **THEN** the run ends with exit code 2, and standard error names the start directory

### Requirement: Hosted service start order

The host SHALL run the start phase in three steps: each `starting` hook, then each
`start` hook, then each `started` hook. Each step MUST go in registration order. After
the last step, the host MUST raise the started event and then run the command.

#### Scenario: Two services start in order

- **WHEN** services A and B are registered in that order, and each has all three start hooks
- **THEN** the hooks run in the order A.starting, B.starting, A.start, B.start, A.started, B.started, and then the started event and the command run

### Requirement: Hosted service stop order

The host SHALL run the stop phase in this order: the stopping event, each `stopping`
hook, each `stop` hook, each `stopped` hook, the stopped event. Each hook step MUST go
in reverse registration order. Only started services MUST get stop hooks.

#### Scenario: Two services stop in reverse order

- **WHEN** services A and B started in that order, and the command returns
- **THEN** the order is the stopping event, B.stopping, A.stopping, B.stop, A.stop, B.stopped, A.stopped, and the stopped event

### Requirement: Optional lifecycle hooks

Each hook of a hosted service SHALL be optional. The host MUST skip a hook that the
service does not supply and MUST continue with the next hook.

#### Scenario: Service with only a stopping hook

- **WHEN** a service supplies only a `stopping` hook that flushes logs
- **THEN** the host starts the service with no calls, and calls the flush one time during the stop phase

### Requirement: A service counts as started after its start hook

The host SHALL mark a service as started when its `start` hook returns without an
error, or when the service has no `start` hook and its `starting` hook did not fail.

#### Scenario: Failure in a starting hook

- **WHEN** service A has a `starting` hook that fails
- **THEN** A is not started, and A gets no stop hooks

### Requirement: Failed start stops started services

When a start hook fails, the host SHALL run no more start hooks, MUST NOT run the
command, and MUST run the stop phase for the services that started. The stopping and
stopped events MUST occur. The started event MUST NOT occur.

#### Scenario: Second service fails to start

- **WHEN** services A, B and C are registered, and B.start fails
- **THEN** C gets no hooks, the command does not run, A gets its stopping, stop and stopped hooks, and the exit code is 1

#### Scenario: Failure after all services started

- **WHEN** services A and B started, and B.started fails
- **THEN** the command does not run, and B and A both get their stop hooks in that order

### Requirement: Stop hook failures do not skip other hooks

When a stop hook or a stopped hook fails, the host SHALL record the failure and MUST
continue with the remaining stop hooks. The host MUST report each failure on standard
error. When the exit code is otherwise 0, it MUST become 1.

#### Scenario: Stop failure with otherwise clean run

- **WHEN** the command returns, and B.stop fails
- **THEN** A.stop still runs, the failure appears on standard error, and the exit code is 1

### Requirement: Lifetime events

The lifetime SHALL give the events started, stopping and stopped. Each event MUST
occur at most one time per run. A handler that the application registers after its
event occurred MUST run at once.

#### Scenario: Late registration

- **WHEN** the command registers a started handler after the started event occurred
- **THEN** the handler runs at once, one time

### Requirement: Stop request

The lifetime SHALL accept a stop request from the command, a hook, an event handler,
a signal, or an embedder. A stop request MUST be idempotent. The first request MUST
set the stop reason. A stop request during the start phase MUST let the current hook
finish, skip the remaining start hooks and the command, and stop the started services.

#### Scenario: Command asks to stop

- **WHEN** the command calls `stop_application()` and then returns
- **THEN** the stop phase runs one time, and the stop reason is a requested stop

#### Scenario: Stop request during start

- **WHEN** service A calls `stop_application()` in its `start` hook, and service B is registered after A
- **THEN** B gets no hooks, the command does not run, and A gets its stop hooks

### Requirement: Cancellation checks seen by the running command

The host SHALL give the command the checks `cancelled()` and `check_cancelled()`
through its context and through a stop token. After a stop request, `cancelled()` MUST
give `true`, and `check_cancelled()` MUST raise `StopRequested`. Each check MUST be a
plain read that synchronous code can poll.

#### Scenario: Synchronous native code sees a signal

- **WHEN** a native command computes in a loop with no suspension point, calls `ctx.cancelled()` in each pass, and the process gets SIGINT
- **THEN** the next call gives `true`, and after the command returns the stop reason is `Signal(Interrupt)` and the exit code is 130

### Requirement: A raised stop is not a failure

When the command raises `StopRequested`, the host SHALL treat the run as stopped, not
as failed. The stop reason MUST stay the reason of the first stop request.

#### Scenario: Command polls the check

- **WHEN** a command calls `ctx.check_cancelled()` between work items, and the command calls `stop_application()` from an event handler
- **THEN** the next check raises `StopRequested`, the stop phase runs, the stop reason is a requested stop, and the exit code is 0

### Requirement: Command task cancellation on native and js

On native and js, a stop request SHALL also cancel the command task. The command MUST
stop at its next suspension point, and its `defer` blocks MUST run before the stop
phase.

#### Scenario: Command waits on input and output

- **WHEN** a native command waits in an asynchronous sleep, and a stop request occurs
- **THEN** the wait ends with cancellation, the command's `defer` block runs, and the stop phase starts after that

### Requirement: Shutdown sees the command state

The stop phase SHALL get the same `Context[S]` and the same `S` instance that the
command used. Each change that the command made to state in `S` MUST be visible to
the stop hooks and the stopped event. The stop hooks MUST get the stop reason.

#### Scenario: Stop hook reads command state

- **WHEN** the command adds three records to a buffer in `S`, and a `stopping` hook flushes that buffer
- **THEN** the flush writes the three records

### Requirement: Shutdown timeout

The host SHALL limit the stop phase to a shutdown timeout. The default MUST be 30
seconds. The builder MUST let the application set another value. When the time ends,
the host MUST cancel the current hook, skip the remaining stop hooks, raise the
stopped event, and report the timeout on standard error.

#### Scenario: Slow stop hook

- **WHEN** the shutdown timeout is 100 ms, and B.stop waits for 10 seconds
- **THEN** the host cancels B.stop after about 100 ms, A.stop does not run, the stopped event occurs, and the exit code is 1

#### Scenario: Timeout after a signal

- **WHEN** a SIGTERM starts the stop phase, and the shutdown timeout ends
- **THEN** the exit code is 143

### Requirement: Console signals give a graceful stop

On native and js, the console driver SHALL change each handled signal into a stop
request with a signal stop reason. On Linux and macOS, the handled signals MUST be
SIGINT, SIGTERM and SIGQUIT. On Windows native, the handled events MUST be
`CTRL_C_EVENT`, `CTRL_BREAK_EVENT` and `CTRL_CLOSE_EVENT`. On Windows js, the handled
events MUST be the Node.js events SIGINT, SIGBREAK and SIGHUP. The full stop phase
MUST run before the process ends.

#### Scenario: Ctrl-C during a command

- **WHEN** a native command runs on Linux and the process gets SIGINT
- **THEN** the command is cancelled, every started service gets its stop hooks, and the exit code is 130

#### Scenario: SIGQUIT on native

- **WHEN** a native command runs on macOS and the process gets SIGQUIT
- **THEN** every started service gets its stop hooks, no core dump occurs, and the exit code is 131

#### Scenario: SIGTERM on js

- **WHEN** a js command runs under Node.js and the process gets SIGTERM
- **THEN** every started service gets its stop hooks, and the process exit code is 143

#### Scenario: Ctrl-Break on Windows

- **WHEN** a native command runs on Windows and the console sends `CTRL_BREAK_EVENT`
- **THEN** every started service gets its stop hooks, and the exit code is 131

### Requirement: Signal identity

The stop reason of a signal stop SHALL name the signal that arrived. SIGINT and
`CTRL_C_EVENT` MUST give `Interrupt`. SIGTERM and `CTRL_CLOSE_EVENT` MUST give
`Terminate`. SIGQUIT and `CTRL_BREAK_EVENT` MUST give `Quit`. On Windows js, SIGINT
MUST give `Interrupt`, SIGHUP MUST give `Terminate`, and SIGBREAK MUST give `Quit`.

#### Scenario: Stop hook reads the signal

- **WHEN** a native command runs on Linux, the process gets SIGTERM, and a `stopping` hook reads the stop reason
- **THEN** the hook gets `Signal(Terminate)`

### Requirement: Second signal stops at once

After the console driver starts a graceful stop because of a signal, a second
handled signal SHALL end the process at once. The remaining hooks and events MUST NOT
run. The exit code MUST be the code of the second signal. On native, the end MUST
occur also while the command runs synchronous code that does not yield.

#### Scenario: Two Ctrl-C presses

- **WHEN** the first SIGINT starts the stop phase, and a stop hook is slow, and a second SIGINT arrives
- **THEN** the process ends at once, the remaining stop hooks do not run, and the exit code is 130

#### Scenario: Second signal during synchronous native code

- **WHEN** a native command computes in a loop with no suspension point and no check, the process gets SIGINT, and then a second SIGINT
- **THEN** the process ends at once with exit code 130

### Requirement: Exit codes

The host SHALL give one exit code per run. The code MUST be 0 for a clean run. It
MUST be 1 for an unhandled failure, 2 for a configuration error or a usage error,
130 for a SIGINT or `CTRL_C_EVENT` stop, 143 for a SIGTERM or `CTRL_CLOSE_EVENT` stop,
and 131 for a SIGQUIT or `CTRL_BREAK_EVENT` stop. After a graceful signal stop, the
host MUST end the process explicitly with that code on every platform. An application
MUST be able to set its own code.

#### Scenario: Clean run

- **WHEN** all hooks and the command return without an error
- **THEN** the exit code is 0

#### Scenario: Configuration error

- **WHEN** the configuration build or a binding raises a configuration error
- **THEN** the exit code is 2, and no hosted-service hook runs when the error occurs before the start phase

#### Scenario: Unhandled command failure

- **WHEN** the command raises an error that is not a configuration or usage error
- **THEN** the stop phase runs, and the exit code is 1

#### Scenario: Application code

- **WHEN** the command sets the exit code 3 and returns
- **THEN** the exit code is 3

#### Scenario: Ctrl-C on Windows

- **WHEN** a native command runs on Windows and the console sends `CTRL_C_EVENT`
- **THEN** the stop phase runs, and the process exit code is 130

### Requirement: Exit code precedence

When more than one exit code applies, the host SHALL select the first of these that
applies: a signal stop code, a configuration or usage error (2), an unhandled
failure (1), a stop phase failure or timeout (1), the code the application set, 0.

#### Scenario: Signal wins over application code

- **WHEN** the command sets the exit code 3, and a SIGINT then stops the run
- **THEN** the exit code is 130

#### Scenario: Application code wins over clean stop

- **WHEN** the command calls `stop_application(exit_code=4)` and all stop hooks succeed
- **THEN** the exit code is 4

### Requirement: Unhandled failure report

When the run ends with code 1 or 2 because of an error, the console driver SHALL
write the error message to standard error. The application MUST be able to replace
the default report with its own report function.

#### Scenario: Default report

- **WHEN** the command raises an error with the message `build.invalid_timeout`
- **THEN** standard error contains `build.invalid_timeout`, and the exit code is 1

### Requirement: Stop on wasm and wasm-gc

On wasm and wasm-gc, the host SHALL NOT handle signals. The lifetime MUST stop
through a stop request from the application, or through a stop probe that the
embedder supplies. The cancellation checks MUST report the probe result.

#### Scenario: Embedder probe

- **WHEN** a wasm-gc command calls `ctx.cancelled()` in a loop, and the embedder probe starts to report a stop
- **THEN** the next call gives `true`, and the stop phase runs after the command returns

#### Scenario: Command stops the host

- **WHEN** a wasm command calls `stop_application()` and returns
- **THEN** the stop phase runs, and the run ends with exit code 0

### Requirement: Parsed arguments become the top configuration layer

The argparse adapter SHALL turn the parsed argparse results into the overrides
source of `configuration-core`, with priority 700. The overrides source MUST be the
last source in merge order. Only options that the application maps to a key path
MUST go into the layer. Values that come from argparse defaults MUST NOT go into the
layer.

#### Scenario: Mapped option overrides a file and a variable

- **WHEN** `acme.toml` sets `log.format = "text"`, `ACME_LOG__FORMAT=yaml` exists, the option `--log-format` maps to `log.format`, and the arguments contain `--log-format json`
- **THEN** the configuration holds `log.format = "json"`, its origin has the kind `overrides`, and the source report shows the overrides source with priority 700

#### Scenario: Argparse default does not hide a file value

- **WHEN** the option `--log-format` has the argparse default `text`, `acme.toml` sets `log.format = "json"`, and the arguments do not contain `--log-format`
- **THEN** the configuration holds `log.format = "json"`

#### Scenario: Unmapped option

- **WHEN** the arguments contain `--dry-run`, and the application maps no key path for it
- **THEN** the configuration contains no key from `--dry-run`

### Requirement: Argument value types

The argparse adapter SHALL give a flag as a boolean, a count flag as an integer, an
option with one value as a string, and an option with the append action as a list of
strings. A mapping MUST be able to give a parse function that changes the text into
another value type.

#### Scenario: Count flag

- **WHEN** the count flag `-v` maps to `log.verbosity`, and the arguments contain `-vvv`
- **THEN** the configuration holds the integer 3 at `log.verbosity`

### Requirement: Batteries-included entry

`@lander.cli` SHALL start a builder with these defaults on: the formats of the
`formats` virtual package, the `app_dirs` convention set with the host name and
prefix, the standard flags, and environment-file discovery. `@hosting.builder` SHALL
start a bare builder with none of them on. Both MUST compose the environment-variable
source and MUST use a 30-second shutdown timeout.

#### Scenario: Smallest program

- **WHEN** a native program is `@lander.cli(AppName::parse("acme"), @env.args()) |> @lander.run(fn(ctx) { ... })`, it starts in `/w`, `/w/acme.toml` sets `log.format = "text"`, and the arguments are `--environment Staging`
- **THEN** the run accepts the flag, the environment name is `Some("Staging")`, the configuration holds `log.format = "text"`, and the exit code is 0

#### Scenario: Bare builder

- **WHEN** a program starts with `@hosting.builder(AppName::parse("acme"), ["--environment", "Staging"])` and has no `command` step
- **THEN** the run ends with a usage error and exit code 2, and no configuration file is read

### Requirement: Change or turn off a default

Each `@lander` default SHALL have one step that changes it or turns it off.
`@lander.formats(names)` MUST keep only the named formats of the linked set.
`@lander.conventions(f)` MUST use the set that `f` gives for the default set.
`@lander.no_standard_flags()` MUST remove the standard flags.
`@lander.no_environments()` MUST turn environment-file discovery off.

#### Scenario: Narrow the formats

- **WHEN** the pipeline contains `@lander.formats(["toml"])`, and `/w` holds only `acme.yaml`
- **THEN** discovery searches only `.toml` candidates, the project source reports `not-found`, and the configuration holds no value from `acme.yaml`

#### Scenario: Unknown format name

- **WHEN** the pipeline contains `@lander.formats(["xml"])`, and the linked set has no format named `xml`
- **THEN** the run ends before any file read with exit code 1, and standard error names `xml` and the linked format names

#### Scenario: No standard flags

- **WHEN** the pipeline contains `@lander.no_standard_flags()`, and the arguments are `--environment Staging`
- **THEN** the run ends with a usage error and exit code 2

#### Scenario: No environments

- **WHEN** the pipeline contains `@lander.no_environments()`, the variable set holds `ACME_ENVIRONMENT=Staging`, and `acme.Staging.toml` sits next to `acme.toml`
- **THEN** no environment-file source exists, and the environment name is `Some("Staging")`

#### Scenario: Replace the convention set

- **WHEN** the pipeline contains `@lander.conventions(fn(_) { @conventions.base("acme") })`, and `/etc/acme/acme.toml` exists
- **THEN** no source loads `/etc/acme/acme.toml`

### Requirement: Environment files under the batteries entry

Under `@lander`, environment-file discovery SHALL be on with no default name.
Environment files MUST load only when the run has an environment name. The bare
`@hosting.builder` and the Morphir preset MUST keep environment files off until the
application enables them.

#### Scenario: No name gives no environment file

- **WHEN** an application uses `@lander.cli` with no `--environment` flag, no `ACME_ENVIRONMENT` variable and no default, and `acme.Staging.toml` sits next to `acme.toml`
- **THEN** no environment-file source loads, and the environment name is `None`

#### Scenario: Variable selects the environment file

- **WHEN** an application uses `@lander.cli`, the variable set holds `ACME_ENVIRONMENT=Staging`, and `acme.Staging.toml` sits next to `acme.toml`
- **THEN** the configuration contains the layer from `acme.Staging.toml`

### Requirement: Services default to Unit

Under `@lander`, when the application does not call `@lander.build`, the services
record SHALL be `Unit`. `@lander.build(factory)` MUST set the services record type
`S` and MUST keep every earlier setting and hosted service.

#### Scenario: No build step

- **WHEN** an application uses `@lander.cli` and `@lander.run` with no `@lander.build` step
- **THEN** the program compiles, and the command gets `ctx.services` as `()`

#### Scenario: Build after other steps

- **WHEN** the pipeline contains `@lander.shutdown_timeout(5_000)` and then `@lander.build(factory)`
- **THEN** the factory runs one time, the command gets the `S` that it gives, and the shutdown timeout is 5000 ms

### Requirement: Driver selection by target

`@lander.run(command)` SHALL build the host and run it with the console driver on
native and js, and with the embedded driver on wasm and wasm-gc. One program source
MUST build on all four targets. `@hosting.run` MUST stay available for tests and
MUST NOT end the process.

#### Scenario: Console driver on native

- **WHEN** a native program uses `@lander.run`, and the process gets SIGINT during the command
- **THEN** every started service gets its stop hooks, and the exit code is 130

#### Scenario: Embedded driver on wasm-gc

- **WHEN** the same program source builds for wasm-gc, and its command calls `stop_application()` and returns
- **THEN** the build passes, the stop phase runs, and the run ends with exit code 0

### Requirement: Program trait and run_app

The host SHALL give a `Program` trait with one method,
`async run(Self, Context[Self]) -> Unit raise`. `run_app(factory)` SHALL build the
services record with the factory and run its `Program` implementation with the same
driver selection as `run`. The lambda form `run(command)` MUST stay available.

#### Scenario: Services record runs as the program

- **WHEN** an application defines `App` with an implementation of `Program` and calls `@lander.run_app(App::new)`
- **THEN** the host builds `App` with the factory, calls its `run` with a context whose services are that `App`, and runs the stop phase after it

#### Scenario: Same result as the lambda form

- **WHEN** one program uses `run_app(App::new)` and another uses `build(App::new)` and `run(fn(ctx) { ctx.services.run(ctx) })` with the same inputs
- **THEN** both give the same hook order, output and exit code

### Requirement: No configuration file is required

An application under `@lander` SHALL run when no configuration file exists. Each
discovered location MUST report `not-found`. Each option MUST take its default from
the defaults source or from `bind_or`. An empty configuration file MUST be valid and
MUST add no value. The show helper MUST give the effective values.

#### Scenario: No file present

- **WHEN** the defaults source sets `log.format = "text"`, and no configuration file exists at any discovered location
- **THEN** the exit code is 0, each file source reports `not-found`, the show helper output holds `log.format = "text"`, and the explain helper gives it the origin kind `defaults`

#### Scenario: Empty file

- **WHEN** `acme.toml` exists and is empty, and the defaults source sets `log.format = "text"`
- **THEN** the project source reports `loaded`, and the configuration holds `log.format = "text"` with the origin kind `defaults`

### Requirement: A partial file changes only its keys

A configuration file at any position in the source list SHALL set only the keys
that it holds. Every other key MUST keep the value of a lower source or its default.

#### Scenario: One-key partial file

- **WHEN** the defaults source sets `log.format = "text"` and `log.level = "info"`, and `acme.toml` holds only `log.level = "debug"`
- **THEN** the configuration holds `log.level = "debug"` from `acme.toml` and `log.format = "text"` with the origin kind `defaults`

#### Scenario: Partial user override

- **WHEN** `acme.toml` sets `log.format = "text"` and `log.level = "info"`, and `acme.user.toml` holds only `log.level = "debug"`
- **THEN** the configuration holds `log.level = "debug"` and `log.format = "text"`

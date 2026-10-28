# Host arguments

Import this package as `@hosting_argparse`. Add a command factory to the host
pipeline. The factory gets the application name, so it occurs once in the
application. The run parses before configuration, the services factory and hooks.

Build the command with the argparse types that this package re-exports, such as
`@hosting_argparse.Command`, `OptionArg`, `FlagArg` and `PositionArg`. Until a
pinned MoonBit release has `Command::try_parse` (moonbitlang/core#4487), the host
uses a vendored copy of core argparse, so a `moonbitlang/core/argparse` command
does not fit the `command` step. After the return to core, the same names are
the core types, and the application does not change. A re-exported enum such as
`FlagAction` has `to_string()`, but `println` of the value does not compile
through the re-export.

```mbt check
test "build a command with global standard flags" {
  let host : @hosting.Host[Unit] =
  @hosting.builder(@lander_core.AppName::parse("acme"), ["build", "--environment", "Staging"])
  |> @hosting_argparse.command(name => @hosting_argparse.Command(name,
    options=[@hosting_argparse.environment_option(), @hosting_argparse.config_option(), @hosting_argparse.project_option()],
    flags=[@hosting_argparse.isolated_flag()],
    subcommands=[@hosting_argparse.Command("build")]))
  |> @hosting.build(_ => ())
  ignore(host)
}
```

The standard flags are opt-in on the bare builder. Add them to the root
command. They are global, so they can follow a subcommand. A standard flag added
only to a subcommand is not read by the host. The factory reads the parsed flags
in `BuildContext.args`. Hooks and the command read the same parse result in
`Context.args`. Standard flag values do not become configuration keys. The run
keeps the discovery inputs separate from configuration values.

An argparse error or an empty standard option value gives `UsageError` and code 2.
A command-definition fault, such as a duplicate id, also gives `UsageError` and
code 2 because core argparse does not distinguish it from a user error without
matching message text.
With no command step, an empty command named after the application rejects every
extra argument.

A help or version request, such as `--help`, `-h`, `help <subcommand>`,
`--version`, or no arguments with `arg_required_else_help`, is not an error. The
run writes the argparse text one time to standard output and ends with code 0
and the stop reason `Requested`, before configuration, the services factory and
hooks. The run never ends the process: `run_embedded` returns to the embedder,
and the console driver ends the process with code 0. A version requires the
command's `version` argument.

Add explicit mappings to put application arguments in configuration. Parse an
`OverrideOption` and a `KeyPath` at the application boundary. An empty id or a
standard discovery id raises `MappingError::InvalidOverrideOption` with the input
and the rule. No standard discovery flag can become a configuration value.

This is the bare pipeline from design D2, with a small services record in place
of Morphir telemetry. The build does no I/O. The run parses once, loads files and
variables, appends overrides, builds services, and then runs the hooks and command.
Use `@hosting.run(host, command)` on native or js, and
`@hosting.run_embedded(host, command)` on wasm or wasm-gc.

```mbt check
test "D2 pipeline with typed argument mappings" {
  let flushes = Ref(0)
  let host : @hosting.Host[Ref[Int]] =
  "morphir"
  |> @lander_core.AppName::parse
  |> @hosting.builder(["build", "--log-format", "json", "-vvv"],
    env_vars=({} : Map[String, String]), working_dir=@lander_core.AbsolutePath::root())
  |> @hosting_argparse.command(name => @hosting_argparse.Command(name,
    options=[@hosting_argparse.environment_option(), @hosting_argparse.config_option(),
      @hosting_argparse.project_option(), @hosting_argparse.OptionArg("log-format", global=true)],
    flags=[@hosting_argparse.isolated_flag(), @hosting_argparse.FlagArg("verbose", short='v', action=Count, global=true)],
    subcommands=[@hosting_argparse.Command("build"), @hosting_argparse.Command("workspace")]),
    mappings=[
      @hosting_argparse.map(@hosting_argparse.OverrideOption::parse("log-format"), @config.KeyPath::parse("log.format")),
      @hosting_argparse.map(@hosting_argparse.OverrideOption::parse("verbose"), @config.KeyPath::parse("log.verbosity"), action=Count),
    ])
  |> @hosting.configure(s => s |> @config.format(@toml.format())
    |> @config.defaults({ "log": { "format": "text", "verbosity": 0 } }))
  |> @hosting.app_dirs()
  |> @hosting.reserve_env(["MORPHIR_LOG_DIR"])
  |> @hosting.service("telemetry", stopping=ctx => ctx.services.val += 1)
  |> @hosting.shutdown_timeout(@lander_core.TimeLimit::seconds(5))
  |> @hosting.build(b => {
    assert_eq(@config.get_text(b.config, "log.format"), "json")
    assert_eq((@config.bind(b.config, "log.verbosity") : Int), 3)
    flushes
  })
  let command : @hosting.Hook[Ref[Int]] = ctx => {
    // The application dispatches the subcommand from this same parse result.
    assert_true(ctx.args.subcommand is Some(("build", _)))
  }
  ignore(host)
  ignore(command)
}
```

Set options give strings, and Set is the default mapping action. Use
`action=Flag` for boolean flags, `action=Count` for integer counts, and
`action=Append` for lists. Match the argument declaration. Argparse `Matches`
omits the declaration's action and zero count entries, so the typed
`MappingAction` keeps this information. A count of zero stays an integer, and
one Append value stays a list. A custom `parse` function converts each text, or each Append
item. For flags it receives `true` or `false`; for counts it receives integer text.

```mbt check
test "Append keeps one value as a list" {
  let matches = @hosting_argparse.Command("acme",
    options=[@hosting_argparse.OptionArg("include", action=Append)])
    .parse(argv=["--include", "src"], env={})
  let source = @hosting_argparse.to_overrides(matches, [
    @hosting_argparse.map(@hosting_argparse.OverrideOption::parse("include"),
      @config.KeyPath::parse("build.include"), action=Append,
      parse=text => @config.string(text)),
  ])
  let config = @config.build([source])
  assert_eq((@config.bind(config, "build.include") : Array[String]), ["src"])
}
```

Only mapped `Argv` and `Env` values enter the source. `Default` values stay out,
so an argparse default cannot hide a file value. Global arguments and the selected
subcommand path participate. A deeper explicit value with the same id wins; a
default at a child does not hide an explicit ancestor. Global values convert once.
Later mappings to the same key win through the normal configuration merge rules.
The `command` step copies the mappings and replaces mappings from an earlier step.

The host appends the real `Overrides` source at priority 700 after its environment
source at 600. An empty mapped result still has a source report; a command with no
mappings adds none. Custom parser errors become `UsageError` and code 2 before any
configuration callback, file read, services factory, hook or command runs.

## Profile selectors

Add `profiles_option()` and `no_profiles_flag()` together on the root command.
They are global through nested subcommands. The option appends repeated values;
the host splits each value at commas, trims ASCII whitespace around names and
parses names once. Empty elements and names outside the lowercase ASCII grammar
give usage code 2. The disabling flag conflicts with every profile option.

```mbt check
test "declare repeatable profile selectors" {
  let command = @hosting_argparse.Command("acme",
    options=[@hosting_argparse.profiles_option()],
    flags=[@hosting_argparse.no_profiles_flag()],
    subcommands=[@hosting_argparse.Command("build")])
  let matches = command.parse(argv=["--profiles", "postgres", "build", "--profiles", "metrics,tracing"], env={})
  assert_eq(matches.values.get("profiles"), Some(["postgres", "metrics,tracing"]))
}
```

The ids `profiles` and `no-profiles` are reserved by `OverrideOption::parse`.
Selectors do not enable a profile policy or file discovery. Enable the policy
with `@hosting.profiles` after `@hosting.app_dirs`. With profiles off, a valid
selector gives a note and preserves ordinary application values named profiles.

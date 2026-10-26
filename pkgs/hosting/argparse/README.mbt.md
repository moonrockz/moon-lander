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

The four standard flags are opt-in on the bare builder. Add them to the root
command. They are global, so they can follow a subcommand. A standard flag added
only to a subcommand is not read by the host. The factory reads the parsed flags
in `BuildContext.args`. Hooks and the command read the same parse result in
`Context.args`. Standard flag values do not become configuration keys. The run
keeps the discovery inputs in its private parsed-arguments state for group 9.

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

Task group 14 adds option mappings. Configuration loading through discovery and
project selection follows in task group 9.

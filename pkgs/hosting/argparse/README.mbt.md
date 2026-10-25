# Host arguments

Import this package as `@hosting_argparse`. Add a command factory to the host
pipeline. The factory gets the application name, so it occurs once in the
application. The run parses before configuration, the services factory and hooks.

```mbt check
test "build a command with global standard flags" {
  let host : @hosting.Host[Unit] =
  @hosting.builder(@lander_core.AppName::parse("acme"), ["build", "--environment", "Staging"])
  |> @hosting_argparse.command(name => @core_argparse.Command(name,
    options=[@hosting_argparse.environment_option(), @hosting_argparse.config_option(), @hosting_argparse.project_option()],
    flags=[@hosting_argparse.isolated_flag()],
    subcommands=[@core_argparse.Command("build")]))
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
extra argument. On native and js, argparse handles `--help` and `--version` itself
and ends the process with code 0 before configuration or hooks. Group 13 decides
the embedded behavior. A version requires the command's `version` argument.

Task group 14 adds option mappings. Configuration loading through discovery and
project selection follows in task group 9.

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

The four standard flags are opt-in on the bare builder. They are global, so they
can follow a subcommand. The factory reads the parsed flags in `BuildContext.args`
and the discovery inputs in `BuildContext.discovery_options`. Hooks and the
command read the same parse result in `Context.args`. Standard flag values do not
become configuration keys.

An argparse error or an empty standard option value gives `UsageError` and code 2.
With no command step, an empty command named after the application rejects every
extra argument. Argparse handles `--help` and `--version` itself and exits with
code 0 before configuration or hooks. A version requires the command's `version`
argument.

Task group 14 adds option mappings. Configuration loading through discovery and
project selection follows in task group 9.

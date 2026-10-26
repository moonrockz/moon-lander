///|
/// Set the command factory used before configuration or hooks. Group 14 adds
/// mappings from parsed options to configuration keys.
pub using @hosting {command}

///|
/// The argparse types of a host command. Build the command with these names, not
/// with `moonbitlang/core/argparse`: until a pinned MoonBit release has
/// `Command::try_parse` (moonbitlang/core#4487), the host uses a vendored copy of
/// core argparse, and core types do not fit the `command` step. After the return
/// to core, these names are the core types, so the application does not change.
pub using @core_argparse {
  type ArgGroup,
  type Command,
  type FlagAction,
  type FlagArg,
  type Matches,
  type OptionAction,
  type OptionArg,
  type PositionArg,
  type ValueRange,
  type ValueSource,
}

///|
/// The global `--environment <name>` option. The host passes it to discovery.
/// Add it to the root command. The host does not read it from a subcommand only.
pub fn environment_option() -> @core_argparse.OptionArg {
  @core_argparse.OptionArg("environment", long="environment", global=true,
    about="The environment name, for example Staging.")
}

///|
/// The global `--config <path>` option for the explicit primary file.
/// Add it to the root command. The host does not read it from a subcommand only.
pub fn config_option() -> @core_argparse.OptionArg {
  @core_argparse.OptionArg("config", long="config", global=true,
    about="The primary configuration file.")
}

///|
/// The global `--isolated` flag that skips optional discovery layers.
/// Add it to the root command. The host does not read it from a subcommand only.
pub fn isolated_flag() -> @core_argparse.FlagArg {
  @core_argparse.FlagArg("isolated", long="isolated", global=true,
    about="Skip the optional configuration layers.")
}

///|
/// The global `--project <path|name>` option for workspace member selection.
/// Add it to the root command. The host does not read it from a subcommand only.
pub fn project_option() -> @core_argparse.OptionArg {
  @core_argparse.OptionArg("project", long="project", global=true,
    about="The workspace member, by path or name.")
}

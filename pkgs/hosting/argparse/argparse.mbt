///|
/// Set the command factory used before configuration or hooks. Group 14 adds
/// mappings from parsed options to configuration keys.
pub using @hosting {command}

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

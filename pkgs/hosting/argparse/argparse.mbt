///|
/// Set the command factory used before configuration or hooks. Group 14 adds
/// mappings from parsed options to configuration keys.
pub using @hosting {command}

///|
/// The global `--environment <name>` option. The host passes it to discovery.
pub fn environment_option() -> @core_argparse.OptionArg {
  @core_argparse.OptionArg("environment", long="environment", global=true)
}

///|
/// The global `--config <path>` option for the explicit primary file.
pub fn config_option() -> @core_argparse.OptionArg {
  @core_argparse.OptionArg("config", long="config", global=true)
}

///|
/// The global `--isolated` flag that skips optional discovery layers.
pub fn isolated_flag() -> @core_argparse.FlagArg {
  @core_argparse.FlagArg("isolated", long="isolated", global=true)
}

///|
/// The global `--project <path|name>` option for workspace member selection.
pub fn project_option() -> @core_argparse.OptionArg {
  @core_argparse.OptionArg("project", long="project", global=true)
}

///|
/// Set the command factory and explicit mappings used before configuration or
/// hooks. The host appends the mapped source after its environment source.
pub using @hosting {command, map, to_overrides, type Mapping, type MappingAction, type OverrideOption, type MappingError}

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

///|
/// The global repeatable `--profiles <a,b>` option. Add it to the root
/// command together with `no_profiles_flag`. It selects profiles only when
/// the application enables a profile policy.
pub fn profiles_option() -> @core_argparse.OptionArg {
  @core_argparse.OptionArg("profiles", long="profiles", global=true,
    action=Append, conflicts_with=["no-profiles"],
    about="Select ordered configuration profiles, separated by commas.")
}

///|
/// The global `--no-profiles` flag. It suppresses profile includes, defaults,
/// groups and files, and conflicts with every `--profiles` occurrence.
pub fn no_profiles_flag() -> @core_argparse.FlagArg {
  @core_argparse.FlagArg("no-profiles", long="no-profiles", global=true,
    conflicts_with=["profiles"], about="Disable configuration profiles.")
}

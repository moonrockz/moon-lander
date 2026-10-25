///|
/// An environment name that follows the conventions rules. It is not empty,
/// holds no `/`, `\`, `.` or control character, and is not `user` or `local`
/// in any letter case. The text and its letter case stay as given.
pub struct EnvironmentName {
  priv text : String
} derive(Eq, Debug)

///|
pub extend EnvironmentName with Eq::{equal, not_equal}

///|
pub extend EnvironmentName with @debug.Debug::{to_repr}

///|
/// Parse an environment name. A broken rule raises `InvalidEnvironmentName`
/// with the input and the reason.
pub fn EnvironmentName::parse(text : String) -> EnvironmentName raise @config.ConfigError {
  check_environment_name(text, source="EnvironmentName::parse")
  { text, }
}

///|
/// The name as text, which `EnvironmentName::parse` reads back to an equal name.
pub impl Show for EnvironmentName with output(self, logger) {
  logger.write_string(self.text)
}

///|
pub extend EnvironmentName with Show::{output, to_string}

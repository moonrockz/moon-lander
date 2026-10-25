///|
/// The parsed inputs of a run, before configuration or services exist.
priv struct ParsedArguments {
  matches : @argparse.Matches
  discovery_options : @conventions.DiscoveryOptions
}

///|
/// Parse once before the driver loads configuration or calls the factory.
/// The driver supplies the resolved variable snapshot, shared by all readers.
// The wasm drivers that call this arrive in group 13.
#warnings("-1")
fn[S] parse_arguments(host : Host[S], env~ : Map[String, String]) -> ParsedArguments raise UsageError {
  let command = match host.make_command {
    Some(make) => make(host.name.to_string())
    None => @argparse.Command(host.name.to_string())
  }
  let matches = command.parse(argv=host.args[:], env~) catch {
    error => raise UsageError(error.to_string())
  }
  let environment = standard_option(matches, "environment")
  let config = match standard_option(matches, "config") {
    Some(path) => @config.SourceSelection::Explicit(path)
    None => @config.SourceSelection::Discover
  }
  let project = standard_option(matches, "project")
  let isolated = matches.flags.get("isolated").unwrap_or(false)
  { matches, discovery_options: @conventions.DiscoveryOptions::new(environment?, config~, isolated~, project?) }
}

///|
/// Empty standard values fail at the argument boundary. Environment names
/// stay raw until group 8. Config and project selectors keep conventions text.
fn standard_option(matches : @argparse.Matches, id : String) -> String? raise UsageError {
  guard matches.values.get(id) is Some([.., value]) else { return None }
  if value.is_empty() { raise UsageError("--\{id} requires a non-empty value") }
  Some(value)
}

///|
/// Set the command factory. The run gives it the application name and parses
/// its command once, before configuration and hooks. Group 14 adds mappings.
pub fn[S] command(builder : HostBuilder[S], make : (String) -> @argparse.Command) -> HostBuilder[S] {
  { ..builder, make_command: Some(make) }
}

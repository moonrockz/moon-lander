///|
/// The parsed inputs of a run, before configuration or services exist.
priv struct ParsedArguments {
  matches : @argparse.Matches
  discovery_options : @conventions.DiscoveryOptions
  overrides : @config.ConfigSource?
}

///|
/// A help or version request of the argument parse, with the text that argparse
/// renders. It is not a failure: the driver writes the text one time to standard
/// output, and the run ends with code 0 and the reason `Requested`, before the
/// configuration load (design D6). It is an error, as `StopRequested` is from the
/// factory, so that it ends the run at the parse in each driver.
priv suberror DisplayRequested {
  DisplayRequested(String)
}

///|
/// Parse once before the driver loads configuration or calls the factory.
/// The driver supplies the resolved variable snapshot, shared by all readers.
/// A parse error raises `UsageError`. A help or version request raises
/// `DisplayRequested`. The parse never ends the process.
fn[S] parse_arguments(host : Host[S], env~ : @sorted_map.SortedMap[String, String]) -> ParsedArguments raise {
  let command = match host.make_command {
    Some(make) => make(host.name.to_string())
    None => @argparse.Command(host.name.to_string())
  }
  let parsed = command.try_parse(argv=host.args[:], env=Map::from_iter(env.iter())) catch {
    error => raise UsageError(error.to_string())
  }
  let matches = match parsed {
    Parsed(matches) => matches
    Help(text) | Version(text) => raise DisplayRequested(text)
  }
  let environment = standard_option(matches, "environment")
  let config = match standard_option(matches, "config") {
    Some(path) => @config.SourceSelection::Explicit(path)
    None => @config.SourceSelection::Discover
  }
  let project = standard_option(matches, "project")
  let isolated = matches.flags.get("isolated").unwrap_or(false)
  let overrides = if host.mappings.is_empty() { None } else { Some(to_overrides(matches, host.mappings)) }
  { matches, discovery_options: @conventions.DiscoveryOptions::new(environment?, config~, isolated~, project?), overrides }
}

///|
/// Empty standard values fail at the argument boundary. The host resolves and
/// parses the environment name next. Config and project selectors keep
/// conventions text.
fn standard_option(matches : @argparse.Matches, id : String) -> String? raise UsageError {
  guard matches.values.get(id) is Some([.., value]) else { return None }
  if value.is_empty() { raise UsageError("--\{id} requires a non-empty value") }
  Some(value)
}

///|
/// Set the command factory. The run gives it the application name and parses
/// its command once, before configuration and hooks.
pub fn[S] command(builder : HostBuilder[S], make : (String) -> @argparse.Command, mappings? : Array[Mapping] = []) -> HostBuilder[S] {
  { ..builder, make_command: Some(make), mappings: mappings.copy() }
}

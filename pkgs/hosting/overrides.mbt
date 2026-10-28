///|
/// An argument id that can supply a configuration override. The standard
/// discovery ids cannot be mapped.
pub struct OverrideOption {
  priv id : String
} derive(Eq, Debug)

///|
pub extend OverrideOption with Eq::{equal, not_equal}

///|
pub extend OverrideOption with @debug.Debug::{to_repr}

///|
/// A mapping id is empty or is reserved for host discovery.
pub suberror MappingError {
  InvalidOverrideOption(input~ : String, reason~ : String)
} derive(Debug)

///|
pub extend MappingError with @debug.Debug::{to_repr}

///|
/// Parse a non-empty argparse id. Reject `environment`, `config`, `isolated`
/// `project`, `profiles` and `no-profiles`, which supply host discovery inputs
/// rather than config values.
pub fn OverrideOption::parse(text : String) -> OverrideOption raise MappingError {
  if text.is_empty() {
    raise InvalidOverrideOption(input=text, reason="the argument id must not be empty")
  }
  match text {
    "environment" | "config" | "isolated" | "project" | "profiles" | "no-profiles" =>
      raise InvalidOverrideOption(input=text, reason="the argument id is reserved for host discovery")
    _ => { id: text }
  }
}

///|
/// The argparse id of the mapping.
pub fn OverrideOption::to_string(self : OverrideOption) -> String {
  self.id
}

///|
/// The value shape of a mapped argument. Match the argparse declaration.
/// Matches omits option actions and count entries whose value is zero.
pub(all) enum MappingAction {
  Flag
  Count
  Set
  Append
}

///|
/// One explicit argument-to-key mapping with its declared value shape.
pub struct Mapping {
  priv option : OverrideOption
  priv key : @config.KeyPath
  priv action : MappingAction
  priv parse : ((String) -> @config.ConfigValue raise)?
}

///|
/// Map a parsed argument id to a parsed configuration key. `action` must match
/// the argument declaration: Flag, Count, Set or Append. The default is Set.
/// Append keeps a list with one value; Count keeps an integer even at zero.
/// With `parse`, convert each text value, or the boolean/count text for a flag.
pub fn map(
  option : OverrideOption,
  key : @config.KeyPath,
  action? : MappingAction = Set,
  parse? : (String) -> @config.ConfigValue raise,
) -> Mapping {
  { option, key, action, parse }
}

///|
/// Convert only explicit Argv and Env values into the priority-700 source.
/// Search the selected subcommand path from the root; a deeper explicit value
/// for the same id wins. A Default value never hides an explicit ancestor.
/// The application still dispatches subcommands. Conversion failures give
/// UsageError before the host loads configuration or creates services.
pub fn to_overrides(matches : @argparse.Matches, mappings : Array[Mapping]) -> @config.ConfigSource raise UsageError {
  let mut tree = @config.fields([])
  for mapping in mappings {
    let mut selected = None
    let mut current = Some(matches)
    while current is Some(node) {
      match node.sources.get(mapping.option.id) {
        Some(Argv) | Some(Env) => selected = Some(node)
        _ => ()
      }
      current = node.subcommand.map(child => child.1)
    }
    if selected is Some(node) {
      let value = mapped_value(node, mapping) catch {
        error => {
          let message = match error {
            UsageError::_ as e => e.message()
            @config.ConfigError::_ as e => e.message()
            e => e.to_string()
          }
          let input = match mapping.action {
            Count => node.flag_counts.get(mapping.option.id).unwrap_or(0).to_string()
            Flag => node.flags.get(mapping.option.id).unwrap_or(false).to_string()
            Set | Append => @debug.to_string(node.values.get(mapping.option.id).unwrap_or([]))
          }
          raise UsageError("Cannot map argument \"\{mapping.option.id}\" with value \{input} to \"\{mapping.key}\": \{message}")
        }
      }
      if value is Some(value) {
        let names = mapping.key.names()
        let mut branch = value
        for i = names.length() - 1; i >= 0; i = i - 1 {
          branch = @config.fields([(names[i], branch)])
        }
        tree = @config.merge(tree, branch) catch {
          error => raise UsageError(error.message())
        }
      }
    }
  }
  @config.ConfigSource::overrides_value(tree, priority=700) catch {
    error => raise UsageError(error.message())
  }
}

///|
fn mapped_value(matches : @argparse.Matches, mapping : Mapping) -> @config.ConfigValue? raise {
  let id = mapping.option.id
  match mapping.action {
    Count => {
      // Argparse omits a zero count from flag_counts, but keeps its flag and
      // source. The explicit-source gate has already excluded Default.
      guard matches.flags.contains(id) else { raise UsageError("Count mapping requires a count flag") }
      let count = matches.flag_counts.get(id).unwrap_or(0)
      Some(match mapping.parse {
        Some(parse) => parse(count.to_string())
        None => @config.int(count.to_int64())
      })
    }
    Flag => {
      guard matches.flags.get(id) is Some(flag) else { raise UsageError("Flag mapping requires a boolean flag") }
      Some(match mapping.parse {
        Some(parse) => parse(flag.to_string())
        None => @config.bool(flag)
      })
    }
    Set | Append => {
      guard matches.values.get(id) is Some(values) else { raise UsageError("Set or Append mapping requires a value argument") }
      let parse = mapping.parse.unwrap_or(text => @config.string(text))
      match mapping.action {
        Append => Some(@config.list(values.map(value => parse(value))))
        _ => match values { [.., last] => Some(parse(last)); _ => None }
      }
    }
  }
}

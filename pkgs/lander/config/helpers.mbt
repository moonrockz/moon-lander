///|
/// The text form of a show helper.
pub(all) enum ShowFormat {
  Toml
  Json
  Ion
} derive(Eq, Debug)

///|
pub extend ShowFormat with Eq::{equal, not_equal}

///|
pub extend ShowFormat with @debug.Debug::{to_repr}

///|
/// The value at the key path `key` as text, after redaction: a string gives its
/// text, and any other value gives compact JSON. A missing key raises
/// `KeyNotFound`.
pub fn get_text(config : Config, key : String) -> String raise ConfigError {
  let path = KeyPath::parse(key)
  let value = redacted_at(config, path)
  match value.ion.kind() {
    String(text) => text
    _ => {
      let json = @ion_json.to_json(value.ion) catch {
        err => raise Render(format="JSON", key=path, reason=err.message())
      }
      json.stringify()
    }
  }
}

///|
/// The value at the key path `key` as a JSON object with the fields `key` and
/// `value`, after redaction. A missing key raises `KeyNotFound`.
pub fn get_json(config : Config, key : String) -> Json raise ConfigError {
  let path = KeyPath::parse(key)
  let value = redacted_at(config, path)
  let rendered = @ion_json.to_json(value.ion) catch {
    err => raise Render(format="JSON", key=path, reason=err.message())
  }
  { "key": Json::string(path.to_string()), "value": rendered }
}

///|
/// Render the redacted configuration as TOML, JSON, or Ion text.
pub fn show(config : Config, format : ShowFormat) -> String raise ConfigError {
  let redacted = redact(config.root)
  match format {
    Json => show_json_value(redacted, { names: ["(root)"] }).stringify()
    Ion =>
      @ion_text.write_ion(redacted.ion) catch {
        err =>
          raise Render(
            format="Ion",
            key={ names: ["(root)"] },
            reason=err.message(),
          )
      }
    Toml => to_toml_value(redacted, []).to_string()
  }
}

///|
/// Source reports as text: highest priority first.
pub fn path_text(reports : Array[SourceReport]) -> String {
  let lines = ["Configuration sources (in priority order):"]
  for report in reports.rev() {
    let mark = if report.status is Loaded { "[✓]" } else { "[✗]" }
    lines.push("")
    lines.push("\{mark} \{report.kind.report_name()} (\{report.name})")
    if report.path is Some(path) {
      lines.push("  Path: \{path}")
    }
    lines.push("  Status: \{status_text(report.status)}")
    lines.push("  Priority: \{report.priority}")
    for warning in report.warnings {
      lines.push("  Warning: \{warning_text(warning)}")
    }
  }
  lines.join("\n")
}

///|
/// Source reports as JSON, in ascending priority (merge order).
pub fn path_json(reports : Array[SourceReport]) -> Json {
  Json::array(
    reports.map(report => {
      let object : Map[String, Json] = {
        "kind": Json::string(report.kind.report_name()),
        "name": Json::string(report.name),
        "priority": Json::number(report.priority.to_double()),
        "status": Json::string(status_text(report.status)),
        "candidates": Json::array(
          report.candidates.map(path => Json::string(path)),
        ),
      }
      match report.path {
        Some(path) => object["path"] = Json::string(path)
        None => object["path"] = Json::null()
      }
      if !report.warnings.is_empty() {
        object["warnings"] = Json::array(
          report.warnings.map(warning => Json::string(warning_text(warning))),
        )
      }
      Json::object(object)
    }),
  )
}

///|
/// The origins of `key`: one entry for a leaf, or each descendant leaf for a
/// struct. A missing key raises `KeyNotFound`.
pub fn explain(
  config : Config,
  key : String,
) -> Array[(KeyPath, Array[Origin])] raise ConfigError {
  let path = KeyPath::parse(key)
  guard config.get(path) is Some(value) else { raise KeyNotFound(key=path) }
  if value.ion.kind() is Struct(_) &&
    !is_secret_reference(value, config.secret_syntax) {
    return leaves(value, secret_syntax=config.secret_syntax).map(leaf => {
      let full = { names: [..path.names, ..leaf.0.names] }
      (full, config.origins(full))
    })
  }
  [(path, config.origins(path))]
}

///|
fn redacted_at(config : Config, path : KeyPath) -> ConfigValue raise ConfigError {
  let redacted = redact(config.root)
  guard redacted.at(path.names) is Some(value) else {
    raise KeyNotFound(key=path)
  }
  value
}

///|
fn status_text(status : SourceStatus) -> String {
  match status {
    Loaded => "loaded"
    NotFound => "not-found"
    Skipped => "skipped"
  }
}

///|
fn warning_text(warning : ConfigWarning) -> String {
  match warning {
    KeyRemoved(key, origin) =>
      "removed key \{key} from \{origin_text(origin)}"
    Note(source~, message~) => "\{source}: \{message}"
  }
}

///|
fn show_json_value(value : ConfigValue, path : KeyPath) -> Json raise ConfigError {
  match value.ion.kind() {
    Null(_) => Json::null()
    Bool(flag) => Json::boolean(flag)
    Int(number) => Json::string(number.to_string())
    Float(number) => {
      if number.is_nan() || number.is_inf() {
        raise Render(
          format="JSON",
          key=path,
          reason="JSON cannot hold NaN or infinity",
        )
      }
      Json::number(number)
    }
    Decimal(number) => Json::string(number.to_ion_string())
    Timestamp(stamp) => Json::string(stamp.to_ion_string())
    Symbol(token) => Json::string(token.text().unwrap_or(""))
    String(text) => Json::string(text)
    Blob(bytes) | Clob(bytes) =>
      Json::string(@base64.encode(bytes[:]))
    List(items) | Sexp(items) =>
      Json::array(items.map(item => show_json_value({ ion: item }, path)))
    Struct(fields) => {
      let object : Map[String, Json] = Map([])
      for field in fields {
        let name = field.name().text().unwrap_or("")
        object[name] = show_json_value(
          { ion: field.value() },
          { names: [..path.names, name] },
        )
      }
      Json::object(object)
    }
  }
}

///|
/// Render an Ion timestamp as a TOML date-time value, not a quoted string.
fn timestamp_to_toml(
  stamp : @ion.Timestamp,
  key : KeyPath,
) -> @toml_lib.TomlValue raise ConfigError {
  let text = stamp.to_ion_string()
  let document = @toml_lib.parse("v = \{text}") catch {
    err =>
      raise Render(
        format="TOML",
        key~,
        reason="cannot write timestamp as TOML date-time: \{err}",
      )
  }
  match document {
    TomlTable(entries) =>
      match entries.get("v") {
        Some(TomlDateTime(_) as value) => value
        Some(_) =>
          raise Render(
            format="TOML",
            key~,
            reason="timestamp did not parse as a TOML date-time",
          )
        None =>
          raise Render(
            format="TOML",
            key~,
            reason="timestamp did not parse as a TOML date-time",
          )
      }
    _ =>
      raise Render(
        format="TOML",
        key~,
        reason="timestamp did not parse as a TOML date-time",
      )
  }
}

///|
fn to_toml_value(
  value : ConfigValue,
  path : Array[String],
) -> @toml_lib.TomlValue raise ConfigError {
  let key : KeyPath = if path.is_empty() {
    { names: ["(root)"] }
  } else {
    { names: path.copy() }
  }
  match value.ion.kind() {
    Null(_) => raise Render(format="TOML", key~, reason="TOML cannot hold null")
    Bool(flag) => @toml_lib.TomlBoolean(flag)
    Int(number) => @toml_lib.TomlInteger(number.to_int64())
    Float(number) => @toml_lib.TomlFloat(number)
    Decimal(number) => @toml_lib.TomlString(number.to_ion_string())
    Timestamp(stamp) => timestamp_to_toml(stamp, key)
    Symbol(token) => @toml_lib.TomlString(token.text().unwrap_or(""))
    String(text) => @toml_lib.TomlString(text)
    Blob(bytes) | Clob(bytes) => @toml_lib.TomlString(@base64.encode(bytes[:]))
    List(items) | Sexp(items) => {
      let out = []
      for item in items {
        if item.is_null() {
          raise Render(
            format="TOML",
            key~,
            reason="TOML cannot hold null in a list",
          )
        }
        out.push(to_toml_value({ ion: item }, path))
      }
      @toml_lib.TomlArray(out)
    }
    Struct(fields) => {
      let table : Map[String, @toml_lib.TomlValue] = Map([])
      for field in fields {
        let name = field.name().text().unwrap_or("")
        table[name] = to_toml_value({ ion: field.value() }, [..path, name])
      }
      @toml_lib.TomlTable(table)
    }
  }
}

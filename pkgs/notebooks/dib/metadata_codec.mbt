///|
priv enum MetadataFormat {
  Json
  Yaml
  Toml
  Ion
}

///|
/// DIB output keeps JSON when it preserves the metadata, otherwise uses Ion.
/// Explicit Json requests reject metadata that cannot round-trip through JSON.
pub(all) enum MetadataOutput {
  Auto
  Json
  Ion
} derive(Eq, Debug)

///|
pub extend MetadataOutput with Eq::{equal, not_equal}

///|
pub extend MetadataOutput with @debug.Debug::{to_repr}

///|
fn metadata_format(line : String) -> MetadataFormat? {
  match line {
    "#!meta" | "#!meta json" => Some(Json)
    "#!meta yaml" => Some(Yaml)
    "#!meta toml" => Some(Toml)
    "#!meta ion" => Some(Ion)
    _ => None
  }
}

///|
fn yaml_metadata_ion(value : @yaml.Yaml, line : Int32) -> @ion.Ion raise FormatError {
  match value {
    Map(fields) => @ion.Ion::from_fields(fields.to_array().map(entry => {
      @ion.field(entry.0, yaml_metadata_ion(entry.1, line))
    }))
    Array(items) => @ion.Ion::list(items.map(value => yaml_metadata_ion(value, line)))
    String(text) => @ion.Ion::string(text)
    Integer(value) => @ion.Ion::big_int(@bigint.BigInt::from_int64(value))
    Real(value, ..) => @ion.Ion::float(value)
    Boolean(value) => @ion.Ion::bool(value)
    Null => @ion.Ion::untyped_null()
    BadValue => raise InvalidMetadata(line~, message="invalid YAML value")
  }
}

///|
fn toml_metadata_ion(value : @toml.TomlValue) -> @ion.Ion raise @ion.IonError {
  match value {
    TomlTable(fields) => @ion.Ion::from_fields(fields.to_array().map(entry => {
      @ion.field(entry.0, toml_metadata_ion(entry.1))
    }))
    TomlArray(items) => @ion.Ion::list(items.map(toml_metadata_ion))
    TomlString(text) => @ion.Ion::string(text)
    TomlInteger(value) => @ion.Ion::big_int(@bigint.BigInt::from_int64(value))
    TomlFloat(value) => @ion.Ion::float(value)
    TomlBoolean(value) => @ion.Ion::bool(value)
    TomlDateTime(_) => {
      let (kind, spelling) = value.datetime_info().unwrap()
      if kind == "LocalTime" {
        // Ion has no date-free time. Preserve TOML's type explicitly.
        @ion.Ion::string(spelling).with_annotation(@ion.symbol("toml_local_time"))
      } else {
        let text = spelling.replace_all(old=" ", new="T")
          .replace_all(old="t", new="T").replace_all(old="z", new="Z")
        let text = if kind == "LocalDateTime" { text + "-00:00" } else { text }
        @ion.Ion::timestamp(@ion.Timestamp::parse(text[:]))
      }
    }
  }
}

///|
fn parse_metadata(source : String, format : MetadataFormat, line : Int32) -> Metadata raise FormatError {
  let value = match format {
    Json => @ion_json.read_json(source[:]) catch {
      error => raise InvalidMetadata(line~, message=error.message())
    }
    Ion => @ion_text.read_ion(source[:]) catch {
      error => raise InvalidMetadata(line~, message=error.message())
    }
    Yaml => {
      let documents = @yaml.Yaml::load_from_string(source[:]) catch {
        @yaml.YamlError(mark~, info~) => raise InvalidMetadata(
          line~, message="YAML line \{mark.line}, column \{mark.col + 1}: \{info}",
        )
      }
      match documents[:] {
        [] => @ion.Ion::from_fields([])
        [document] => yaml_metadata_ion(document, line)
        _ => raise InvalidMetadata(line~, message="expected one YAML mapping document")
      }
    }
    Toml => {
      let document = @toml.parse(source) catch {
        error => raise InvalidMetadata(line~, message=error.to_string())
      }
      toml_metadata_ion(document) catch {
        error => raise InvalidMetadata(line~, message=error.message())
      }
    }
  }
  Metadata::from_ion(value) catch {
    error => raise InvalidMetadata(line~, message=error.message())
  }
}

///|
fn registry_metadata_field(metadata : Metadata, key : String) -> Json? raise FormatError {
  metadata.get_json(key) catch {
    error => raise InvalidMetadata(line=1, message=error.message())
  }
}

///|
fn write_metadata(metadata : Metadata, output : MetadataOutput) -> String raise FormatError {
  if output != Ion {
    let json = try {
      let text = metadata.to_json().stringify()
      let reread = @ion_json.read_json(text[:])
      if metadata.to_ion().equals(reread) { Some(text) } else { None }
    } catch {
      _ => None
    }
    if json is Some(text) {
      return "#!meta\n\n" + text + "\n"
    }
    if output == Json {
      raise InvalidMetadata(line=1, message="metadata cannot round-trip through JSON; use Ion output")
    }
  }
  let text = @ion_text.write_ion(metadata.to_ion()) catch {
    error => raise InvalidMetadata(line=1, message=error.message())
  }
  "#!meta ion\n\n" + text + "\n"
}

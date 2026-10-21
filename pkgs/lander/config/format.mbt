///|
/// A configuration file format. `parse` takes the text and the origin, for
/// example a file path, and gives a value tree with a struct root.
pub(all) struct Format {
  name : String
  extensions : Array[String]
  parse : (String, String) -> ConfigValue raise ConfigError
}

///|
/// Parse the text of the file `path` with the format that its extension
/// selects from `formats`. The extension compares in lowercase. No match
/// raises `UnsupportedFormat` with the registered extensions.
pub fn parse_file(
  formats : Array[Format],
  path : String,
  text : String,
) -> ConfigValue raise ConfigError {
  parse_with(select_format(formats, path), path, text)
}

///|
/// The first format in `formats` that reads the extension of `path`.
fn select_format(
  formats : Array[Format],
  path : String,
) -> Format raise ConfigError {
  let (_, name) = split_path(path)
  if name.rev_find(".") is Some(index) && index > 0 {
    let extension = name[index + 1:].to_owned().to_lower()
    for format in formats {
      if format.extensions.iter().any(item => item.to_lower() == extension) {
        return format
      }
    }
  }
  raise UnsupportedFormat(
    path~,
    extensions=formats.map(format => format.extensions).flatten(),
  )
}

///|
/// A lexical rule for portable payload-owned relative names. This restriction
/// applies only to embedded asset names, never to argv, cwd or user paths.
pub(all) enum PayloadPathRule {
  Empty
  Absolute
  EmptySegment
  DotSegment
  ParentSegment
  Backslash
  ControlCharacter
  NonAscii
  ReservedCharacter
  TrailingDotOrSpace
  ReservedName
} derive(Eq, Debug)

///|
pub extend PayloadPathRule with Eq::{equal, not_equal}

///|
pub extend PayloadPathRule with @debug.Debug::{to_repr}

///|
/// An invalid original asset name and the rule that it breaks.
pub suberror PayloadPathError {
  InvalidPayloadPath(input~ : String, rule~ : PayloadPathRule)
} derive(Debug)

///|
pub extend PayloadPathError with @debug.Debug::{to_repr}

///|
/// A nonempty relative slash-separated ASCII asset name, portable to Windows
/// and POSIX filesystems, with no traversal, reserved syntax or ambiguous names.
pub struct RelativeFilePath {
  priv text : String
  priv identity : String
} derive(Debug)

///|
pub extend RelativeFilePath with @debug.Debug::{to_repr}

///|
/// Parse an unambiguous portable asset name before filesystem access.
pub fn RelativeFilePath::parse(input : String) -> RelativeFilePath raise PayloadPathError {
  guard !input.is_empty() else { raise InvalidPayloadPath(input~, rule=Empty) }
  guard !input.has_prefix("/") else { raise InvalidPayloadPath(input~, rule=Absolute) }
  for code_unit in input.to_array() {
    let code = code_unit.to_int()
    if code == 92 { raise InvalidPayloadPath(input~, rule=Backslash) }
    if code < 32 || code == 127 { raise InvalidPayloadPath(input~, rule=ControlCharacter) }
    if code > 127 { raise InvalidPayloadPath(input~, rule=NonAscii) }
    // A tilde could name a filesystem-generated Windows 8.3 alias of another
    // entry. Exclude it so lexical identities remain sufficient before I/O.
    if code_unit is ('<' | '>' | ':' | '"' | '|' | '?' | '*' | '~') {
      raise InvalidPayloadPath(input~, rule=ReservedCharacter)
    }
  }
  for segment in input.split("/") {
    if segment.is_empty() { raise InvalidPayloadPath(input~, rule=EmptySegment) }
    if segment == "." { raise InvalidPayloadPath(input~, rule=DotSegment) }
    if segment == ".." { raise InvalidPayloadPath(input~, rule=ParentSegment) }
    if segment.has_suffix(".") || segment.has_suffix(" ") {
      raise InvalidPayloadPath(input~, rule=TrailingDotOrSpace)
    }
    // Windows reserves these base names even when followed by an extension.
    let base = segment.split(".").next().unwrap().trim_end(chars=" ").to_owned().to_lower()
    if ["con", "prn", "aux", "nul", "conin$", "conout$", "clock$"].contains(base) ||
      (base.length() == 4 && (base.has_prefix("com") || base.has_prefix("lpt")) &&
        base.code_unit_at(3) >= 49 && base.code_unit_at(3) <= 57) {
      raise InvalidPayloadPath(input~, rule=ReservedName)
    }
  }
  { text: input, identity: input.to_lower() }
}

///|
/// The retained spelling of this relative asset name.
pub fn RelativeFilePath::to_string(self : RelativeFilePath) -> String { self.text }

///|
/// An immutable asset entry. Bytes are immutable MoonBit values.
pub struct PayloadFile {
  priv path : RelativeFilePath
  priv bytes : Bytes
}

///|
/// Pair a parsed asset name with immutable bytes.
pub fn PayloadFile::new(path : RelativeFilePath, bytes : Bytes) -> PayloadFile {
  { path, bytes }
}

///|
/// The asset's parsed relative name.
pub fn PayloadFile::path(self : PayloadFile) -> RelativeFilePath { self.path }

///|
/// The exact immutable asset bytes.
pub fn PayloadFile::bytes(self : PayloadFile) -> Bytes { self.bytes }

///|
/// A layout collision or missing entry, retaining the parsed names involved.
pub suberror PayloadError {
  DuplicatePayloadPath(first~ : RelativeFilePath, second~ : RelativeFilePath)
  PayloadFileDirectoryConflict(file~ : RelativeFilePath, descendant~ : RelativeFilePath)
  PayloadDirectoryCaseConflict(first~ : RelativeFilePath, second~ : RelativeFilePath)
  PayloadEntryMissing(entry~ : RelativeFilePath)
} derive(Debug)

///|
pub extend PayloadError with @debug.Debug::{to_repr}

///|
/// A complete collision-free immutable layout with an entry that names an
/// actual file. File order is retained; path identity is ASCII case insensitive.
pub struct Payload {
  priv files : Array[PayloadFile]
  priv entry : RelativeFilePath
}

///|
/// Parse collection rules once and take ownership of a separate file array.
pub fn Payload::new(
  files : Array[PayloadFile],
  entry : RelativeFilePath,
) -> Payload raise PayloadError {
  let paths : Map[String, RelativeFilePath] = Map([])
  for file in files {
    let path = file.path
    if paths.get(path.identity) is Some(first) {
      raise DuplicatePayloadPath(first~, second=path)
    }
    paths.set(path.identity, path)
  }
  let directories : Map[String, (String, RelativeFilePath)] = Map([])
  for file in files {
    let segments = file.path.identity.split("/").to_array()
    let exact_segments = file.path.text.split("/").to_array()
    for end in 1..<segments.length() {
      let prefix = segments[:end].join("/")
      if paths.get(prefix) is Some(parent) {
        raise PayloadFileDirectoryConflict(file=parent, descendant=file.path)
      }
      let exact = exact_segments[:end].join("/")
      if directories.get(prefix) is Some((previous, first)) && previous != exact {
        raise PayloadDirectoryCaseConflict(first~, second=file.path)
      }
      directories.set(prefix, (exact, file.path))
    }
  }
  // Entry spelling must identify a real retained filename, not only a case alias.
  guard files.any(file => file.path.text == entry.text) else { raise PayloadEntryMissing(entry~) }
  { files: files.copy(), entry }
}

///|
/// A fresh array whose immutable entries retain the original order.
pub fn Payload::files(self : Payload) -> Array[PayloadFile] { self.files.copy() }

///|
/// The exact retained entry filename.
pub fn Payload::entry(self : Payload) -> RelativeFilePath { self.entry }

///|
/// A Node executable, owned payload and opaque application arguments.
pub struct NodeLaunch {
  priv node : Executable
  priv payload : Payload
  priv args : Arguments
}

///|
/// Construct a Node launch from a valid complete payload and parsed arguments.
pub fn NodeLaunch::new(
  payload : Payload,
  args : Arguments,
  node~ : Executable = Executable::node(),
) -> NodeLaunch {
  { node, payload, args }
}

///|
/// The selected Node executable, defaulting to PATH lookup.
pub fn NodeLaunch::executable(self : NodeLaunch) -> Executable { self.node }

///|
/// The immutable complete file layout.
pub fn NodeLaunch::payload(self : NodeLaunch) -> Payload { self.payload }

///|
/// The opaque application arguments after the private absolute entry path.
pub fn NodeLaunch::arguments(self : NodeLaunch) -> Arguments { self.args }

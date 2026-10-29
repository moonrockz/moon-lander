///|
/// The fixed CLI rules reported by ArgumentError.
pub enum ArgumentRule {
  PathSyntax
  PortDigits
  PortRange
  TreeSyntax
  BaseSyntax
  CommandExpected
  OptionValue
  UnknownOption
} derive(Debug)

///|
pub extend ArgumentRule with @debug.Debug::{to_repr}

///|
fn ArgumentRule::message(self : ArgumentRule) -> String {
  match self {
    PathSyntax => "path must be nonempty and contain no NUL"
    PortDigits => "port must contain decimal digits"
    PortRange => "port must be between 1 and 65535"
    TreeSyntax => "tree must be empty, next/ or v/<major>.<minor>/"
    BaseSyntax => "base must be a normalized absolute URL path ending in /"
    CommandExpected => "expected build, check or serve"
    OptionValue => "option needs a value"
    UnknownOption => "unknown option"
  }
}

///|
/// A raw argument and the rule it broke.
pub suberror ArgumentError {
  InvalidArgument(String, ArgumentRule)
} derive(Debug)

///|
pub extend ArgumentError with @debug.Debug::{to_repr}

///|
/// Text for CLI diagnostics.
pub fn ArgumentError::message(self : ArgumentError) -> String {
  match self { InvalidArgument(input, rule) => "Invalid argument `\{input}`: \{rule.message()}" }
}

///|
/// A nonempty local path passed to the native host, which checks filesystem containment.
pub struct LocalPath { value : String }

///|
/// Parse a local path before native I/O.
pub fn LocalPath::parse(text : String) -> LocalPath raise ArgumentError {
  guard text != "" && !text.contains("\u{0}") else {
    raise InvalidArgument(text, PathSyntax)
  }
  { value: text }
}

///|
/// The path text for a host call.
pub fn LocalPath::text(self : LocalPath) -> String { self.value }

///|
/// A port the loopback server can bind.
pub struct Port { value : Int }

///|
/// Parse decimal text in the inclusive range 1 through 65535.
pub fn Port::parse(text : String) -> Port raise ArgumentError {
  guard text != "" && text.iter().all(c => c >= '0' && c <= '9') else {
    raise InvalidArgument(text, PortDigits)
  }
  let value = @string.parse_int(text) catch {
    _ => raise InvalidArgument(text, PortRange)
  }
  guard value >= 1 && value <= 65535 else {
    raise InvalidArgument(text, PortRange)
  }
  { value, }
}

///|
/// The validated port for a host call.
pub fn Port::number(self : Port) -> Int { self.value }

///|
/// The suffix of a root, main or released-minor site tree.
pub struct TreePrefix { value : String }

///|
/// Parse the allowed root, main or released-minor tree syntax.
pub fn TreePrefix::parse(text : String) -> TreePrefix raise ArgumentError {
  if text == "" || text == "next/" { return { value: text } }
  let parts = text.split("/").collect()
  if parts is ["v", line, ""] {
    let version = line.split(".").collect()
    if version is [major, minor] &&
      major != "" && minor != "" &&
      (major + minor).iter().all(c => c >= '0' && c <= '9') {
      return { value: text }
    }
  }
  raise InvalidArgument(text, TreeSyntax)
}

///|
/// The normalized suffix used for this tree.
pub fn TreePrefix::text(self : TreePrefix) -> String { self.value }

///|
/// Validated deployment base passed by the tree-aware task.
pub struct BasePath { value : String }

///|
/// Parse an absolute deployment URL prefix with a trailing slash.
pub fn BasePath::parse(text : String) -> BasePath raise ArgumentError {
  guard text.has_prefix("/") && text.has_suffix("/") &&
    !text.contains("//") && !text.contains("\\") && !text.contains("\u{0}") &&
    !text.contains("?") && !text.contains("#") && !text.contains("%") &&
    !text.split("/").any(p => p == "." || p == "..") else {
    raise InvalidArgument(text, BaseSyntax)
  }
  { value: text }
}

///|
/// The validated deployment prefix.
pub fn BasePath::text(self : BasePath) -> String { self.value }

///|
/// Commands describe native work after all raw CLI arguments have been parsed.
pub(all) enum Command {
  Build(LocalPath, LocalPath, TreePrefix, Bool)
  Check(LocalPath, LocalPath, BasePath?)
  Serve(LocalPath, LocalPath, Port)
}

///|
/// Parse one CLI boundary into a command with valid values.
pub fn Command::parse(args : Array[String]) -> Command raise ArgumentError {
  guard args is [command, .. rest] &&
    ["build", "check", "serve"].contains(command) else {
    raise InvalidArgument(args.join(" "), CommandExpected)
  }
  let mut root = "."
  let mut out = "_site"
  let mut tree = ""
  let mut base : String? = None
  let mut port = "4173"
  let mut main_build = false
  let mut i = 0
  while i < rest.length() {
    let key = rest[i]
    if key == "--main" && command == "build" {
      main_build = true
      i += 1
      continue
    }
    guard i + 1 < rest.length() else {
      raise InvalidArgument(key, OptionValue)
    }
    let value = rest[i + 1]
    match key {
      "--root" => root = value
      "--out" | "--dir" => out = value
      "--tree-path" if command == "build" => tree = value
      "--base" if command == "check" => base = Some(value)
      "--port" if command == "serve" => port = value
      _ => raise InvalidArgument(key, UnknownOption)
    }
    i += 2
  }
  let root = LocalPath::parse(root)
  let out = LocalPath::parse(out)
  match command {
    "build" => Build(root, out, TreePrefix::parse(tree), main_build)
    "check" => Check(root, out, base.map(BasePath::parse))
    _ => Serve(root, out, Port::parse(port))
  }
}

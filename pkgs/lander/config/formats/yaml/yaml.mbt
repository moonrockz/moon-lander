///|
/// How the YAML format treats anchors, aliases, tags, and null.
pub(all) enum Profile {
  /// Expand aliases, allow null, keep core-schema tags, reject merge keys and
  /// more than one document.
  Default
  /// Reject anchors, aliases, non-core tags, null, merge keys, and more than
  /// one document.
  Strict
} derive(Eq)

///|
pub extend Profile with Eq::{equal, not_equal}

///|
/// The YAML format for `.yaml` and `.yml` files.
pub fn format(profile~ : Profile = Default) -> @config.Format {
  {
    name: "YAML",
    extensions: ["yaml", "yml"],
    parse: (text, origin) => parse(text, origin~, profile~),
  }
}

///|
/// Parse YAML text into a value tree. The root must be a mapping. An empty
/// document gives an empty struct. `origin` names the source in errors.
pub fn parse(
  text : String,
  origin~ : String,
  profile~ : Profile = Default,
) -> @config.ConfigValue raise @config.ConfigError {
  let builder : Builder = {
    origin,
    profile,
    docs: [],
    stack: [],
    key_stack: [],
    anchors: Map([]),
    documents: 0,
    error: None,
  }
  try {
    @yaml_lib.Parser(text[:]).load(builder, true)
  } catch {
    @yaml_lib.YamlError(mark~, info~) =>
      raise parse_error(origin, info, Some(mark.line), Some(mark.col))
  }
  if builder.error is Some(error) {
    raise error
  }
  let ion = match builder.docs[:] {
    [] => @ion.Ion::from_fields([])
    [document] => document
    _ => abort("YAML builder kept more than one document")
  }
  @config.ConfigValue::from_ion(ion, origin~)
}

///|
priv enum Frame {
  Sequence(Array[@ion.Ion], Int)
  Mapping(Array[(String, @ion.Ion)], Int)
  /// A finished root node waiting for `DocumentEnd`.
  Root(@ion.Ion)
}

///|
priv struct Builder {
  origin : String
  profile : Profile
  docs : Array[@ion.Ion]
  stack : Array[Frame]
  key_stack : Array[String]
  anchors : Map[Int, @ion.Ion]
  mut documents : Int
  mut error : @config.ConfigError?
}

///|
impl @yaml_lib.MarkedEventReceiver for Builder with fn on_event(
  self,
  event,
  mark,
) {
  if self.error is Some(_) {
    return
  }
  self.on_event_impl(event, mark) catch {
    error => self.error = Some(error)
  }
}

///|
fn Builder::on_event_impl(
  self : Builder,
  event : @yaml_lib.Event,
  mark : @yaml_lib.Marker,
) -> Unit raise @config.ConfigError {
  match event {
    StreamStart | StreamEnd => ()
    DocumentStart => {
      self.documents += 1
      if self.documents > 1 {
        raise parse_error(
          self.origin,
          "expected exactly one YAML document",
          Some(mark.line),
          Some(mark.col),
        )
      }
    }
    DocumentEnd =>
      match self.stack.length() {
        0 => self.docs.push(@ion.Ion::from_fields([]))
        1 =>
          match self.stack.pop().unwrap() {
            Root(node) => self.docs.push(node)
            _ =>
              raise parse_error(
                self.origin,
                "unexpected end of document",
                Some(mark.line),
                Some(mark.col),
              )
          }
        _ =>
          raise parse_error(
            self.origin,
            "unexpected end of document",
            Some(mark.line),
            Some(mark.col),
          )
      }
    Alias(id~) => {
      if self.profile is Strict {
        raise unsupported(self.origin, "anchor", mark)
      }
      guard self.anchors.get(id) is Some(value) else {
        raise parse_error(
          self.origin,
          "unknown alias",
          Some(mark.line),
          Some(mark.col),
        )
      }
      self.insert(value, 0, mark)
    }
    Scalar(value~, style~, id~, tag~) => {
      self.check_anchor(id, mark)
      self.check_tag(tag, mark)
      let node = resolve_scalar(value, style, tag, self.origin, mark)
      if self.profile is Strict && node.ion_type() is Null {
        raise unsupported(self.origin, self.null_feature(), mark)
      }
      self.insert(node, id, mark)
    }
    SequenceStart(id~, tag~) => {
      self.check_anchor(id, mark)
      self.check_tag(tag, mark)
      self.reject_complex_key(mark)
      self.stack.push(Sequence([], id))
    }
    MappingStart(id~, tag~) => {
      self.check_anchor(id, mark)
      self.check_tag(tag, mark)
      self.reject_complex_key(mark)
      self.stack.push(Mapping([], id))
      self.key_stack.push("")
    }
    SequenceEnd => {
      guard self.stack.pop() is Some(Sequence(items, id)) else {
        raise parse_error(
          self.origin,
          "unexpected sequence end",
          Some(mark.line),
          Some(mark.col),
        )
      }
      self.insert(@ion.Ion::list(items), id, mark)
    }
    MappingEnd => {
      guard self.key_stack.pop() is Some(_) else {
        raise parse_error(
          self.origin,
          "unexpected mapping end",
          Some(mark.line),
          Some(mark.col),
        )
      }
      guard self.stack.pop() is Some(Mapping(fields, id)) else {
        raise parse_error(
          self.origin,
          "unexpected mapping end",
          Some(mark.line),
          Some(mark.col),
        )
      }
      self.insert(
        @ion.Ion::from_fields(
          fields.map(field => @ion.field(field.0, field.1)),
        ),
        id,
        mark,
      )
    }
  }
}

///|
fn Builder::reject_complex_key(
  self : Builder,
  mark : @yaml_lib.Marker,
) -> Unit raise @config.ConfigError {
  if self.stack.last() is Some(Mapping(_)) && self.key_stack.last() is Some("") {
    raise parse_error(
      self.origin,
      "mapping keys must be strings",
      Some(mark.line),
      Some(mark.col),
    )
  }
}

///|
fn Builder::check_anchor(
  self : Builder,
  id : Int,
  mark : @yaml_lib.Marker,
) -> Unit raise @config.ConfigError {
  if self.profile is Strict && id > 0 {
    raise unsupported(self.origin, "anchor", mark)
  }
}

///|
fn Builder::check_tag(
  self : Builder,
  tag : @yaml_lib.Tag?,
  mark : @yaml_lib.Marker,
) -> Unit raise @config.ConfigError {
  if self.profile is Strict && !is_core_tag(tag) {
    let feature = match tag {
      Some({ handle, suffix }) => handle + suffix
      None => "tag"
    }
    raise unsupported(self.origin, feature, mark)
  }
}

///|
fn Builder::null_feature(self : Builder) -> String {
  match self.key_stack.last() {
    Some(key) if key != "" => key
    _ => "null"
  }
}

///|
fn Builder::insert(
  self : Builder,
  node : @ion.Ion,
  id : Int,
  mark : @yaml_lib.Marker,
) -> Unit raise @config.ConfigError {
  if id > 0 {
    self.anchors[id] = node
  }
  if self.stack.is_empty() {
    self.stack.push(Root(node))
    return
  }
  match self.stack.last().unwrap() {
    Root(_) =>
      raise parse_error(
        self.origin,
        "expected exactly one YAML document",
        Some(mark.line),
        Some(mark.col),
      )
    Sequence(items, _) => items.push(node)
    Mapping(fields, _) => {
      let cur_key = self.key_stack[self.key_stack.length() - 1]
      if cur_key == "" {
        guard node.kind() is String(key) else {
          raise parse_error(
            self.origin,
            "mapping keys must be strings",
            Some(mark.line),
            Some(mark.col),
          )
        }
        if key == "<<" {
          raise unsupported(self.origin, "merge key", mark)
        }
        for field in fields {
          if field.0 == key {
            raise parse_error(
              self.origin,
              "duplicate key \{key}",
              Some(mark.line),
              Some(mark.col),
            )
          }
        }
        self.key_stack[self.key_stack.length() - 1] = key
      } else {
        fields.push((cur_key, node))
        self.key_stack[self.key_stack.length() - 1] = ""
      }
    }
  }
}

///|
fn is_core_tag(tag : @yaml_lib.Tag?) -> Bool {
  match tag {
    None => true
    Some({ handle, suffix }) =>
      handle == "tag:yaml.org,2002:" &&
      ["bool", "int", "float", "null", "str", "seq", "map"].contains(suffix)
  }
}

///|
/// Resolve a scalar with the YAML 1.2 core schema, matching
/// `moonbit-community/yaml` for values that fit `Int64`, and keeping larger
/// integers exact.
fn resolve_scalar(
  value : String,
  style : @yaml_lib.TScalarStyle,
  tag : @yaml_lib.Tag?,
  origin : String,
  mark : @yaml_lib.Marker,
) -> @ion.Ion raise @config.ConfigError {
  if !(style is Plain) {
    return @ion.Ion::string(value)
  }
  if tag is Some({ handle, suffix }) {
    if handle == "tag:yaml.org,2002:" {
      return match suffix {
        "bool" =>
          match value {
            "true" | "True" | "TRUE" => @ion.Ion::bool(true)
            "false" | "False" | "FALSE" => @ion.Ion::bool(false)
            _ =>
              raise parse_error(
                origin,
                "invalid !!bool \{value}",
                Some(mark.line),
                Some(mark.col),
              )
          }
        "int" => integer_ion(value)
        "float" =>
          match parse_double(value[:]) {
            Some(number) => @ion.Ion::float(number)
            None =>
              raise parse_error(
                origin,
                "invalid !!float \{value}",
                Some(mark.line),
                Some(mark.col),
              )
          }
        "null" =>
          match value {
            "~" | "null" => @ion.Ion::untyped_null()
            _ =>
              raise parse_error(
                origin,
                "invalid !!null \{value}",
                Some(mark.line),
                Some(mark.col),
              )
          }
        _ => @ion.Ion::string(value)
      }
    }
    return @ion.Ion::string(value)
  }
  from_plain(value)
}

///|
fn from_plain(value : String) -> @ion.Ion {
  match value {
    ['0', 'x', .. number] => return integer_ion_base(number.to_owned(), 16)
    ['0', 'o', .. number] => return integer_ion_base(number.to_owned(), 8)
    ['+', .. number] =>
      match try_int64(number.to_owned()) {
        Some(integer) =>
          return @ion.Ion::big_int(@bigint.BigInt::from_int64(integer))
        None => ()
      }
    "" | "~" | "null" => return @ion.Ion::untyped_null()
    "true" | "True" | "TRUE" => return @ion.Ion::bool(true)
    "false" | "False" | "FALSE" => return @ion.Ion::bool(false)
    _ => ()
  }
  match try_int64(value) {
    Some(integer) => @ion.Ion::big_int(@bigint.BigInt::from_int64(integer))
    None =>
      if is_decimal_integer(value) {
        integer_ion(value)
      } else {
        match parse_double(value[:]) {
          Some(number) => @ion.Ion::float(number)
          None => @ion.Ion::string(value)
        }
      }
  }
}

///|
fn try_int64(text : String) -> Int64? {
  Some(@string.parse_int64(text)) catch {
    _ => None
  }
}

///|
fn integer_ion(text : String) -> @ion.Ion {
  match try_int64(text) {
    Some(integer) => @ion.Ion::big_int(@bigint.BigInt::from_int64(integer))
    None => @ion.Ion::big_int(@bigint.BigInt::from_string(text))
  }
}

///|
fn integer_ion_base(digits : String, radix : Int) -> @ion.Ion {
  let parsed = try {
    Some(@string.parse_int64(digits, base=radix))
  } catch {
    _ => None
  }
  match parsed {
    Some(integer) => @ion.Ion::big_int(@bigint.BigInt::from_int64(integer))
    None => @ion.Ion::big_int(@bigint.BigInt::from_string(digits, radix~))
  }
}

///|
fn is_decimal_integer(text : String) -> Bool {
  let chars = text.to_array()
  if chars.is_empty() {
    return false
  }
  let mut i = 0
  if chars[0] is ('+' | '-') {
    i = 1
  }
  if i >= chars.length() {
    return false
  }
  while i < chars.length() {
    if chars[i] < '0' || chars[i] > '9' {
      return false
    }
    i += 1
  }
  true
}

///|
fn parse_double(v : StringView) -> Double? {
  match v {
    ".inf" | ".Inf" | ".INF" | "+.inf" | "+.Inf" | "+.INF" =>
      Some(@double.infinity)
    "-.inf" | "-.Inf" | "-.INF" => Some(@double.neg_infinity)
    ".nan" | ".NaN" | ".NAN" => Some(@double.not_a_number)
    v if v.iter().any(ch => ch.is_ascii_digit()) =>
      Some(@string.parse_double(v)) catch {
        _ => None
      }
    _ => None
  }
}

///|
fn parse_error(
  origin : String,
  message : String,
  line : Int?,
  column : Int?,
) -> @config.ConfigError {
  Parse(format="YAML", origin~, message~, line~, column~)
}

///|
fn unsupported(
  origin : String,
  feature : String,
  mark : @yaml_lib.Marker,
) -> @config.ConfigError {
  UnsupportedYaml(origin~, feature~, line=mark.line, column=mark.col)
}

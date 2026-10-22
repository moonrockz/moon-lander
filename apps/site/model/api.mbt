///|
/// The source position of an API item: the package path, the file name in the package directory and
/// the line.
pub(all) struct ApiLoc {
  path : String
  file : String
  line : Int32
} derive(Eq, Debug)

///|
pub extend ApiLoc with Eq::{equal, not_equal}

///|
pub extend ApiLoc with @debug.Debug::{to_repr}

///|
/// A method, a value or a type alias: a name, a docstring, the signature HTML of `moon doc` and the
/// source position.
pub(all) struct ApiEntry {
  name : String
  docstring : String
  signature : String
  loc : ApiLoc
} derive(Eq, Debug)

///|
pub extend ApiEntry with Eq::{equal, not_equal}

///|
pub extend ApiEntry with @debug.Debug::{to_repr}

///|
/// The implementation of a trait for a type, with its methods. `self_type` is the type as text, such
/// as `Map[String, T]`.
pub(all) struct ApiImpl {
  trait_name : String
  trait_path : String
  self_type : String
  methods : Array[ApiEntry]
} derive(Eq, Debug)

///|
pub extend ApiImpl with Eq::{equal, not_equal}

///|
pub extend ApiImpl with @debug.Debug::{to_repr}

///|
/// A type, an error type or a trait, with its methods and its trait implementations.
pub(all) struct ApiItem {
  entry : ApiEntry
  methods : Array[ApiEntry]
  impls : Array[ApiImpl]
} derive(Eq, Debug)

///|
pub extend ApiItem with Eq::{equal, not_equal}

///|
pub extend ApiItem with @debug.Debug::{to_repr}

///|
/// The public API of one package, from its `package_data.json`.
pub(all) struct ApiPackage {
  path : String
  types : Array[ApiItem]
  errors : Array[ApiItem]
  traits : Array[ApiItem]
  aliases : Array[ApiEntry]
  values : Array[ApiEntry]
} derive(Eq, Debug)

///|
pub extend ApiPackage with Eq::{equal, not_equal}

///|
pub extend ApiPackage with @debug.Debug::{to_repr}

///|
/// The reader of one `moon doc` JSON file. The first shape error stops it, and the problem names the
/// file and the key.
priv struct Reader {
  file : String
}

///|
fn Reader::fail(self : Reader, key : String, expected : String) -> Invalid {
  Invalid([problem(self.file, "`\{key}` must be \{expected}")])
}

///|
fn Reader::object(
  self : Reader,
  json : Json,
  key : String,
) -> Map[String, Json] raise Invalid {
  guard json is Object(fields) else { raise self.fail(key, "an object") }
  fields
}

///|
fn Reader::field(
  self : Reader,
  fields : Map[String, Json],
  at : String,
  name : String,
) -> Json raise Invalid {
  let key = if at == "" { name } else { "\{at}.\{name}" }
  guard fields.get(name) is Some(value) else {
    raise Invalid([problem(self.file, "missing key `\{key}`")])
  }
  value
}

///|
fn Reader::text(
  self : Reader,
  fields : Map[String, Json],
  at : String,
  name : String,
) -> String raise Invalid {
  guard self.field(fields, at, name) is String(value) else {
    raise self.fail(if at == "" { name } else { "\{at}.\{name}" }, "a string")
  }
  value
}

///|
fn Reader::array(
  self : Reader,
  fields : Map[String, Json],
  at : String,
  name : String,
) -> Array[Json] raise Invalid {
  guard self.field(fields, at, name) is Array(values) else {
    raise self.fail(if at == "" { name } else { "\{at}.\{name}" }, "an array")
  }
  values
}

///|
fn Reader::entry(
  self : Reader,
  json : Json,
  at : String,
) -> ApiEntry raise Invalid {
  let fields = self.object(json, at)
  let loc_key = "\{at}.loc"
  let loc = self.object(self.field(fields, at, "loc"), loc_key)
  guard self.field(loc, loc_key, "line") is Number(line, ..) else {
    raise self.fail("\{loc_key}.line", "a number")
  }
  {
    name: self.text(fields, at, "name"),
    docstring: self.text(fields, at, "docstring"),
    signature: self.text(fields, at, "signature"),
    loc: {
      path: self.text(loc, loc_key, "path"),
      file: self.text(loc, loc_key, "file"),
      line: line.to_int(),
    },
  }
}

///|
fn Reader::members(
  self : Reader,
  values : Array[Json],
  at : String,
) -> Array[ApiEntry] raise Invalid {
  let out = []
  for i, value in values {
    out.push(self.entry(value, "\{at}[\{i}]"))
  }
  out
}

///|
/// A type, error or trait. Each has `impls`. A type or an error also has `methods`; a trait has
/// none, so only a trait can be without that key.
fn Reader::item(
  self : Reader,
  json : Json,
  at : String,
  is_trait~ : Bool,
) -> ApiItem raise Invalid {
  let fields = self.object(json, at)
  let methods = if is_trait && !fields.contains("methods") {
    []
  } else {
    self.members(self.array(fields, at, "methods"), "\{at}.methods")
  }
  let impls = []
  for i, value in self.array(fields, at, "impls") {
      let impl_at = "\{at}.impls[\{i}]"
      let impl_fields = self.object(value, impl_at)
      let trait_at = "\{impl_at}.trait"
      let trait_fields = self.object(
        self.field(impl_fields, impl_at, "trait"),
        trait_at,
      )
    impls.push({
      trait_name: self.text(trait_fields, trait_at, "name"),
      trait_path: self.text(trait_fields, trait_at, "path"),
      self_type: type_text(self.field(impl_fields, impl_at, "self")),
      methods: self.members(
        self.array(impl_fields, impl_at, "methods"),
        "\{impl_at}.methods",
      ),
    })
  }
  { entry: self.entry(json, at), methods, impls }
}

///|
fn Reader::items(
  self : Reader,
  fields : Map[String, Json],
  name : String,
) -> Array[ApiItem] raise Invalid {
  let out = []
  for i, value in self.array(fields, "", name) {
    out.push(self.item(value, "\{name}[\{i}]", is_trait=name == "traits"))
  }
  out
}

///|
/// The text of the `self` type of an implementation: a named type, a type parameter, or a type
/// constructor with its arguments. A kind that this reader does not know shows as `_`, so a new kind of
/// type does not stop the build.
fn type_text(json : Json) -> String {
  guard json is Object(fields) else { return "_" }
  match (fields.get("kind"), fields.get("name"), fields.get("constructor")) {
    (Some(String("constr")), _, Some(Object(type_constructor))) => {
      let name = match type_constructor.get("name") {
        Some(String(name)) => name
        _ => "_"
      }
      match fields.get("arguments") {
        Some(Array(args)) if !args.is_empty() =>
          name + "[" + args.map(type_text).join(", ") + "]"
        _ => name
      }
    }
    (Some(String("param")), Some(String(name)), _) => name
    (None, Some(String(name)), _) => name
    _ => "_"
  }
}

///|
fn parse_json(file : String, text : String) -> Json raise Invalid {
  @json.parse(text) catch {
    error => raise Invalid([problem(file, "not valid JSON: \{error}")])
  }
}

///|
/// Read the `package_data.json` that `moon doc` writes for one package. When the JSON does not have
/// the expected shape, the problem names `file` and the key, so a format change in `moon doc` stops
/// the build.
pub fn ApiPackage::parse(file : String, text : String) -> ApiPackage raise Invalid {
  let reader : Reader = { file, }
  let fields = reader.object(parse_json(file, text), "(root)")
  {
    path: reader.text(fields, "", "name"),
    types: reader.items(fields, "types"),
    errors: reader.items(fields, "errors"),
    traits: reader.items(fields, "traits"),
    aliases: reader.members(reader.array(fields, "", "typealias"), "typealias"),
    values: reader.members(reader.array(fields, "", "values"), "values"),
  }
}

///|
/// The package paths in the `module_index.json` that `moon doc` writes for one module, in tree order.
pub fn api_index_packages(
  file : String,
  text : String,
) -> Array[String] raise Invalid {
  let reader : Reader = { file, }
  let out = []
  fn walk(json : Json, at : String) raise Invalid {
    let fields = reader.object(json, at)
    match reader.field(fields, at, "package") {
      Null => ()
      package_json => {
        let package_at = if at == "" { "package" } else { "\{at}.package" }
        out.push(
          reader.text(reader.object(package_json, package_at), package_at, "path"),
        )
      }
    }
    for i, child in reader.array(fields, at, "childs") {
      walk(child, if at == "" { "childs[\{i}]" } else { "\{at}.childs[\{i}]" })
    }
  }

  walk(parse_json(file, text), "")
  out
}

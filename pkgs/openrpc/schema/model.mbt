///|
pub(all) enum SimpleType {
  ArrayType
  BooleanType
  IntegerType
  NullType
  NumberType
  ObjectType
  StringType
} derive(Eq, Debug)

///|
pub fn SimpleType::to_string(self : SimpleType) -> String {
  match self {
    ArrayType => "array"
    BooleanType => "boolean"
    IntegerType => "integer"
    NullType => "null"
    NumberType => "number"
    ObjectType => "object"
    StringType => "string"
  }
}

///|
pub struct TypeConstraint {
  types : Array[SimpleType]
  union : Bool
} derive(Debug)

///|
pub fn TypeConstraint::one(type_ : SimpleType) -> TypeConstraint {
  { types: [type_], union: false, }
}

///|
pub fn TypeConstraint::many(
  types : Array[SimpleType],
) -> Result[TypeConstraint, @json.Diagnostic] {
  if types.is_empty() {
    return Err(
      @json.Diagnostic::new(@json.InvalidSchema, "A type set must be nonempty"),
    )
  }
  let seen : Set[String] = Set([])
  for type_ in types {
    let name = type_.to_string()
    if seen.contains(name) {
      return Err(
        @json.Diagnostic::new(
          @json.InvalidSchema,
          "A type set must contain unique types",
        ),
      )
    }
    seen.add(name)
  }
  Ok({ types: types.copy(), union: true, })
}

///|
pub fn TypeConstraint::types(self : TypeConstraint) -> Array[SimpleType] {
  self.types.copy()
}

///|
pub fn TypeConstraint::is_union(self : TypeConstraint) -> Bool {
  self.union
}

///|
pub fn TypeConstraint::to_json(self : TypeConstraint) -> @json.Value {
  if self.union {
    @json.Value::array(self.types.map(t => @json.Value::string(t.to_string())))
  } else {
    @json.Value::string(self.types[0].to_string())
  }
}

///|
pub struct NonNegativeInteger {
  number : @json.Number
} derive(Eq, Debug)

///|
pub fn NonNegativeInteger::from_number(
  number : @json.Number,
) -> Result[NonNegativeInteger, @json.Diagnostic] {
  if number.is_integer() &&
    number.numeric_compare(@json.Number::parse("0").unwrap()) >= 0 {
    Ok({ number, })
  } else {
    Err(
      @json.Diagnostic::new(
        @json.InvalidSchema,
        "Expected a nonnegative mathematical integer",
      ),
    )
  }
}

///|
pub fn NonNegativeInteger::parse(
  token : String,
) -> Result[NonNegativeInteger, @json.Diagnostic] {
  match @json.Number::parse(token) {
    Ok(number) => NonNegativeInteger::from_number(number)
    Err(d) => Err(d)
  }
}

///|
pub fn NonNegativeInteger::number(self : NonNegativeInteger) -> @json.Number {
  self.number
}

///|
pub struct PositiveNumber {
  number : @json.Number
} derive(Eq, Debug)

///|
pub fn PositiveNumber::from_number(
  number : @json.Number,
) -> Result[PositiveNumber, @json.Diagnostic] {
  if number.numeric_compare(@json.Number::parse("0").unwrap()) > 0 {
    Ok({ number, })
  } else {
    Err(
      @json.Diagnostic::new(@json.InvalidSchema, "Expected a positive number"),
    )
  }
}

///|
pub fn PositiveNumber::parse(
  token : String,
) -> Result[PositiveNumber, @json.Diagnostic] {
  match @json.Number::parse(token) {
    Ok(number) => PositiveNumber::from_number(number)
    Err(d) => Err(d)
  }
}

///|
pub fn PositiveNumber::number(self : PositiveNumber) -> @json.Number {
  self.number
}

///|
pub(all) enum Items {
  SingleItems(Schema)
  TupleItems(Array[Schema])
} derive(Debug)

///|
pub(all) enum Dependency {
  SchemaDependency(Schema)
  PropertyDependencies(Array[String])
} derive(Debug)

///|
pub(all) enum Keyword {
  Id(@reference.UriReference)
  Dialect(@reference.UriReference)
  Ref(@reference.Reference)
  Comment(String)
  Title(String)
  Description(String)
  Default(@json.Value)
  ReadOnly(Bool)
  WriteOnly(Bool)
  Examples(Array[@json.Value])
  MultipleOf(PositiveNumber)
  Maximum(@json.Number)
  ExclusiveMaximum(@json.Number)
  Minimum(@json.Number)
  ExclusiveMinimum(@json.Number)
  MaxLength(NonNegativeInteger)
  MinLength(NonNegativeInteger)
  Pattern(String)
  AdditionalItems(Schema)
  Items(Items)
  MaxItems(NonNegativeInteger)
  MinItems(NonNegativeInteger)
  UniqueItems(Bool)
  Contains(Schema)
  MaxProperties(NonNegativeInteger)
  MinProperties(NonNegativeInteger)
  Required(Array[String])
  AdditionalProperties(Schema)
  Definitions(Array[(String, Schema)])
  Properties(Array[(String, Schema)])
  PatternProperties(Array[(String, Schema)])
  Dependencies(Array[(String, Dependency)])
  PropertyNames(Schema)
  Const(@json.Value)
  Enum(Array[@json.Value])
  Type(TypeConstraint)
  Format(String)
  ContentMediaType(String)
  ContentEncoding(String)
  If(Schema)
  Then(Schema)
  Else(Schema)
  AllOf(Array[Schema])
  AnyOf(Array[Schema])
  OneOf(Array[Schema])
  Not(Schema)
} derive(Debug)

///|
pub fn Keyword::name(self : Keyword) -> String {
  match self {
    Id(_) => "$id"
    Dialect(_) => "$schema"
    Ref(_) => "$ref"
    Comment(_) => "$comment"
    Title(_) => "title"
    Description(_) => "description"
    Default(_) => "default"
    ReadOnly(_) => "readOnly"
    WriteOnly(_) => "writeOnly"
    Examples(_) => "examples"
    MultipleOf(_) => "multipleOf"
    Maximum(_) => "maximum"
    ExclusiveMaximum(_) => "exclusiveMaximum"
    Minimum(_) => "minimum"
    ExclusiveMinimum(_) => "exclusiveMinimum"
    MaxLength(_) => "maxLength"
    MinLength(_) => "minLength"
    Pattern(_) => "pattern"
    AdditionalItems(_) => "additionalItems"
    Items(_) => "items"
    MaxItems(_) => "maxItems"
    MinItems(_) => "minItems"
    UniqueItems(_) => "uniqueItems"
    Contains(_) => "contains"
    MaxProperties(_) => "maxProperties"
    MinProperties(_) => "minProperties"
    Required(_) => "required"
    AdditionalProperties(_) => "additionalProperties"
    Definitions(_) => "definitions"
    Properties(_) => "properties"
    PatternProperties(_) => "patternProperties"
    Dependencies(_) => "dependencies"
    PropertyNames(_) => "propertyNames"
    Const(_) => "const"
    Enum(_) => "enum"
    Type(_) => "type"
    Format(_) => "format"
    ContentMediaType(_) => "contentMediaType"
    ContentEncoding(_) => "contentEncoding"
    If(_) => "if"
    Then(_) => "then"
    Else(_) => "else"
    AllOf(_) => "allOf"
    AnyOf(_) => "anyOf"
    OneOf(_) => "oneOf"
    Not(_) => "not"
  }
}

///|
let all_names : Array[String] = [
  "$id", "$schema", "$ref", "$comment", "title", "description", "default", "readOnly",
  "writeOnly", "examples", "multipleOf", "maximum", "exclusiveMaximum", "minimum",
  "exclusiveMinimum", "maxLength", "minLength", "pattern", "additionalItems", "items",
  "maxItems", "minItems", "uniqueItems", "contains", "maxProperties", "minProperties",
  "required", "additionalProperties", "definitions", "properties", "patternProperties",
  "dependencies", "propertyNames", "const", "enum", "type", "format", "contentMediaType",
  "contentEncoding", "if", "then", "else", "allOf", "anyOf", "oneOf", "not",
]

///|
pub fn keyword_names() -> Array[String] {
  all_names.copy()
}

///|
fn schema_map_json(
  entries : Array[(String, Schema)],
) -> Result[@json.Value, @json.Diagnostic] {
  @json.Value::object(entries.map(entry => (entry.0, entry.1.to_json())))
}

///|
pub fn Keyword::to_json(
  self : Keyword,
) -> Result[@json.Value, @json.Diagnostic] {
  Ok(
    match self {
      Id(ref_) | Dialect(ref_) => @json.Value::string(ref_.text())
      Ref(ref_) => @json.Value::string(ref_.text())
      Comment(text)
      | Title(text)
      | Description(text)
      | Pattern(text)
      | Format(text)
      | ContentMediaType(text)
      | ContentEncoding(text) => @json.Value::string(text)
      Default(value) | Const(value) => value
      ReadOnly(b) | WriteOnly(b) | UniqueItems(b) => @json.Value::boolean(b)
      Examples(values) | Enum(values) => @json.Value::array(values)
      MultipleOf(n) => @json.Value::number(n.number)
      Maximum(n) | ExclusiveMaximum(n) | Minimum(n) | ExclusiveMinimum(n) =>
        @json.Value::number(n)
      MaxLength(n)
      | MinLength(n)
      | MaxItems(n)
      | MinItems(n)
      | MaxProperties(n)
      | MinProperties(n) => @json.Value::number(n.number)
      AdditionalItems(schema)
      | Contains(schema)
      | AdditionalProperties(schema)
      | PropertyNames(schema)
      | If(schema)
      | Then(schema)
      | Else(schema)
      | Not(schema) => schema.to_json()
      Items(SingleItems(schema)) => schema.to_json()
      Items(TupleItems(schemas))
      | AllOf(schemas)
      | AnyOf(schemas)
      | OneOf(schemas) =>
        @json.Value::array(schemas.map(schema => schema.to_json()))
      Required(names) =>
        @json.Value::array(names.map(name => @json.Value::string(name)))
      Definitions(entries) | Properties(entries) | PatternProperties(entries) =>
        return schema_map_json(entries)
      Dependencies(entries) =>
        return @json.Value::object(
          entries.map(entry => {
            let value = match entry.1 {
              SchemaDependency(schema) => schema.to_json()
              PropertyDependencies(names) =>
                @json.Value::array(names.map(name => @json.Value::string(name)))
            }
            (entry.0, value)
          }),
        )
      Type(types) => types.to_json()
    },
  )
}

///|
pub struct SchemaObject {
  value : @json.Value
} derive(Debug)

///|
pub struct ReferenceObject {
  reference : @reference.Reference
  siblings : @json.Value
} derive(Debug)

///|
pub fn ReferenceObject::reference(
  self : ReferenceObject,
) -> @reference.Reference {
  self.reference
}

///|
pub fn ReferenceObject::siblings(self : ReferenceObject) -> @json.Value {
  self.siblings
}

///|
pub(all) enum SchemaKind {
  BooleanSchema(Bool)
  ObjectSchema(SchemaObject)
  ReferenceSchema(ReferenceObject)
  UnsupportedDialectSchema(@reference.UriReference, @json.Value)
} derive(Debug)

///|
fn draft07(text : String) -> Bool {
  @domain.draft07_dialect(text)
}

///|
pub fn Schema::kind(self : Schema) -> SchemaKind {
  match self.value.kind() {
    @json.Boolean(b) => BooleanSchema(b)
    @json.Object(fields) => {
      if self.value.get("$schema") is Some(dialect) &&
        !draft07(dialect.text().unwrap()) {
        return UnsupportedDialectSchema(
          @reference.UriReference::parse(
            dialect.text().unwrap(),
            limits=@json.Limits::unlimited(),
          ).unwrap(),
          self.value,
        )
      }
      if self.value.get("$ref") is Some(ref_) {
        return ReferenceSchema({
          reference: @reference.Reference::parse(
            ref_.text().unwrap(),
            limits=@json.Limits::unlimited(),
          ).unwrap(),
          siblings: @json.Value::object(
            fields.filter(entry => entry.0 != "$ref"),
          ).unwrap(),
        })
      }
      ObjectSchema({ value: self.value, })
    }
    _ => abort("Schema constructor invariant")
  }
}

///|
pub fn SchemaObject::keywords(self : SchemaObject) -> Array[Keyword] {
  guard self.value.kind() is @json.Object(fields) else {
    abort("Schema object invariant")
  }
  fields
  .filter(entry => all_names.contains(entry.0))
  .map(entry => {
    decode_keyword(entry.0, entry.1, limits=@json.Limits::unlimited()).unwrap()
  })
}

///|
pub fn SchemaObject::keyword(self : SchemaObject, name : String) -> Keyword? {
  if !all_names.contains(name) {
    return None
  }
  self.value
  .get(name)
  .map(value => {
    decode_keyword(name, value, limits=@json.Limits::unlimited()).unwrap()
  })
}

///|
pub fn SchemaObject::additional_fields(
  self : SchemaObject,
) -> Array[(String, @json.Value)] {
  guard self.value.kind() is @json.Object(fields) else {
    abort("Schema object invariant")
  }
  fields.filter(entry => {
    !all_names.contains(entry.0) && !entry.0.has_prefix("x-")
  })
}

///|
pub fn SchemaObject::extensions(self : SchemaObject) -> @domain.Extensions {
  guard self.value.kind() is @json.Object(fields) else {
    abort("Schema object invariant")
  }
  @domain.Extensions::from_json(
    @json.Value::object(fields.filter(entry => entry.0.has_prefix("x-"))).unwrap(),
  ).unwrap()
}

///|
pub fn Schema::from_keywords(
  keywords : Array[Keyword],
  additional_fields~ : Array[(String, @json.Value)] = [],
  extensions~ : @domain.Extensions = @domain.Extensions::empty(),
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[Schema, @json.Diagnostic] {
  let fields = []
  for keyword in keywords {
    match keyword.to_json() {
      Ok(value) => fields.push((keyword.name(), value))
      Err(d) => {
        let path = [keyword.name()]
        for part in d.path() {
          path.push(part)
        }
        return Err(@json.Diagnostic::new(d.code(), d.message(), path~))
      }
    }
  }
  for (name, value) in additional_fields {
    if all_names.contains(name) || name.has_prefix("x-") {
      return Err(
        @json.Diagnostic::new(
          @json.InvalidSchema,
          "Known keywords and extensions require their typed inputs",
          path=[name],
        ),
      )
    }
    fields.push((name, value))
  }
  for (name, value) in extensions.entries() {
    fields.push((name.to_string(), value))
  }
  match @json.Value::object(fields) {
    Ok(value) => Schema::from_json(value, limits~)
    Err(d) => Err(d)
  }
}

///|
pub extend SimpleType with Eq::{equal, not_equal}

///|
pub extend SimpleType with @debug.Debug::{to_repr}

///|
pub extend TypeConstraint with @debug.Debug::{to_repr}

///|
pub extend NonNegativeInteger with Eq::{equal, not_equal}

///|
pub extend NonNegativeInteger with @debug.Debug::{to_repr}

///|
pub extend PositiveNumber with Eq::{equal, not_equal}

///|
pub extend PositiveNumber with @debug.Debug::{to_repr}

///|
pub extend Items with @debug.Debug::{to_repr}

///|
pub extend Dependency with @debug.Debug::{to_repr}

///|
pub extend Keyword with @debug.Debug::{to_repr}

///|
pub extend SchemaObject with @debug.Debug::{to_repr}

///|
pub extend ReferenceObject with @debug.Debug::{to_repr}

///|
pub extend SchemaKind with @debug.Debug::{to_repr}

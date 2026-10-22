///|
priv suberror SchemaRead {
  SchemaRead(@json.Diagnostic)
} derive(Debug)

///|
fn invalid(message : String, path~ : Array[String] = []) -> @json.Diagnostic {
  @json.Diagnostic::new(@json.InvalidSchema, message, path~)
}

///|
fn string_value(value : @json.Value) -> String raise SchemaRead {
  match value.text() {
    Some(text) => text
    None => raise SchemaRead(invalid("Expected a string"))
  }
}

///|
fn boolean_value(value : @json.Value) -> Bool raise SchemaRead {
  match value.kind() {
    @json.Boolean(b) => b
    _ => raise SchemaRead(invalid("Expected a boolean"))
  }
}

///|
fn number_value(value : @json.Value) -> @json.Number raise SchemaRead {
  match value.kind() {
    @json.Numeric(n) => n
    _ => raise SchemaRead(invalid("Expected a number"))
  }
}

///|
fn array_value(value : @json.Value) -> Array[@json.Value] raise SchemaRead {
  match value.kind() {
    @json.Array(items) => items
    _ => raise SchemaRead(invalid("Expected an array"))
  }
}

///|
fn object_value(
  value : @json.Value,
) -> Array[(String, @json.Value)] raise SchemaRead {
  match value.kind() {
    @json.Object(fields) => fields
    _ => raise SchemaRead(invalid("Expected an object"))
  }
}

///|
fn shallow_schema(value : @json.Value) -> Schema raise SchemaRead {
  if !schema_kind(value) {
    raise SchemaRead(invalid("Expected an object or boolean schema"))
  }
  { value, }
}

///|
fn schema_array(value : @json.Value) -> Array[Schema] raise SchemaRead {
  let items = array_value(value)
  if items.is_empty() {
    raise SchemaRead(invalid("A schema array must be nonempty"))
  }
  let result = []
  for i, value in items {
    if !schema_kind(value) {
      raise SchemaRead(
        invalid("Expected an object or boolean schema", path=[i.to_string()]),
      )
    }
    result.push(Schema::{ value, })
  }
  result
}

///|
fn schema_dictionary(
  value : @json.Value,
) -> Array[(String, Schema)] raise SchemaRead {
  object_value(value).map(entry => {
    if !schema_kind(entry.1) {
      raise SchemaRead(
        invalid("Expected an object or boolean schema", path=[entry.0]),
      )
    }
    (entry.0, Schema::{ value: entry.1, })
  })
}

///|
fn names_value(value : @json.Value) -> Array[String] raise SchemaRead {
  let names = []
  let seen : Set[String] = Set([])
  for i, item in array_value(value) {
    guard item.text() is Some(name) else {
      raise SchemaRead(
        invalid("Expected a property name string", path=[i.to_string()]),
      )
    }
    if seen.contains(name) {
      raise SchemaRead(
        invalid("Property names must be unique", path=[i.to_string()]),
      )
    }
    seen.add(name)
    names.push(name)
  }
  names
}

///|
fn reference_value(
  value : @json.Value,
  limits : @json.Limits,
) -> @reference.Reference raise SchemaRead {
  match @reference.Reference::parse(string_value(value), limits~) {
    Ok(ref_) => ref_
    Err(d) => raise SchemaRead(d)
  }
}

///|
fn uri_value(
  value : @json.Value,
  limits : @json.Limits,
) -> @reference.UriReference raise SchemaRead {
  match @reference.UriReference::parse(string_value(value), limits~) {
    Ok(uri) => uri
    Err(d) => raise SchemaRead(d)
  }
}

///|
fn simple_type(value : @json.Value) -> SimpleType raise SchemaRead {
  match string_value(value) {
    "array" => ArrayType
    "boolean" => BooleanType
    "integer" => IntegerType
    "null" => NullType
    "number" => NumberType
    "object" => ObjectType
    "string" => StringType
    _ => raise SchemaRead(invalid("Unknown draft-07 simple type"))
  }
}

///|
fn count_value(value : @json.Value) -> NonNegativeInteger raise SchemaRead {
  match NonNegativeInteger::from_number(number_value(value)) {
    Ok(n) => n
    Err(d) => raise SchemaRead(d)
  }
}

///|
fn decode_keyword(
  name : String,
  value : @json.Value,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[Keyword, @json.Diagnostic] {
  Ok(
    match name {
      "$id" => Id(uri_value(value, limits))
      "$schema" => Dialect(uri_value(value, limits))
      "$ref" => Ref(reference_value(value, limits))
      "$comment" => Comment(string_value(value))
      "title" => Title(string_value(value))
      "description" => Description(string_value(value))
      "default" => Default(value)
      "readOnly" => ReadOnly(boolean_value(value))
      "writeOnly" => WriteOnly(boolean_value(value))
      "examples" => Examples(array_value(value))
      "multipleOf" =>
        match PositiveNumber::from_number(number_value(value)) {
          Ok(n) => MultipleOf(n)
          Err(d) => raise SchemaRead(d)
        }
      "maximum" => Maximum(number_value(value))
      "exclusiveMaximum" => ExclusiveMaximum(number_value(value))
      "minimum" => Minimum(number_value(value))
      "exclusiveMinimum" => ExclusiveMinimum(number_value(value))
      "maxLength" => MaxLength(count_value(value))
      "minLength" => MinLength(count_value(value))
      "pattern" => Pattern(string_value(value))
      "additionalItems" => AdditionalItems(shallow_schema(value))
      "items" =>
        Items(
          match value.kind() {
            @json.Array(_) => TupleItems(schema_array(value))
            _ => SingleItems(shallow_schema(value))
          },
        )
      "maxItems" => MaxItems(count_value(value))
      "minItems" => MinItems(count_value(value))
      "uniqueItems" => UniqueItems(boolean_value(value))
      "contains" => Contains(shallow_schema(value))
      "maxProperties" => MaxProperties(count_value(value))
      "minProperties" => MinProperties(count_value(value))
      "required" => Required(names_value(value))
      "additionalProperties" => AdditionalProperties(shallow_schema(value))
      "definitions" => Definitions(schema_dictionary(value))
      "properties" => Properties(schema_dictionary(value))
      "patternProperties" => PatternProperties(schema_dictionary(value))
      "dependencies" =>
        Dependencies(
          object_value(value).map(entry => {
            let dependency = match entry.1.kind() {
              @json.Array(_) => {
                let names = names_value(entry.1) catch {
                  SchemaRead(d) => {
                    let path = [entry.0]
                    for part in d.path() {
                      path.push(part)
                    }
                    raise SchemaRead(
                      @json.Diagnostic::new(d.code(), d.message(), path~),
                    )
                  }
                }
                PropertyDependencies(names)
              }
              _ => {
                if !schema_kind(entry.1) {
                  raise SchemaRead(
                    invalid("Expected a schema or property-name array", path=[
                      entry.0,
                    ]),
                  )
                }
                SchemaDependency(Schema::{ value: entry.1, })
              }
            }
            (entry.0, dependency)
          }),
        )
      "propertyNames" => PropertyNames(shallow_schema(value))
      "const" => Const(value)
      "enum" => {
        let items = array_value(value)
        if items.is_empty() {
          raise SchemaRead(invalid("Enum values must be nonempty"))
        }
        Enum(items)
      }
      "type" =>
        Type(
          match value.kind() {
            @json.String(_) => TypeConstraint::one(simple_type(value))
            _ =>
              match TypeConstraint::many(array_value(value).map(simple_type)) {
                Ok(types) => types
                Err(d) => raise SchemaRead(d)
              }
          },
        )
      "format" => Format(string_value(value))
      "contentMediaType" => ContentMediaType(string_value(value))
      "contentEncoding" => ContentEncoding(string_value(value))
      "if" => If(shallow_schema(value))
      "then" => Then(shallow_schema(value))
      "else" => Else(shallow_schema(value))
      "allOf" => AllOf(schema_array(value))
      "anyOf" => AnyOf(schema_array(value))
      "oneOf" => OneOf(schema_array(value))
      "not" => Not(shallow_schema(value))
      _ => raise SchemaRead(invalid("Unknown typed keyword"))
    },
  ) catch {
    SchemaRead(d) => Err(d)
  }
}

///|
priv enum SchemaPath {
  RootPath
  PathStep(SchemaPath, String)
}

///|
fn path_tokens(
  path : SchemaPath,
  suffix~ : Array[String] = [],
) -> Array[String] {
  let tokens = []
  let mut current = path
  while current is PathStep(parent, token) {
    tokens.push(token)
    current = parent
  }
  let result = Array::makei(tokens.length(), i => {
    tokens[tokens.length() - 1 - i]
  })
  for token in suffix {
    result.push(token)
  }
  result
}

///|
fn with_path(d : @json.Diagnostic, path : SchemaPath) -> @json.Diagnostic {
  @json.Diagnostic::new(
    d.code(),
    d.message(),
    path=path_tokens(path, suffix=d.path()),
  )
}

///|
fn decode_schema(
  value : @json.Value,
  limits : @json.Limits,
) -> Result[Schema, @json.Diagnostic] {
  // Also bounds literal/unknown data and shared value graphs, before queuing.
  match @json.write(value, limits~) {
    Err(d) => return Err(d)
    Ok(_) => ()
  }
  let stack : Array[(@json.Value, SchemaPath)] = [(value, RootPath)]
  while stack.pop() is Some((current, path)) {
    match current.kind() {
      @json.Boolean(_) => continue
      @json.Object(fields) => {
        if current.get("$schema") is Some(declaration) {
          match decode_keyword("$schema", declaration, limits~) {
            Ok(Dialect(ref_)) => if !draft07(ref_.text()) { continue }
            Ok(_) => abort("Dialect decoding invariant")
            Err(d) => return Err(with_path(d, PathStep(path, "$schema")))
          }
        }
        if current.get("$ref") is Some(reference) {
          match decode_keyword("$ref", reference, limits~) {
            Ok(_) => continue
            Err(d) => return Err(with_path(d, PathStep(path, "$ref")))
          }
        }
        for (name, item) in fields {
          if !all_names.contains(name) {
            continue
          }
          let at = PathStep(path, name)
          let keyword = match decode_keyword(name, item, limits~) {
            Ok(keyword) => keyword
            Err(d) => return Err(with_path(d, at))
          }
          match keyword {
            AdditionalItems(child_)
            | Contains(child_)
            | AdditionalProperties(child_)
            | PropertyNames(child_)
            | If(child_)
            | Then(child_)
            | Else(child_)
            | Not(child_)
            | Items(SingleItems(child_)) => stack.push((child_.value, at))
            Items(TupleItems(schemas))
            | AllOf(schemas)
            | AnyOf(schemas)
            | OneOf(schemas) =>
              for i, schema in schemas {
                stack.push((schema.value, PathStep(at, i.to_string())))
              }
            Definitions(entries)
            | Properties(entries)
            | PatternProperties(entries) =>
              for (key, schema) in entries {
                stack.push((schema.value, PathStep(at, key)))
              }
            Dependencies(entries) =>
              for (key, dependency) in entries {
                if dependency is SchemaDependency(schema) {
                  stack.push((schema.value, PathStep(at, key)))
                }
              }
            _ => ()
          }
        }
      }
      _ =>
        return Err(
          invalid("Schema must be an object or boolean", path=path_tokens(path)),
        )
    }
  }
  Ok(Schema::{ value, })
}

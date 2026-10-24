///|
/// Merge `overlay` over `base`. A null overlay keeps the base value. A secret
/// reference replaces and is not merged with a struct. Two structs merge field
/// by field, with base fields first and new overlay fields after. Two lists use
/// `policy`, or a matching entry of `key_policies` when one exists for the path.
/// In all other cases the overlay value wins. The inputs do not change, and
/// unchanged subtrees are shared.
pub fn merge(
  base : ConfigValue,
  overlay : ConfigValue,
  policy~ : MergePolicy = Replace,
  key_policies~ : Array[(KeyPath, MergePolicy)] = [],
  source~ : String = "overlay",
  secret_syntax~ : SecretSyntax = Standard,
) -> ConfigValue raise ConfigError {
  merge_at(base, overlay, [], policy, key_policies, source, secret_syntax)
}

///|
fn merge_at(
  base : ConfigValue,
  overlay : ConfigValue,
  path : Array[String],
  source_policy : MergePolicy,
  key_policies : Array[(KeyPath, MergePolicy)],
  source : String,
  secret_syntax : SecretSyntax,
) -> ConfigValue raise ConfigError {
  if overlay.ion.is_null() {
    return base
  }
  if is_secret_reference(base, secret_syntax) ||
    is_secret_reference(overlay, secret_syntax) {
    return overlay
  }
  match (base.ion.kind(), overlay.ion.kind()) {
    (Struct(base_fields), Struct(overlay_fields)) =>
      merge_structs(
        base,
        base_fields,
        overlay,
        overlay_fields,
        path,
        source_policy,
        key_policies,
        source,
        secret_syntax,
      )
    (List(base_items), List(overlay_items)) =>
      merge_lists(
        base,
        base_items,
        overlay,
        overlay_items,
        path,
        source_policy,
        key_policies,
        source,
        secret_syntax,
      )
    _ => overlay
  }
}

///|
fn merge_structs(
  base : ConfigValue,
  base_fields : Array[@ion.Field],
  overlay : ConfigValue,
  overlay_fields : Array[@ion.Field],
  path : Array[String],
  source_policy : MergePolicy,
  key_policies : Array[(KeyPath, MergePolicy)],
  source : String,
  secret_syntax : SecretSyntax,
) -> ConfigValue raise ConfigError {
  let merged = base_fields.copy()
  for field in overlay_fields {
    // A null overlay field keeps the base field, or adds nothing.
    if field.value().is_null() {
      continue
    }
    let name = field.name()
    let child_path = match name.text() {
      Some(text) => [..path, text]
      None => path
    }
    match merged.search_by(existing => existing.name().text() == name.text()) {
      Some(index) => {
        let value = merge_at(
          { ion: merged[index].value() },
          { ion: field.value() },
          child_path,
          source_policy,
          key_policies,
          source,
          secret_syntax,
        )
        merged[index] = @ion.Field::from_token(name, value.ion)
      }
      None => merged.push(field)
    }
  }
  // The result keeps the overlay annotations if it has any, else the base ones.
  let annotations = if overlay.ion.has_annotations() {
    overlay.ion.annotations()
  } else {
    base.ion.annotations()
  }
  { ion: @ion.Ion::from_fields(merged).with_annotations(annotations) }
}

///|
fn merge_lists(
  base : ConfigValue,
  base_items : Array[@ion.Ion],
  overlay : ConfigValue,
  overlay_items : Array[@ion.Ion],
  path : Array[String],
  source_policy : MergePolicy,
  key_policies : Array[(KeyPath, MergePolicy)],
  source : String,
  secret_syntax : SecretSyntax,
) -> ConfigValue raise ConfigError {
  match resolve_policy(path, source_policy, key_policies) {
    Replace => overlay
    Append => {
      let items = base_items.copy()
      items.append(overlay_items)
      {
        ion: @ion.Ion::list(items).with_annotations(
          list_annotations(base, overlay),
        ),
      }
    }
    MergeByKey(key_name) =>
      merge_lists_by_key(
        base,
        base_items,
        overlay,
        overlay_items,
        path,
        key_name,
        source_policy,
        key_policies,
        source,
        secret_syntax,
      )
  }
}

///|
fn merge_lists_by_key(
  base : ConfigValue,
  base_items : Array[@ion.Ion],
  overlay : ConfigValue,
  overlay_items : Array[@ion.Ion],
  path : Array[String],
  key_name : String,
  source_policy : MergePolicy,
  key_policies : Array[(KeyPath, MergePolicy)],
  source : String,
  secret_syntax : SecretSyntax,
) -> ConfigValue raise ConfigError {
  // A list under the struct root always has a non-empty path.
  let key_path : KeyPath = { names: path.copy() }
  let result = []
  let index_by_key : Map[String, Int] = Map([])
  for index, item in base_items {
    let key = list_item_key({ ion: item }, key_name, key_path, index, source)
    if index_by_key.contains(key) {
      raise MergeKey(key=key_path, index~, source~)
    }
    index_by_key[key] = result.length()
    result.push(item)
  }
  let overlay_keys : Set[String] = Set([])
  for index, item in overlay_items {
    let key = list_item_key({ ion: item }, key_name, key_path, index, source)
    if overlay_keys.contains(key) {
      raise MergeKey(key=key_path, index~, source~)
    }
    overlay_keys.add(key)
    match index_by_key.get(key) {
      Some(position) => {
        let merged = merge_at(
          { ion: result[position] },
          { ion: item },
          path,
          source_policy,
          key_policies,
          source,
          secret_syntax,
        )
        result[position] = merged.ion
      }
      None => {
        index_by_key[key] = result.length()
        result.push(item)
      }
    }
  }
  {
    ion: @ion.Ion::list(result).with_annotations(
      list_annotations(base, overlay),
    ),
  }
}

///|
/// The scalar text of the key field of a merge-by-key list item.
fn list_item_key(
  item : ConfigValue,
  key_name : String,
  list_path : KeyPath,
  index : Int,
  source : String,
) -> String raise ConfigError {
  guard item.ion.kind() is Struct(_) else {
    raise MergeKey(key=list_path, index~, source~)
  }
  guard item.field(key_name) is Some(field) else {
    raise MergeKey(key=list_path, index~, source~)
  }
  match field.ion.kind() {
    String(text) => text
    Symbol(token) =>
      match token.text() {
        Some(text) => text
        None => raise MergeKey(key=list_path, index~, source~)
      }
    Int(number) => number.to_string()
    Bool(flag) => flag.to_string()
    _ => raise MergeKey(key=list_path, index~, source~)
  }
}

///|
fn list_annotations(base : ConfigValue, overlay : ConfigValue) -> Array[@ion.SymbolToken] {
  if overlay.ion.has_annotations() {
    overlay.ion.annotations()
  } else {
    base.ion.annotations()
  }
}

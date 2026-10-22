///|
/// An immutable caller-supplied JSON resource. Its retrieval URI and aliases
/// are absolute and fragment-free; the value can be any extracted JSON fragment.
pub struct Resource {
  uri : UriReference
  value : @json.Value
  priv aliases : Array[UriReference]
  priv schema_roots : Array[JsonPointer]
  priv nodes : Int32
} derive(Debug)

///|
pub extend Resource with @debug.Debug::{to_repr}

///|
fn retrieval_name(
  uri : UriReference,
  role : String,
) -> Result[Unit, @json.Diagnostic] {
  if !uri.is_absolute() {
    return Err(
      @json.Diagnostic::new(
        @json.InvalidReference,
        role + " must be an absolute URI",
      ),
    )
  }
  if uri.fragment is Some(_) {
    return Err(
      @json.Diagnostic::new(
        @json.InvalidReference,
        role + " must not have a fragment",
      ),
    )
  }
  Ok(())
}

///|
/// Count value nodes iteratively, stopping once `budget` is exceeded.
fn node_count(value : @json.Value, budget : Int32) -> Int32? {
  let stack = [value]
  let mut count = 0
  while stack.pop() is Some(current) {
    count += 1
    if count > budget {
      return None
    }
    match current.kind() {
      Array(items) => stack.append(items)
      Object(fields) =>
        for field in fields {
          stack.push(field.1)
        }
      _ => ()
    }
  }
  Some(count)
}

///|
fn limit_error(message : String) -> @json.Diagnostic {
  @json.Diagnostic::new(@json.LimitExceeded, message)
}

///|
pub fn Resource::new(
  uri : UriReference,
  value : @json.Value,
  aliases~ : Array[UriReference] = [],
  schema_roots~ : Array[JsonPointer] = [],
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[Resource, @json.Diagnostic] {
  if aliases.length() > limits.max_nodes() - 1 ||
    schema_roots.length() > limits.max_nodes() - 1 {
    return Err(limit_error("Resource registration limit exceeded"))
  }
  if retrieval_name(uri, "Resource URI") is Err(d) {
    return Err(d)
  }
  for name in aliases {
    if retrieval_name(name, "Resource alias") is Err(d) {
      return Err(d)
    }
  }
  let nodes = match node_count(value, limits.max_nodes()) {
    Some(n) => n
    None => return Err(limit_error("Resource value node limit exceeded"))
  }
  for root in schema_roots {
    if root.resolve(value, limits~) is Err(d) {
      return Err(d)
    }
  }
  Ok({
    uri,
    value,
    aliases: aliases.copy(),
    schema_roots: schema_roots.copy(),
    nodes,
  })
}

///|
pub fn Resource::uri(self : Resource) -> UriReference {
  self.uri
}

///|
pub fn Resource::value(self : Resource) -> @json.Value {
  self.value
}

///|
pub fn Resource::aliases(self : Resource) -> Array[UriReference] {
  self.aliases.copy()
}

///|
/// Locations whose values are declared draft-07 schema roots.
pub fn Resource::schema_roots(self : Resource) -> Array[JsonPointer] {
  self.schema_roots.copy()
}

///|
/// Explicit immutable resource snapshots with an optional root base URI.
/// Lookup uses syntax-based URI identity and never retrieves anything.
pub struct ResourceSet {
  priv resources : Array[Resource]
  root_base : UriReference?
  priv index : Map[String, Int32]
} derive(Debug)

///|
pub extend ResourceSet with @debug.Debug::{to_repr}

///|
pub fn ResourceSet::empty() -> ResourceSet {
  { resources: [], root_base: None, index: Map([]), }
}

///|
pub fn ResourceSet::new(
  resources : Array[Resource],
  root_base~ : UriReference? = None,
  limits~ : @json.Limits = @json.Limits::new(),
) -> Result[ResourceSet, @json.Diagnostic] {
  let mut registrations = 0
  let mut nodes = 0
  for resource in resources {
    if resource.aliases.length() >= limits.max_nodes() - registrations {
      return Err(limit_error("Resource registration limit exceeded"))
    }
    registrations += resource.aliases.length() + 1
    if resource.nodes > limits.max_nodes() - nodes {
      return Err(limit_error("Resource set node limit exceeded"))
    }
    nodes += resource.nodes
  }
  let index : Map[String, Int32] = Map([])
  for i, resource in resources {
    for name in [resource.uri, ..resource.aliases] {
      let identity = name.identity()
      match index.get(identity) {
        Some(owner) if owner != i =>
          return Err(
            @json.Diagnostic::new(
              @json.ConflictingIdentifier,
              "Resource identity " +
              name.text() +
              " is already registered by " +
              resources[owner].uri.text(),
            ),
          )
        _ => index.set(identity, i)
      }
    }
  }
  Ok({ resources: resources.copy(), root_base, index, })
}

///|
pub fn ResourceSet::resources(self : ResourceSet) -> Array[Resource] {
  self.resources.copy()
}

///|
pub fn ResourceSet::root_base(self : ResourceSet) -> UriReference? {
  self.root_base
}

///|
/// The resource registered under the fragment-free identity of `uri`.
pub fn ResourceSet::get(self : ResourceSet, uri : UriReference) -> Resource? {
  match self.index.get(uri.without_fragment().identity()) {
    Some(i) => Some(self.resources[i])
    None => None
  }
}

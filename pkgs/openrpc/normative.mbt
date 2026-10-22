///|
/// A recorded disagreement between pinned prose and the pinned metaschema.
/// Only these normative errors become warnings under MetaschemaCompatibility.
pub(all) enum Discrepancy {
  OptionalParameterBeforeRequired
  ServerNameOmitted
  LicenseNameOmitted
} derive(Eq, Debug)

///|
pub extend Discrepancy with Eq::{equal, not_equal}

///|
pub extend Discrepancy with @debug.Debug::{to_repr}

///|
/// The frozen downgrade list. Adding an entry changes public behavior.
pub fn compatibility_discrepancies() -> Array[Discrepancy] {
  [OptionalParameterBeforeRequired, ServerNameOmitted, LicenseNameOmitted]
}

///|
/// 1.3.2 rules come from its prose; 1.4.x rules from its pinned schema, whose
/// generated prose marks no server, license or link name as required.
fn legacy(version : DocumentVersion) -> Bool {
  version.to_string() == "1.3.2"
}

///|
/// Fields defined by the version's pinned field tables. The model keeps the
/// union so that no present field is lost.
fn version_fields(version : DocumentVersion, kind : ObjectKind) -> Array[String] {
  let excluded = if legacy(version) {
    match kind {
      DocumentObject => ["$schema"]
      ComponentsObject => ["examplePairings"]
      _ => []
    }
  } else {
    match kind {
      TagObject => ["summary"]
      ExamplePairingObject => ["summary"]
      ExampleObject => ["externalValue"]
      ComponentsObject => ["examplePairingObjects"]
      _ => []
    }
  }
  field_names(kind).filter(name => !excluded.contains(name))
}

///|
fn Check::normative(
  self : Check,
  code : @exact.Code,
  message : String,
  site : Site,
  chain~ : Array[Site] = [],
  related~ : Array[Site] = [],
  expected~ : String? = None,
  discrepancy~ : Discrepancy? = None,
) -> Unit {
  let severity = if discrepancy is Some(_) &&
    self.profile == MetaschemaCompatibility {
    Warning
  } else {
    Error
  }
  add(
    self.findings,
    code,
    message,
    site.path,
    Normative,
    severity~,
    resource=site.resource,
    related~,
    chain~,
    expected~,
    discrepancy~,
  )
}

///|
/// Report members outside the version's field table once per location. They
/// are retained and never fail the normative facet.
fn Check::fields(
  self : Check,
  kind : ObjectKind,
  value : @exact.Value,
  owner : @reference.UriReference?,
  path : Array[String],
  chain~ : Array[Site] = [],
) -> Unit {
  if !self.checked.add_and_check("fields " + site_key(owner, path)) {
    return
  }
  guard value.kind() is @exact.Object(members) else { return }
  let known = version_fields(self.version, kind)
  for entry in members {
    if !known.contains(entry.0) && !entry.0.has_prefix("x-") {
      add(
        self.findings,
        @exact.UnknownField,
        "Field is not defined by OpenRPC " + self.version.to_string(),
        child(path, entry.0),
        Normative,
        severity=Warning,
        resource=owner,
        chain~,
      )
    }
  }
}

///|
fn Check::named(
  self : Check,
  name : String?,
  owner : @reference.UriReference?,
  path : Array[String],
  object_name : String,
  chain~ : Array[Site] = [],
  discrepancy~ : Discrepancy? = None,
) -> Unit {
  if legacy(self.version) && name is None {
    self.normative(
      @exact.MissingField,
      object_name + " name is required by OpenRPC 1.3.2",
      { resource: owner, path },
      chain~,
      expected=Some("name"),
      discrepancy~,
    )
  }
}

///|
fn Check::external_docs(
  self : Check,
  docs : ExternalDocumentation?,
  owner : @reference.UriReference?,
  path : Array[String],
  chain~ : Array[Site] = [],
) -> Unit {
  if docs is Some(docs) {
    self.fields(
      ExternalDocumentationObject,
      docs.value,
      owner,
      child(path, "externalDocs"),
      chain~,
    )
  }
}

///|
fn Check::server(
  self : Check,
  server : Server,
  owner : @reference.UriReference?,
  path : Array[String],
  chain~ : Array[Site] = [],
) -> Unit {
  self.fields(ServerObject, server.value, owner, path, chain~)
  self.named(
    server.name(),
    owner,
    path,
    "Server",
    chain~,
    discrepancy=Some(ServerNameOmitted),
  )
  for variable in server.variables().unwrap_or([]) {
    self.fields(
      ServerVariableObject,
      variable.1.value,
      owner,
      child(child(path, "variables"), variable.0),
      chain~,
    )
  }
}

///|
fn Check::servers(
  self : Check,
  servers : Array[Server]?,
  owner : @reference.UriReference?,
  path : Array[String],
  chain~ : Array[Site] = [],
) -> Unit {
  for i, server in servers.unwrap_or([]) {
    self.server(server, owner, child(path, i.to_string()), chain~)
  }
}

///|
/// Check a link's own rules; its target is checked once all methods are known.
fn Check::link(
  self : Check,
  link : Link,
  owner : @reference.UriReference?,
  path : Array[String],
  chain~ : Array[Site] = [],
) -> Unit {
  if self.checked.contains("fields " + site_key(owner, path)) {
    return
  }
  self.fields(LinkObject, link.value, owner, path, chain~)
  self.named(link.name(), owner, path, "Link", chain~)
  if link.server() is Some(server) {
    self.server(server, owner, child(path, "server"), chain~)
  }
  if link.target_method() is Some(target) {
    self.links.push((target.to_string(), { resource: owner, path: child(path, "method") }, chain))
  }
}

///|
fn Check::tag(
  self : Check,
  tag : Tag,
  owner : @reference.UriReference?,
  path : Array[String],
  chain~ : Array[Site] = [],
) -> Unit {
  self.fields(TagObject, tag.value, owner, path, chain~)
  self.external_docs(tag.external_docs(), owner, path, chain~)
}

///|
/// Methods are unique by name; parameters by name and errors by exact
/// integer code within one method; links name an existing method.
fn Check::uniqueness(
  self : Check,
  methods : Array[Resolved[Method]],
  errors : Array[Array[Resolved[ErrorObject]]],
  methods_complete~ : Bool,
) -> Unit {
  let names : Map[String, Array[Site]] = Map([])
  for method_ in methods {
    let site = Site::{
      resource: method_.owner,
      path: child(method_.path, "name"),
    }
    match names.get(method_.value.name.text) {
      Some(first) =>
        self.normative(
          @exact.DuplicateName,
          "Method names must be unique",
          site,
          chain=method_.chain,
          related=first,
        )
      None => names[method_.value.name.text] = [site, ..method_.chain]
    }
  }
  for method_errors in errors {
    let seen : Map[String, Array[Site]] = Map([])
    for error in method_errors {
      let site = Site::{ resource: error.owner, path: child(error.path, "code") }
      let key = error.value.code().number().numeric_key()
      match seen.get(key) {
        Some(first) =>
          self.normative(
            @exact.DuplicateErrorCode,
            "Error codes must be unique within a method",
            site,
            chain=error.chain,
            related=first,
          )
        None => seen[key] = [site, ..error.chain]
      }
    }
  }
  for link in self.links {
    if !names.contains(link.0) && !methods_complete {
      // An unresolved method could have this name.
      add(
        self.findings,
        @exact.UnsupportedCheck,
        "Link target not checked because a method did not resolve",
        link.1.path,
        Normative,
        severity=Information,
        resource=link.1.resource,
        chain=link.2,
      )
    } else if !names.contains(link.0) {
      self.normative(
        @exact.UnknownMethod,
        "Link method must name an existing method",
        link.1,
        chain=link.2,
      )
    }
  }
}

///|
/// OpenRPC 1.3.2 requires component keys to match `^[a-zA-Z0-9.\-_]+$`. The
/// 1.4 tables state no key grammar; its artifact pattern is checked there.
fn Check::component_keys(
  self : Check,
  components : Components,
  owner : @reference.UriReference?,
) -> Unit {
  guard legacy(self.version) else { return }
  let tables : Array[(String, Array[ComponentKey])] = [
    ("schemas", components.schemas().unwrap_or([]).map(e => e.0)),
    (
      "contentDescriptors",
      components.content_descriptors().unwrap_or([]).map(e => e.0),
    ),
    ("examples", components.examples().unwrap_or([]).map(e => e.0)),
    ("links", components.links().unwrap_or([]).map(e => e.0)),
    ("errors", components.errors().unwrap_or([]).map(e => e.0)),
    ("tags", components.tags().unwrap_or([]).map(e => e.0)),
    (
      "examplePairings",
      components.example_pairings().unwrap_or([]).map(e => e.0),
    ),
    (
      "examplePairingObjects",
      components.example_pairing_objects().unwrap_or([]).map(e => e.0),
    ),
  ]
  for table in tables {
    for key in table.1 {
      if !key.is_conforming() {
        self.normative(
          @exact.InvalidValue,
          "Component keys must match ^[a-zA-Z0-9.\\-_]+$",
          { resource: owner, path: ["components", table.0, key.to_string()] },
        )
      }
    }
  }
}

///|
/// The pinned 1.4 schema requires an example's `name` and inline `value`; its
/// generated tables drop the 1.3.2 `externalValue` alternative. The 1.3.2
/// prose requires neither.
fn Check::example(
  self : Check,
  value : @exact.Value,
  owner : @reference.UriReference?,
  path : Array[String],
  chain~ : Array[Site] = [],
) -> Unit {
  if self.checked.contains("fields " + site_key(owner, path)) {
    return
  }
  self.fields(ExampleObject, value, owner, path, chain~)
  guard !legacy(self.version) else { return }
  for field in ["name", "value"] {
    if value.get(field) is None {
      self.normative(
        @exact.MissingField,
        "Example " + field + " is required by OpenRPC 1.4",
        { resource: owner, path },
        chain~,
        expected=Some(field),
      )
    }
  }
}

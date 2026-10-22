///|
pub(all) enum ObjectKind {
  DocumentObject
  InfoObject
  ContactObject
  LicenseObject
  ExternalDocumentationObject
  ServerVariableObject
  ServerObject
  MethodObject
  ContentDescriptorObject
  TagObject
  ErrorObjectKind
  ExampleObject
  ExamplePairingObject
  LinkObject
  ComponentsObject
  ReferenceObject
} derive(Eq, Debug)

///|
pub fn field_names(kind : ObjectKind) -> Array[String] {
  match kind {
    DocumentObject =>
      [
        "$schema", "openrpc", "info", "methods", "servers", "components", "externalDocs",
      ]
    InfoObject =>
      [
        "title", "version", "description", "termsOfService", "contact", "license",
      ]
    ContactObject => ["name", "url", "email"]
    LicenseObject => ["name", "url"]
    ExternalDocumentationObject => ["url", "description"]
    ServerVariableObject => ["default", "enum", "description"]
    ServerObject => ["url", "name", "summary", "description", "variables"]
    MethodObject =>
      [
        "name", "tags", "summary", "description", "externalDocs", "params", "result",
        "deprecated", "servers", "errors", "links", "paramStructure", "examples",
      ]
    ContentDescriptorObject =>
      ["name", "summary", "description", "required", "schema", "deprecated"]
    TagObject => ["name", "summary", "description", "externalDocs"]
    ErrorObjectKind => ["code", "message", "data"]
    ExampleObject =>
      ["name", "summary", "description", "value", "externalValue"]
    ExamplePairingObject =>
      ["name", "summary", "description", "params", "result"]
    LinkObject =>
      ["name", "summary", "description", "method", "params", "server"]
    ComponentsObject =>
      [
        "schemas", "contentDescriptors", "examples", "links", "errors", "tags", "examplePairings",
        "examplePairingObjects",
      ]
    ReferenceObject => ["$ref"]
  }
}

///|
pub extend ObjectKind with Eq::{equal, not_equal}

///|
pub extend ObjectKind with @debug.Debug::{to_repr}

///|
pub fn object_kinds() -> Array[ObjectKind] {
  [
    DocumentObject,
    InfoObject,
    ContactObject,
    LicenseObject,
    ExternalDocumentationObject,
    ServerVariableObject,
    ServerObject,
    MethodObject,
    ContentDescriptorObject,
    TagObject,
    ErrorObjectKind,
    ExampleObject,
    ExamplePairingObject,
    LinkObject,
    ComponentsObject,
    ReferenceObject,
  ]
}

///|
pub fn ObjectKind::name(self : ObjectKind) -> String {
  match self {
    DocumentObject => "openrpcDocument"
    InfoObject => "infoObject"
    ContactObject => "contactObject"
    LicenseObject => "licenseObject"
    ExternalDocumentationObject => "externalDocumentationObject"
    ServerVariableObject => "serverVariableObject"
    ServerObject => "serverObject"
    MethodObject => "methodObject"
    ContentDescriptorObject => "contentDescriptorObject"
    TagObject => "tagObject"
    ErrorObjectKind => "errorObject"
    ExampleObject => "exampleObject"
    ExamplePairingObject => "examplePairingObject"
    LinkObject => "linkObject"
    ComponentsObject => "components"
    ReferenceObject => "referenceObject"
  }
}

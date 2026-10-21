///|
/// Whether the load and the merge treat one-field `env` / `file` / `command` /
/// `keyring` structs as secret references.
pub(all) enum SecretSyntax {
  Standard
  None
} derive(Eq, Debug)

///|
pub extend SecretSyntax with Eq::{equal, not_equal}

///|
pub extend SecretSyntax with @debug.Debug::{to_repr}

///|
/// The Morphir secret-reference shapes. Recognition is on when the syntax is
/// `Standard`.
pub fn SecretSyntax::standard() -> SecretSyntax {
  Standard
}

///|
/// Turn secret-reference recognition off.
pub fn SecretSyntax::none() -> SecretSyntax {
  None
}

///|
/// A secret reference leaf: one of the Morphir shapes.
pub(all) enum SecretRef {
  Env(String)
  File(String)
  Command(Array[String])
  Keyring(service~ : String, account~ : String)
} derive(Eq, Debug)

///|
pub extend SecretRef with Eq::{equal, not_equal}

///|
pub extend SecretRef with @debug.Debug::{to_repr}

///|
/// An opaque resolved secret. `Show` writes `<redacted>`.
pub struct Secret {
  priv text : String
}

///|
/// The secret text. Callers that display a value must not use this.
pub fn Secret::expose(self : Secret) -> String {
  self.text
}

///|
pub impl Show for Secret with output(_self, logger) {
  logger.write_string("<redacted>")
}

///|
pub extend Secret with Show::{output, to_string}

///|
/// A failure while resolving a secret. Messages never hold the secret or the
/// backend output.
pub(all) suberror SecretError {
  MissingConfigKey(key~ : KeyPath)
  EmptyEnvironment(variable~ : String)
  FileRead(path~ : String, reason~ : String)
  InvalidSecretValue(reason~ : String)
  CommandFailed(reason~ : String)
  KeyringLookupFailed(reason~ : String)
} derive(Eq, Debug)

///|
pub extend SecretError with Eq::{equal, not_equal}

///|
pub extend SecretError with @debug.Debug::{to_repr}

///|
/// Text for people that names the failure class and never holds a secret.
pub fn SecretError::message(self : SecretError) -> String {
  match self {
    MissingConfigKey(key~) => "missing-config-key: configuration key \{key} is missing"
    EmptyEnvironment(variable~) =>
      "empty-environment: environment variable \{variable} is empty or unset"
    FileRead(path~, reason~) => "file-read: cannot read \{path}: \{reason}"
    InvalidSecretValue(reason~) => "invalid-secret-value: \{reason}"
    CommandFailed(reason~) => "command-failed: \{reason}"
    KeyringLookupFailed(reason~) => "keyring-lookup-failed: \{reason}"
  }
}

///|
/// Resolves a secret reference. The origin lets a file resolver anchor a
/// relative path to the directory of the declaring file.
pub(open) trait SecretResolver {
  resolve(Self, SecretRef, Origin) -> Secret raise SecretError
}

///|
/// A resolver over an explicit variable map. It resolves only `Env` references.
pub struct EnvResolver {
  priv vars : Map[String, String]
}

///|
/// A resolver over `vars`. File, command, and keyring references raise
/// `InvalidSecretValue`.
pub fn env_resolver(vars : Map[String, String]) -> EnvResolver {
  { vars: vars.copy() }
}

///|
pub impl SecretResolver for EnvResolver with resolve(self, reference, _origin) {
  match reference {
    Env(variable) => {
      guard self.vars.get(variable) is Some(text) && !text.is_empty() else {
        raise EmptyEnvironment(variable~)
      }
      { text, }
    }
    File(_) => raise InvalidSecretValue(reason="env_resolver does not read files")
    Command(_) =>
      raise InvalidSecretValue(reason="env_resolver does not run commands")
    Keyring(..) =>
      raise InvalidSecretValue(reason="env_resolver does not look up keyrings")
  }
}

///|
pub extend EnvResolver with SecretResolver::{resolve}

///|
/// Whether `value` is a secret-reference shape under `syntax`.
fn is_secret_reference(value : ConfigValue, syntax : SecretSyntax) -> Bool {
  match syntax {
    None => false
    Standard => secret_ref_of(value) is Some(_)
  }
}

///|
/// Parse a secret reference from `value`, or `None` when it is not one.
fn secret_ref_of(value : ConfigValue) -> SecretRef? {
  guard value.ion.kind() is Struct(fields) && fields.length() == 1 else {
    return None
  }
  let field = fields[0]
  guard field.name().text() is Some(name) else { return None }
  match name {
    "env" =>
      match field.value().kind() {
        String(text) if !text.is_empty() => Some(Env(text))
        _ => None
      }
    "file" =>
      match field.value().kind() {
        String(text) if !text.is_empty() => Some(File(text))
        _ => None
      }
    "command" => parse_command_ref(field.value())
    "keyring" => parse_keyring_ref(field.value())
    _ => None
  }
}

///|
fn parse_command_ref(value : @ion.Ion) -> SecretRef? {
  guard value.kind() is List(items) && !items.is_empty() else { return None }
  let parts = []
  for item in items {
    guard item.kind() is String(text) else { return None }
    parts.push(text)
  }
  guard !parts[0].is_empty() else { return None }
  Some(Command(parts))
}

///|
fn parse_keyring_ref(value : @ion.Ion) -> SecretRef? {
  guard value.kind() is Struct(fields) && fields.length() == 2 else {
    return None
  }
  let mut service : String? = None
  let mut account : String? = None
  for field in fields {
    guard field.name().text() is Some(name) else { return None }
    guard field.value().kind() is String(text) && !text.is_empty() else {
      return None
    }
    match name {
      "service" => service = Some(text)
      "account" => account = Some(text)
      _ => return None
    }
  }
  match (service, account) {
    (Some(service), Some(account)) => Some(Keyring(service~, account~))
    _ => None
  }
}

///|
/// Raise `InvalidSecret` when `value` is a one-field secret-reference shape
/// with a wrong payload. A nested table whose only field is named `env`,
/// `file`, `command`, or `keyring` and whose value is itself a struct is not a
/// reference: it is an ordinary table, and the walk continues.
fn check_secret_payloads(
  value : ConfigValue,
  origin : String,
  syntax : SecretSyntax,
  path~ : Array[String] = [],
) -> Unit raise ConfigError {
  guard syntax is Standard else { return }
  match value.ion.kind() {
    Struct(fields) => {
      if fields.length() == 1 {
        if fields[0].name().text() is Some(name) && is_secret_field(name) {
          let payload = fields[0].value()
          let nested_table = payload.kind() is Struct(_) && name != "keyring"
          if !nested_table {
            guard secret_ref_of(value) is Some(_) else {
              let key = if path.is_empty() {
                KeyPath::{ names: ["(root)"] }
              } else {
                { names: path.copy() }
              }
              raise InvalidSecret(
                key~,
                origin~,
                reason="the \{name} payload has the wrong shape",
              )
            }
            return
          }
        }
      }
      for field in fields {
        guard field.name().text() is Some(name) else { continue }
        check_secret_payloads(
          { ion: field.value() },
          origin,
          syntax,
          path=[..path, name],
        )
      }
    }
    List(items) | Sexp(items) =>
      for item in items {
        check_secret_payloads({ ion: item }, origin, syntax, path~)
      }
    _ => ()
  }
}

///|
fn is_secret_field(name : String) -> Bool {
  name == "env" || name == "file" || name == "command" || name == "keyring"
}

///|
/// A configuration with the given tree and provenance, for origins that no
/// source can give yet: environment variables and appended lists.
fn with_provenance(
  json : Json,
  records : Array[(String, Array[Origin])],
) -> Config {
  let provenance : Map[KeyPath, Array[Origin]] = Map([])
  for record in records {
    provenance[KeyPath::parse(record.0) catch { _ => abort("bad key") }] = record.1
  }
  {
    root: ConfigValue::from_json(json) catch { _ => abort("bad tree") },
    reports: [],
    notes: [],
    provenance,
    secret_syntax: Standard,
    profiles: Off,
  }
}

///|
fn bind_message(run : () -> Unit raise ConfigError) -> String {
  try run() catch {
    error => error.message()
  } noraise {
    _ => abort("expected an error")
  }
}

///|
let env_origin : Origin = {
  kind: Environment,
  source: "environment",
  priority: 600,
  location: Some("MORPHIR_IR__STRICT_MODE"),
}

///|
test "Value from an environment variable" {
  let config = with_provenance({ "ir": { "strict_mode": "maybe" } }, [
    ("ir.strict_mode", [env_origin]),
  ])
  let message = bind_message(() => {
    let _ : Bool = bind(config, "ir.strict_mode")
  })
  assert_eq(message, "ir.strict_mode: Bool::from_json: expected boolean (set in environment MORPHIR_IR__STRICT_MODE)")
}

///|
test "Appended list names every source" {
  let a : Origin = {
    kind: File(Workspace),
    source: "a",
    priority: 300,
    location: Some("/repo/a.toml"),
  }
  let b : Origin = { ..a, source: "b", location: Some("/repo/b.toml") }
  let config = with_provenance({ "targets": [1, "x"] }, [("targets", [a, b])])
  let error = try {
    let _ : Array[Int] = bind(config, "targets")
    abort("expected an error")
  } catch {
    error => error
  }
  guard error is Decode(failure~) else { fail("expected a decode error") }
  assert_eq(failure.at[0].blame, Set([a, b]))
  assert_eq(error.message(), "targets[1]: Int::from_json: expected number (set in project /repo/a.toml, project /repo/b.toml)")
}

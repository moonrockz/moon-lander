///|
struct ServiceOptions {
  url : String
  token : String
} derive(FromJson, ToJson, Debug, Eq)

///|
struct ApiOptions {
  api_token : String
} derive(FromJson, ToJson, Debug, Eq)

///|
/// A resolver that counts its calls. Binding must never call it.
struct CountingResolver {
  calls : Ref[Int]
}

///|
impl @config.SecretResolver for CountingResolver with resolve(
  self,
  _reference,
  _origin,
) {
  self.calls.val += 1
  raise EmptyEnvironment(variable="SERVICE_TOKEN")
}

///|
fn service_config() -> @config.Config raise @config.ConfigError {
  load_files([
    (
      "/repo/acme.toml",
      Workspace,
      (
        #|service.url = "https://example.org"
        #|service.token = { env = "SERVICE_TOKEN" }
      ),
    ),
  ])
}

///|
test "Secret reference into a text field" {
  let resolver : CountingResolver = { calls: { val: 0 } }
  let config = service_config()
  let (failure, text) = decode_failure(() => {
    let _ : ServiceOptions = config |> @config.bind("service")
  })
  @expect.expect(failure.at.map(at => at.path.to_string())).to_equal([
    "service.token",
  ])
  @expect.expect(text).to_equal(
    "service.token: is a secret reference; bind it as SecretRef with bind_with (set in project /repo/acme.toml)",
  )
  @expect.expect(resolver.calls.val).to_equal(0)
  // The stub counts a real resolution, so the zero above means no call.
  try config.secret("service.token", resolver) |> ignore catch {
    _ => ()
  }
  @expect.expect(resolver.calls.val).to_equal(1)
}

///|
test "a secret reference fails bind_or before the merge and bind_root" {
  let config = service_config()
  let (failure, _) = decode_failure(() => {
    let default : ServiceOptions = { url: "http://localhost", token: "" }
    config |> @config.bind_or("service", default) |> ignore
  })
  @expect.expect(failure.at.map(at => at.path.to_string())).to_equal([
    "service.token",
  ])
  let (root, _) = decode_failure(() => {
    let _ : Map[String, ServiceOptions] = config |> @config.bind_root()
  })
  @expect.expect(root.detail).to_equal(
    "is a secret reference; bind it as SecretRef with bind_with",
  )
}

///|
test "a secret reference names the binding target itself" {
  let config = service_config()
  let (failure, _) = decode_failure(() => {
    let _ : String = config |> @config.bind("service.token")
  })
  @expect.expect(failure.at.map(at => at.path.to_string())).to_equal([
    "service.token",
  ])
}

///|
test "a secret reference inside a list names its index" {
  let config = load_files([
    (
      "/repo/acme.toml",
      Workspace,
      "tokens = [\"plain\", { env = \"SERVICE_TOKEN\" }]",
    ),
  ])
  let (failure, _) = decode_failure(() => {
    let _ : Array[String] = config |> @config.bind("tokens")
  })
  @expect.expect(failure.at.map(at => at.path.to_string())).to_equal([
    "tokens[1]",
  ])
}

///|
test "a section without a secret reference still binds" {
  let config = service_config()
  let url : String = config |> @config.bind("service.url")
  @expect.expect(url).to_equal("https://example.org")
}

///|
test "with secret syntax off, a reference shape is an ordinary table" {
  let builder = @config.builder()
    |> @config.format(@toml.format())
    |> @config.secret_syntax(@config.SecretSyntax::none())
    |> @config.file("/repo/acme.toml")
  let tree = @config.FileTree::new(complete=true).with_file(p("/repo/acme.toml"), "service.token = { env = \"SERVICE_TOKEN\" }",
  )
  guard @config.load(builder, tree) is Done(config) else {
    abort("a complete tree never asks for files")
  }
  let token : Map[String, String] = config |> @config.bind("service.token")
  @expect.expect(token).to_equal({ "env": "SERVICE_TOKEN" })
}

///|
test "the text of each binding error does not show the configured value" {
  let config = load_files([
    ("/repo/acme.toml", Workspace, "service.api_token = 42"),
  ])
  let texts = []
  let keep = (run : () -> Unit raise @config.ConfigError) => {
    try run() catch {
      error => texts.push(error.message())
    } noraise {
      _ => abort("expected a binding error")
    }
  }
  keep(() => {
    let _ : ApiOptions = config |> @config.bind("service")
  })
  keep(() => {
    let _ : String = config |> @config.bind("service.api_token")
  })
  keep(() => {
    let _ : Map[String, ApiOptions] = config |> @config.bind_root()
  })
  keep(() => {
    config
    |> @config.bind_or("service", ({ api_token: "none" } : ApiOptions))
    |> ignore
  })
  keep(() => {
    let value : ApiOptions = { api_token: "x" }
    value |> @config.validated(config, "service") |> ignore
  })
  @expect.expect(texts.length()).to_equal(5)
  for text in texts {
    @expect.expect(text.contains("service.api_token")).to_be_true()
    @expect.expect(text.contains("/repo/acme.toml")).to_be_true()
    @expect.expect(text.contains("42")).to_be_false()
  }
}

///|
/// A rule that always breaks, so the safe-text test gets a validation error.
impl @config.Validate for ApiOptions with validate(_) {
  [@config.violation(["api_token"], "must be text")]
}

///|
struct SpyResolver {
  calls : Ref[Array[(@config.SecretRef, @config.Origin)]]
  inner : @config.EnvResolver
}

///|
fn SpyResolver::SpyResolver(vars : Map[String, String]) -> SpyResolver {
  { calls: Ref([]), inner: @config.env_resolver(vars) }
}

///|
impl @config.SecretResolver for SpyResolver with resolve(self, reference, origin) {
  self.calls.val.push((reference, origin))
  self.inner.resolve(reference, origin)
}

///|
struct FileSpy {
  calls : Ref[Array[(@config.SecretRef, @config.Origin)]]
}

///|
fn FileSpy::FileSpy() -> FileSpy {
  { calls: Ref([]) }
}

///|
impl @config.SecretResolver for FileSpy with resolve(self, reference, origin) {
  self.calls.val.push((reference, origin))
  raise @config.InvalidSecretValue(reason="file spy does not read")
}

///|
test "Two secret references do not merge" {
  let config = @config.build([
    named({ "credentials": { "key": { "env": "FIRST" } } }, "base"),
    named({ "credentials": { "key": { "file": "secret" } } }, "overlay"),
  ])
  @expect.expect(config.get(key("credentials.key"))).to_equal(
    Some(
      @config.ConfigValue::from_json({ "file": "secret" }) catch {
        error => abort(error.message())
      },
    ),
  )
  @expect.expect(config.get(key("credentials.key.env"))).to_equal(None)
}

///|
test "Invalid reference payload" {
  try
    @config.build([
      named({ "registry": { "token": { "command": 5 } } }, "app.toml"),
    ])
  catch {
    error => {
      guard error is InvalidSecret(key~, origin~, ..) else {
        fail("wrong error")
      }
      @expect.expect(key.to_string()).to_equal("registry.token")
      @expect.expect(origin).to_equal("app.toml")
    }
  } noraise {
    _ => fail("expected InvalidSecret")
  }
}

///|
test "Load does not resolve" {
  let spy = SpyResolver::SpyResolver({ "TOKEN": "abc" })
  let config = @config.build([
    named({ "registry": { "token": { "env": "TOKEN" } } }, "base"),
  ])
  @expect.expect(config.get(key("registry.token")) is None).to_be_false()
  @expect.expect(spy.calls.val.length()).to_equal(0)
  let secret = config.secret("registry.token", spy)
  @expect.expect(secret.expose()).to_equal("abc")
  @expect.expect(secret.to_string()).to_equal("<redacted>")
  @expect.expect(spy.calls.val.length()).to_equal(1)
}

///|
test "Resolve an environment reference" {
  let config = @config.build([
    named({ "registry": { "token": { "env": "TOKEN" } } }, "base"),
  ])
  let secret = config.secret(
    "registry.token",
    @config.env_resolver({ "TOKEN": "abc" }),
  )
  @expect.expect(secret.expose()).to_equal("abc")
  @expect.expect(secret.to_string()).to_equal("<redacted>")
}

///|
test "Plain string is a literal secret" {
  let spy = SpyResolver::SpyResolver({ "TOKEN": "abc" })
  let config = @config.build([
    named({ "registry": { "token": "abc" } }, "base"),
  ])
  let secret = config.secret("registry.token", spy)
  @expect.expect(secret.expose()).to_equal("abc")
  @expect.expect(spy.calls.val.length()).to_equal(0)
}

///|
test "Resolution failure classes" {
  let config = @config.build([
    named({ "registry": { "token": { "env": "TOKEN" } } }, "base"),
  ])
  try config.secret("missing", @config.env_resolver({})) catch {
    error =>
      @expect.expect(error.message().has_prefix("missing-config-key")).to_equal(
        true,
      )
  } noraise {
    _ => fail("expected MissingConfigKey")
  }
  try config.secret("registry.token", @config.env_resolver({})) catch {
    error =>
      @expect.expect(error.message().has_prefix("empty-environment")).to_equal(
        true,
      )
  } noraise {
    _ => fail("expected EmptyEnvironment")
  }
  let messages = [
    (@config.FileRead(path="x", reason="no") : @config.SecretError).message(),
    (@config.InvalidSecretValue(reason="bad") : @config.SecretError).message(),
    (@config.CommandFailed(reason="exit 1") : @config.SecretError).message(),
    (@config.KeyringLookupFailed(reason="missing") : @config.SecretError).message(),
  ]
  @expect.expect(messages[0].has_prefix("file-read")).to_equal(true)
  @expect.expect(messages[1].has_prefix("invalid-secret-value")).to_equal(true)
  @expect.expect(messages[2].has_prefix("command-failed")).to_equal(true)
  @expect.expect(messages[3].has_prefix("keyring-lookup-failed")).to_equal(true)
  for message in messages {
    @expect.expect(message.contains("secret-value-here")).to_be_false()
  }
}

///|
test "Resolver gets the origin" {
  let value = @config.ConfigValue::from_json({ "token": { "file": "s.txt" } })
  let config = @config.build([
    @config.ConfigSource::parsed_file("/w/app.toml", value),
  ])
  let file_spy = FileSpy::FileSpy()
  try config.secret("token", file_spy) catch {
    @config.InvalidSecretValue(..) => ()
    other => fail("unexpected \{other.message()}")
  } noraise {
    _ => ()
  }
  @expect.expect(file_spy.calls.val.length()).to_equal(1)
  let (reference, origin) = file_spy.calls.val[0]
  @expect.expect(reference).to_equal(@config.File("s.txt"))
  @expect.expect(origin.location).to_equal(Some("/w/app.toml"))
}

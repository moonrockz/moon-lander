///|
fn rejected_policy(run : () -> Unit raise @config.ConfigError) -> @config.ConventionRule raise {
  try run() catch {
    @config.ConventionPolicy(rule~, ..) => rule
    error => raise error
  } noraise { _ => fail("invalid policy accepted") }
}

///|
test "extension parsing accepts boundary characters and rejects empty or path syntax" {
  for text in ["a", "Z", "0", "_", "-", "json5", "yml"] {
    assert_eq(@conventions.Extension::parse(text).to_string(), text)
  }
  assert_eq(rejected_policy(() => ignore(@conventions.Extension::parse(""))), @config.ConventionRule::EmptyExtension)
  for text in [".", "/", "\\", "a b", "é", "a\u{0}"] {
    assert_eq(rejected_policy(() => ignore(@conventions.Extension::parse(text))), @config.ConventionRule::ExtensionCharacters)
  }
}

///|
test "format groups and order reject empty or repeated assignments and copy inputs" {
  let toml = @conventions.Extension::parse("toml")
  let extensions = [toml]
  let group = @conventions.FormatGroup::new(extensions)
  extensions.clear()
  assert_eq(group.extensions(), [toml])
  let copy = group.extensions()
  copy.clear()
  assert_eq(group.extensions(), [toml])
  assert_eq(rejected_policy(() => ignore(@conventions.FormatGroup::new([]))), @config.ConventionRule::EmptyFormatGroup)
  assert_eq(rejected_policy(() => ignore(@conventions.FormatGroup::new([toml, toml]))), @config.ConventionRule::DuplicateExtension)
  assert_eq(rejected_policy(() => ignore(@conventions.FormatLayers::new([]))), @config.ConventionRule::EmptyFormatOrder)
  assert_eq(rejected_policy(() => ignore(@conventions.FormatLayers::new([group, group]))), @config.ConventionRule::DuplicateExtension)
}

///|
test "supplemental sources require a matching confined name and group extension" {
  let json = @conventions.Extension::parse("json")
  let toml = @conventions.Extension::parse("toml")
  let file = @conventions.SupplementalFile::new("acme-workspace.json", json)
  assert_eq(file.name(), "acme-workspace.json")
  ignore(@conventions.FormatGroup::new([json], supplemental=file))
  assert_eq(rejected_policy(() => ignore(@conventions.FormatGroup::new([toml], supplemental=file))), @config.ConventionRule::SupplementalOutsideGroup)
  assert_eq(rejected_policy(() => ignore(@conventions.SupplementalFile::new("acme.yaml", json))), @config.ConventionRule::SupplementalExtension)
  for name in ["", ".", "..", "/x.json", "dir/x.json", "x\\y.json", "x\u{0}.json"] {
    assert_eq(rejected_policy(() => ignore(@conventions.SupplementalFile::new(name, json))), @config.ConventionRule::SupplementalName)
  }
}

///|
test "unregistered ordered extensions fail before requesting file-tree data" {
  let layers = @conventions.FormatLayers::new([@conventions.FormatGroup::new([@conventions.Extension::parse("json")])])
  let conventions = @conventions.app_dirs("acme") |> @conventions.format_layers(layers)
  let context : @config.LoadContext = { tree: @config.FileTree::new(), working_dir: Some(p("/w")), platform: Some(Linux), env_vars: Map([]), formats: [@toml.format()] }
  assert_eq(rejected_policy(() => ignore(conventions.roots(context))), @config.ConventionRule::UnregisteredExtension)
  let builder = @config.builder() |> @config.working_dir("/w") |> @config.format(@toml.format()) |> @conventions.add(conventions)
  assert_eq(rejected_policy(() => ignore(@config.load(builder, context.tree))), @config.ConventionRule::UnregisteredExtension)
}

///|
test "a supplemental source cannot alias an enabled ordinary primary" {
  let extension = @conventions.Extension::parse("json")
  let supplemental = @conventions.SupplementalFile::new("acme.json", extension)
  let layers = @conventions.FormatLayers::new([@conventions.FormatGroup::new([extension], supplemental~)])
  let conventions = @conventions.app_dirs("acme") |> @conventions.format_layers(layers)
  let context : @config.LoadContext = { tree: @config.FileTree::new(), working_dir: Some(p("/w")), platform: Some(Linux), env_vars: Map([]), formats: [@json5.format()] }
  assert_eq(rejected_policy(() => ignore(conventions.roots(context))), @config.ConventionRule::SupplementalPrimaryCollision)
  let distinct = @conventions.SupplementalFile::new("acme-workspace.json", extension)
  let layers = @conventions.FormatLayers::new([@conventions.FormatGroup::new([extension], supplemental=distinct)])
  guard (@conventions.app_dirs("acme") |> @conventions.format_layers(layers)).roots(context) is Need(_) else { fail("a distinct supplemental source must remain valid") }
}

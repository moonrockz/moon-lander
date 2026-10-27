///|
fn[S] injected_run(host : Host[S]) -> ConfiguredRun[S] raise {
  let inputs = configuration_inputs(host)
  finish_configuration(host, inputs, configuration_from_tree(inputs.sources, host.file_tree))
}

///|
test "configure convention pipeline loads files and variables win on every target" {
  let vars = { "ACME_LOG__FORMAT": "json", "HOME": "/home/test" }
  let tree = @config.FileTree::new(complete=true)
    .with_listing(p("/w"), [{ name: "acme.toml", kind: File }])
    .with_file(p("/w/acme.toml"), "log.format = \"text\"\nfile_only = true")
  let host = builder(@lander_core.AppName::parse("acme"), [], env_vars=vars,
      working_dir=@lander_core.AbsolutePath::parse("/w"))
    |> configure(sources => sources |> @config.platform(Linux) |> @config.format(@toml.format())
      |> @conventions.add(@conventions.app_dirs("acme")))
    |> files(tree)
    |> build(b => {
      assert_eq(b.env_vars.get("HOME"), Some("/home/test"))
      assert_eq(b.working_dir.to_string(), "/w")
      @config.get_text(b.config, "log.format")
    })
  let loaded = injected_run(host)
  assert_eq(loaded.context.services, "json")
  assert_eq(loaded.context.config.value(), @config.ConfigValue::from_json({ "log": { "format": "json" }, "file_only": true }))
  assert_true(loaded.context.config.reports().iter().any(r => r.path == Some("/w/acme.toml") && r.status is Loaded))
  assert_true(loaded.context.config.reports().iter().any(r => r.priority == 600 && r.kind is Environment))
  // JSON and map settings give identical results and reports through shared loading.
  let equivalent = builder(host.name, [], env_vars=({ "ACME_LOG__FORMAT": "json", "HOME": "/home/test" } : Json),
      working_dir=@lander_core.AbsolutePath::parse("/w"))
    |> configure(s => s |> @config.platform(Linux) |> @config.format(@toml.format()))
    |> app_dirs() |> files(tree) |> build(_ => ()) |> injected_run
  assert_eq(loaded.context.config.value(), equivalent.context.config.value())
  assert_eq(loaded.context.config.reports(), equivalent.context.config.reports())
}

///|
test "incomplete tree names every requested path and has usage code 2 before factory" {
  let calls = Ref(0)
  let host = builder(@lander_core.AppName::parse("acme"), [], env_vars=(Map([]) : Map[String, String]),
      working_dir=@lander_core.AbsolutePath::parse("/w"))
    |> configure(s => s |> @config.format(@toml.format()) |> @config.file("/w/a.toml") |> @config.file("/w/b.toml"))
    |> files(@config.FileTree::new()) |> build(_ => { calls.val += 1 })
  try { ignore(injected_run(host)); fail("expected incomplete tree") } catch {
    IncompleteFileTree(requests~) as error => {
      assert_eq(requests, [@config.ReadFile(p("/w/a.toml")), @config.ReadFile(p("/w/b.toml"))])
      assert_eq(report_text(host.name, error), "acme: Incomplete configuration file tree; requested paths: /w/a.toml, /w/b.toml")
      assert_eq(outcome(error).exit_code().to_int(), 2)
    }
    error => raise error
  }
  assert_eq(calls.val, 0)
}

///|
test "incomplete app_dirs tree names the unlisted start directory before factory" {
  let calls = Ref(0)
  let host = builder(@lander_core.AppName::parse("acme"), [], env_vars=(Map([]) : Map[String, String]),
      working_dir=@lander_core.AbsolutePath::parse("/w"))
    |> configure(s => s |> @config.platform(Linux) |> @config.format(@toml.format()))
    |> app_dirs() |> files(@config.FileTree::new()) |> build(_ => { calls.val += 1 })
  try { ignore(injected_run(host)); fail("expected incomplete tree") } catch {
    IncompleteFileTree(requests~) as error => {
      assert_true(requests.contains(@config.ListDir(p("/w"))))
      assert_true(report_text(host.name, error).contains("/w"))
      assert_eq(outcome(error).exit_code().to_int(), 2)
    }
    error => raise error
  }
  assert_eq(calls.val, 0)
}

///|
test "configure file at 300 before host-owned conventions fails with SourceOrder" {
  let calls = Ref(0)
  let host = builder(@lander_core.AppName::parse("acme"), [], env_vars=(Map([]) : Map[String, String]),
      working_dir=@lander_core.AbsolutePath::parse("/w"))
    |> configure(s => s |> @config.platform(Linux) |> @config.format(@toml.format())
      |> @config.file("/w/extra.toml"))
    |> app_dirs() |> files(@config.FileTree::new(complete=true).with_file(p("/w/extra.toml"), ""))
    |> build(_ => { calls.val += 1 })
  try { ignore(injected_run(host)); fail("expected source order failure") } catch {
    @config.SourceOrder(previous~, previous_priority~, priority~, ..) as error => {
      assert_eq(previous, "/w/extra.toml")
      assert_eq(previous_priority, 300)
      assert_eq(priority, 100)
      assert_eq(outcome(error).exit_code().to_int(), 2)
    }
    error => raise error
  }
  assert_eq(calls.val, 0)
}

///|
test "configured sources compose in order and final services use a source above 600" {
  let calls = Ref(0)
  let first = builder(@lander_core.AppName::parse("acme"), [], env_vars={ "ACME_LOG__FORMAT": "yaml" },
      working_dir=@lander_core.AbsolutePath::root())
    |> configure(s => s |> @config.defaults({ "log": { "format": "text" } }))
  let host = first |> build(b => { calls.val += 1; @config.get_text(b.config, "log.format") })
  let inputs = configuration_inputs(host)
  // Group 14 adds the public overrides mapping. Append a test source after
  // the host-owned 600 layer to verify the shared factory boundary now.
  let sources = inputs.sources |> @config.add(@config.in_memory_pairs([("log.format", @config.string("json"))], priority=650))
  let loaded = finish_configuration(host, inputs, configuration_from_tree(sources, host.file_tree))
  assert_eq(calls.val, 1)
  assert_eq(loaded.context.services, "json")
  assert_eq(@config.get_text(first |> build(_ => "") |> injected_run |> (r => r.context.config), "log.format"), "yaml")
}

///|
test "shutdown key decodes exact time limits and falls back to builder or default" {
  for (value, expected) in [(Some("100ms"), 100), (None, 30000)] {
    let host = builder(@lander_core.AppName::parse("acme"), [], env_vars=(Map([]) : Map[String, String]),
        working_dir=@lander_core.AbsolutePath::root())
      |> configure(s => match value { Some(text) => s |> @config.defaults({ "app": { "shutdown_timeout": text } }); None => s })
      |> shutdown_timeout_key(@config.KeyPath::parse("app.shutdown_timeout")) |> build(_ => ())
    assert_eq(injected_run(host).shutdown_timeout.to_millis(), expected)
    let overridden = { ..host, shutdown_timeout: @lander_core.TimeLimit::seconds(5) }
    assert_eq(injected_run(overridden).shutdown_timeout.to_millis(), if value is Some(_) { expected } else { 5000 })
  }
}

///|
test "numeric and invalid text timeout values fail before factory" {
  for value in ([100, "0s", "-1s", "1day"] : Array[Json]) {
    let calls = Ref(0)
    let host = builder(@lander_core.AppName::parse("acme"), [], env_vars=(Map([]) : Map[String, String]),
        working_dir=@lander_core.AbsolutePath::root())
      |> configure(s => s |> @config.defaults({ "app": { "shutdown_timeout": value } }))
      |> shutdown_timeout_key(@config.KeyPath::parse("app.shutdown_timeout"))
      |> build(_ => calls.val += 1)
    try { ignore(injected_run(host)); fail("expected invalid time limit: " + value.stringify()) } catch {
      @config.Decode(_) as error => assert_eq(outcome(error).exit_code().to_int(), 2)
      error => raise error
    }
    assert_eq(calls.val, 0)
  }
}

///|
test "host-owned conventions compose in pipeline order and app_dirs replaces earlier parts" {
  let first = builder(@lander_core.AppName::parse("acme"), [], env_vars=(Map([]) : Map[String, String]),
      working_dir=@lander_core.AbsolutePath::parse("/w"))
    |> configure(s => s |> @config.platform(Linux) |> @config.format(@toml.format()))
    |> conventions(c => c |> @conventions.system_dir())
    |> files(@config.FileTree::new(complete=true))
  let config = first |> build(_ => ()) |> injected_run
  assert_true(config.context.config.reports().iter().any(r => r.kind is File(System)))
  assert_false(config.context.config.reports().iter().any(r => r.kind is File(Workspace) && !r.candidates.is_empty()))
  let replaced = first |> app_dirs() |> conventions(c => c |> @conventions.without(SystemDir))
    |> build(_ => ()) |> injected_run
  assert_false(replaced.context.config.reports().iter().any(r => r.kind is File(System)))
  assert_true(replaced.context.config.reports().iter().any(r => r.kind is File(Workspace)))
}

///|
/// The parsed path of the test path `text`.
fn p(text : String) -> @config.FileTreePath {
  @config.FileTreePath::parse(text) catch {
    _ => abort("invalid test path \{text}")
  }
}

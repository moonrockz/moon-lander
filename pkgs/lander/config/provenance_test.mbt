///|
fn json_tree(json : Json) -> @config.ConfigValue {
  @config.ConfigValue::from_json(json) catch {
    error => abort(error.message())
  }
}

///|
fn named(json : Json, name : String) -> @config.ConfigSource {
  @config.in_memory(json_tree(json), name~) catch {
    error => abort(error.message())
  }
}

///|
fn origin_names(config : @config.Config, text : String) -> Array[String] {
  config.origins(key(text)).map(origin => origin.source)
}

///|
test "Null does not unset" {
  let config = @config.build([
    named({ "ir": { "layout": "tree" } }, "base"),
    named({ "ir": { "layout": null } }, "overlay"),
  ])
  @expect.expect(@config.get_text(config, "ir.layout")).to_equal("tree")
  @expect.expect(origin_names(config, "ir.layout")).to_equal(["base"])
}

///|
test "Null with no base value" {
  let config = @config.build([
    named({ "a": null, "b": { "c": null, "d": 1 }, "e": [null] }, "only"),
  ])
  @expect.expect(config.value()).to_equal(
    json_tree({ "b": { "d": 1 }, "e": [null] }),
  )
  @expect.expect(config.get(key("a"))).to_equal(None)
}

///|
test "a null overlay root or field keeps the base value" {
  let base = json_tree({ "a": { "b": 1 } })
  @expect.expect(@config.merge(base, json_tree({ "a": null }))).to_equal(base)
  @expect.expect(@config.merge(base, json_tree({ "x": null }))).to_equal(base)
}

///|
test "Scalar replaces a struct" {
  let merged = @config.merge(
    json_tree({ "ir": { "layout": "tree" } }),
    json_tree({ "ir": "x" }),
  )
  @expect.expect(merged).to_equal(json_tree({ "ir": "x" }))
}

///|
test "Inputs do not change" {
  let base_json : Json = { "a": { "b": 1, "c": [1, 2] }, "d": "x" }
  let overlay_json : Json = { "a": { "b": 2, "e": null }, "f": true }
  let base = json_tree(base_json)
  let overlay = json_tree(overlay_json)
  @config.merge(base, overlay) |> ignore
  @expect.expect(base).to_equal(json_tree(base_json))
  @expect.expect(overlay).to_equal(json_tree(overlay_json))
  @expect.expect(field_names(base)).to_equal(["a", "d"])
  @expect.expect(field_names(overlay)).to_equal(["a", "f"])
}

///|
test "New keys follow base keys" {
  let merged = @config.merge(
    json_tree({ "a": 1, "b": 2 }),
    json_tree({ "c": 3, "a": 4 }),
  )
  @expect.expect(field_names(merged)).to_equal(["a", "b", "c"])
}

///|
/// Generation choices for a value tree. Struct names (`s1`, `s2`) always hold
/// structs and leaf names (`x`, `y`, `z`) always hold leaves, so no path is a
/// struct in one tree and a leaf in another.
priv struct TreeCase {
  choices : Array[UInt]
} derive(Debug)

///|
impl @quickcheck.Arbitrary for TreeCase with fn arbitrary(size, state) {
  { choices: @quickcheck.Arbitrary::arbitrary(size, state) }
}

///|
impl @shrink.Shrink for TreeCase with fn shrink(self) {
  @shrink.Shrink::shrink(self.choices).map(choices => { choices, })
}

///|
fn TreeCase::tree(self : TreeCase) -> @config.ConfigValue {
  let cursor = Ref(0)
  let next = () => {
    let index = cursor.val
    cursor.val += 1
    if index < self.choices.length() {
      self.choices[index]
    } else {
      0
    }
  }
  fn build(depth : Int) -> Json {
    let object : Map[String, Json] = Map([])
    for name in ["s1", "s2"] {
      if depth > 0 && next() % 3 == 0 {
        object[name] = build(depth - 1)
      }
    }
    for name in ["x", "y", "z"] {
      let choice = next()
      match choice % 5 {
        0 => object[name] = Json::number((choice / 5).to_double())
        1 => object[name] = Json::string("v\{choice / 5 % 4}")
        2 => object[name] = Json::null()
        3 => object[name] = Json::array([Json::number(choice.to_double())])
        _ => ()
      }
    }
    Json::object(object)
  }

  json_tree(build(3))
}

///|
test "law: merge is associative when names keep their shape" {
  @expect.for_all(
    (input : (TreeCase, TreeCase, TreeCase)) => {
      let (a, b, c) = (input.0.tree(), input.1.tree(), input.2.tree())
      @expect.expect(@config.merge(@config.merge(a, b), c)).to_equal(
        @config.merge(a, @config.merge(b, c)),
      )
    },
    count=500,
    max_size=40,
    max_shrinks=200,
    seed=4204,
  )
}

///|
test "Winning origins" {
  let config = @config.build([
    named({ "project": { "name": "A", "exposed_modules": ["X"] } }, "base"),
    named({ "project": { "exposed_modules": ["Y", "Z"] } }, "user"),
  ])
  @expect.expect(origin_names(config, "project.name")).to_equal(["base"])
  @expect.expect(origin_names(config, "project.exposed_modules")).to_equal([
    "user",
  ])
}

///|
test "Stale records go" {
  let config = @config.build([
    named({ "ir": { "layout": "tree", "mode": "fast" } }, "base"),
    named({ "ir": "x" }, "overlay"),
  ])
  @expect.expect(
    config.provenance().map(record => (record.0.to_string(), record.1.length())),
  ).to_equal([("ir", 1)])
  @expect.expect(origin_names(config, "ir")).to_equal(["overlay"])
  @expect.expect(config.origins(key("ir.layout"))).to_equal([])
}

///|
test "a struct over a leaf removes the leaf record" {
  let config = @config.build([
    named({ "ir": "x" }, "base"),
    named({ "ir": { "layout": "tree" } }, "overlay"),
    named({ "ir": {} }, "empty"),
  ])
  @expect.expect(config.provenance().map(record => record.0.to_string())).to_equal([
    "ir.layout",
  ])
  @expect.expect(config.origins(key("ir"))).to_equal([])
}

///|
test "an origin holds the kind, name, priority, and file path" {
  let config = @config.builder()
    |> @config.format(@toml.format())
    |> @config.defaults({ "ir": { "layout": "tree" } })
    |> @config.file("/w/app.toml")
    |> @config.load(
      @config.FileTree::new(complete=true).with_file(
        "/w/app.toml",
        "ir.mode = \"fast\"",
      ),
    )
    |> done
  @expect.expect(config.origins(key("ir.layout"))).to_equal([
    { kind: Defaults, source: "defaults", priority: 0, location: None },
  ])
  @expect.expect(config.origins(key("ir.mode"))).to_equal([
    {
      kind: File(Explicit),
      source: "/w/app.toml",
      priority: 300,
      location: Some("/w/app.toml"),
    },
  ])
}

///|
test "excluded values have no provenance" {
  let config = @config.build([
    named({ "workspace": { "out_dir": "base" } }, "base"),
    named({ "workspace": { "out_dir": "member", "name": "m" } }, "member").exclude(
      [key("workspace.out_dir")],
      warn=false,
    ),
  ])
  @expect.expect(origin_names(config, "workspace.out_dir")).to_equal(["base"])
  @expect.expect(origin_names(config, "workspace.name")).to_equal(["member"])
}

///|
test "every leaf has a non-empty origin list" {
  let config = @config.build([
    named({ "a": 1, "b": { "c": [1, 2], "d": null } }, "one"),
    named({ "b": { "c": [3], "e": "x" }, "f": { "g": true } }, "two"),
  ])
  let provenance = config.provenance()
  @expect.expect(provenance.map(record => record.0.to_string())).to_equal([
    "a", "b.c", "b.e", "f.g",
  ])
  @expect.expect(provenance.all(record => record.1.length() == 1)).to_equal(
    true,
  )
}

///|
test "Report order and status" {
  let config = @config.builder()
    |> @config.format(@toml.format())
    |> @config.defaults({ "a": 1 })
    |> @config.file("/w/app.toml")
    |> @config.add(@config.ConfigSource::skipped(Environment))
    |> @config.add(
      @config.ConfigSource::candidates(
        ["/w/app.user.toml"],
        display="App",
        role=UserOverride,
        // After the environment source, the order check needs a priority.
        priority=600,
      ),
    )
    |> @config.load(
      @config.FileTree::new(complete=true)
      .with_listing("/w", [{ name: "app.toml", kind: File }])
      .with_file("/w/app.toml", "b = 2"),
    )
    |> done
  @expect.expect(
    config.reports().map(report => (report.kind.report_name(), report.status)),
  ).to_equal([
    ("defaults", Loaded),
    ("project", Loaded),
    ("environment", Skipped),
    ("user-override", NotFound),
  ])
}

///|
test "File role names" {
  let config = @config.build(
    ([Member, LocalOverride, UserOverride] : Array[@config.FileRole]).map(role => {
      @config.ConfigSource::skipped(File(role))
    }),
  )
  @expect.expect(config.reports().map(report => report.kind.report_name())).to_equal([
    "workspace-member", "local-override", "user-override",
  ])
}

///|
test "report names of every kind" {
  let kinds : Array[@config.SourceKind] = [
    Defaults,
    InMemory,
    File(System),
    File(Global),
    File(Workspace),
    File(Explicit),
    File(Legacy),
    File(Member),
    File(EnvironmentFile),
    File(LocalOverride),
    File(UserOverride),
    Environment,
    Overrides,
  ]
  @expect.expect(kinds.map(kind => kind.report_name())).to_equal([
    "defaults", "in-memory", "system", "global", "project", "project", "project",
    "workspace-member", "environment-file", "local-override", "user-override", "environment",
    "overrides",
  ])
}

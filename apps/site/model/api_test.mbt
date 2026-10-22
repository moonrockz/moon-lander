///|
fn problems_in(action : () -> Unit raise @model.Invalid) -> Array[String] {
  try action() catch {
    @model.Invalid(problems) => problems.map(p => p.render())
  } noraise {
    _ => []
  }
}

///|
test "Fixture shape" {
  let api = @model.ApiPackage::parse("package_data.json", notebooks_package_data)
  @expect.expect(api.path).to_equal("moonrockz/notebooks")
  let names = api.types.map(item => item.entry.name)
  @expect.expect(names.contains("CellKind")).to_be_true()
  guard api.types.search_by(item => item.entry.name == "CellKind") is Some(i) else {
    fail("no CellKind")
  }
  let cell_kind = api.types[i]
  @expect.expect(cell_kind.entry.loc).to_equal({
    path: "moonrockz/notebooks",
    file: "navigation.mbt",
    line: 4,
  })
  @expect.expect(cell_kind.methods.map(m => m.name)).to_equal([
    "equal", "not_equal", "to_repr",
  ])
  @expect.expect(api.aliases).to_equal([])
  @expect.expect(api.values.map(v => v.name).contains("walk")).to_be_true()
  guard api.types.search_by(item => item.entry.name == "Metadata") is Some(m) else {
    fail("no Metadata")
  }
  @expect.expect(
    api.types[m].impls.map(i => (i.trait_name, i.trait_path, i.self_type, i.methods.length())),
  ).to_equal([("Eq", "moonbitlang/core/builtin", "Metadata", 1)])
  let packages = @model.api_index_packages(
    "module_index.json", notebooks_module_index,
  )
  @expect.expect(packages).to_equal([
    "moonrockz/notebooks", "moonrockz/notebooks/dib", "moonrockz/notebooks/nbformat",
  ])
}

///|
test "Format change" {
  let without_values = notebooks_package_data.replace(
    old="\"values\":",
    new="\"values_moved\":",
  )
  @expect.expect(
    problems_in(() => {
      @model.ApiPackage::parse("doc/moonrockz/notebooks/package_data.json", without_values)
      |> ignore
    }),
  ).to_equal([
    "doc/moonrockz/notebooks/package_data.json: missing key `values`",
  ])
  @expect.expect(
    problems_in(() => {
      @model.ApiPackage::parse(
        "p.json", "{\"name\":\"p\",\"types\":[{\"name\":\"T\",\"methods\":[],\"impls\":[]}],\"errors\":[],\"traits\":[],\"typealias\":[],\"values\":[]}",
      )
      |> ignore
    }),
  ).to_equal(["p.json: missing key `types[0].loc`"])
  let entry = "{\"name\":\"T\",\"docstring\":\"\",\"signature\":\"\",\"loc\":{\"path\":\"p\",\"file\":\"f.mbt\",\"line\":1},\"impls\":[]}"
  @expect.expect(
    problems_in(() => {
      @model.ApiPackage::parse(
        "p.json",
        "{\"name\":\"p\",\"types\":[\{entry}],\"errors\":[],\"traits\":[],\"typealias\":[],\"values\":[]}",
      )
      |> ignore
    }),
  ).to_equal(["p.json: missing key `types[0].methods`"])
  @expect.expect(
    problems_in(() => {
      @model.ApiPackage::parse(
        "p.json",
        "{\"name\":\"p\",\"types\":[],\"errors\":[],\"traits\":[\{entry}],\"typealias\":[],\"values\":[]}",
      )
      |> ignore
    }),
  ).to_equal([])
  @expect.expect(
    problems_in(() => {
      @model.ApiPackage::parse("p.json", "[]") |> ignore
    }),
  ).to_equal(["p.json: `(root)` must be an object"])
  @expect.expect(
    problems_in(() => {
      @model.api_index_packages("m.json", "{\"name\":\"m\",\"package\":null}")
      |> ignore
    }),
  ).to_equal(["m.json: missing key `childs`"])
}

///|
test "Signature text" {
  @expect.expect(
    @model.parse_signature(
      "fn[N : <a href=\"moonrockz/notebooks#Node\">Node</a>] at(root : N) -> N?",
    ),
  ).to_equal(
    Ok([
      Text("fn[N : "),
      Link("moonrockz/notebooks#Node", "Node"),
      Text("] at(root : N) -> N?"),
    ]),
  )
  @expect.expect(@model.parse_signature("fn f(a : Int) -> Int < 3 && b")).to_equal(
    Ok([Text("fn f(a : Int) -> Int < 3 && b")]),
  )
  @expect.expect(@model.parse_signature("")).to_equal(Ok([]))
}

///|
test "Unknown markup" {
  @expect.expect(@model.parse_signature("fn f() -> <a>T</a>")).to_equal(
    Err("an `<a>` tag has no `href`"),
  )
  @expect.expect(@model.parse_signature("fn f() -> <a class=\"x\">T</a>")).to_equal(
    Err("an `<a>` tag has no `href`"),
  )
  @expect.expect(@model.parse_signature("fn f() -> <a href=\"p#T\">T")).to_equal(
    Err("the link to `p#T` has no `</a>`"),
  )
  @expect.expect(@model.parse_signature("fn f() -> T</a>")).to_equal(
    Err("a `</a>` tag has no `<a>`"),
  )
}

///|
test "every fixture signature parses" {
  let api = @model.ApiPackage::parse("package_data.json", notebooks_package_data)
  let entries = api.aliases + api.values
  for item in api.types + api.errors + api.traits {
    entries.push(item.entry)
    entries.append(item.methods)
    for impl_ in item.impls {
      entries.append(impl_.methods)
    }
  }
  for entry in entries {
    @expect.expect(@model.parse_signature(entry.signature) is Ok(_)).to_be_true()
  }
}

///|
let site_packages : Array[String] = ["moonrockz/notebooks", "moonrockz/moon-lander"]

///|
test "Same package" {
  @expect.expect(
    @model.api_link(
      "moonrockz/notebooks#CellKind",
      current="moonrockz/notebooks",
      site_packages~,
      base_path="/moon-lander/",
    ),
  ).to_equal(Some("#CellKind"))
}

///|
test "a target in another site package links its API page" {
  @expect.expect(
    @model.api_link(
      "moonrockz/moon-lander#version",
      current="moonrockz/notebooks",
      site_packages~,
      base_path="/moon-lander/",
    ),
  ).to_equal(Some("/moon-lander/api/moonrockz/moon-lander/#version"))
  @expect.expect(
    @model.api_link(
      "moonrockz/notebooks",
      current="moonrockz/notebooks",
      site_packages~,
      base_path="/moon-lander/",
    ),
  ).to_equal(Some("/moon-lander/api/moonrockz/notebooks/"))
}

///|
test "Package outside the site" {
  @expect.expect(
    @model.api_link(
      "moonbitlang/core/builtin#Eq",
      current="moonrockz/notebooks",
      site_packages~,
      base_path="/moon-lander/",
    ),
  ).to_equal(None)
}

///|
test "Source link" {
  let loc : @model.ApiLoc = {
    path: "moonrockz/notebooks",
    file: "navigation.mbt",
    line: 4,
  }
  @expect.expect(
    @model.api_source_url(
      repo_url="https://github.com/moonrockz/moon-lander",
      commit="abc123",
      module_dir="pkgs/notebooks",
      module_name="moonrockz/notebooks",
      loc,
    ),
  ).to_equal(
    "https://github.com/moonrockz/moon-lander/blob/abc123/pkgs/notebooks/navigation.mbt#L4",
  )
  @expect.expect(
    @model.api_source_url(
      repo_url="https://github.com/moonrockz/moon-lander",
      commit="abc123",
      module_dir="pkgs/notebooks",
      module_name="moonrockz/notebooks",
      { ..loc, path: "moonrockz/notebooks/dib", file: "parse.mbt" },
    ),
  ).to_equal(
    "https://github.com/moonrockz/moon-lander/blob/abc123/pkgs/notebooks/dib/parse.mbt#L4",
  )
}

///|
test "method anchors" {
  @expect.expect(@model.api_method_anchor("CellKind", "equal")).to_equal(
    "CellKind.equal",
  )
  @expect.expect(
    @model.api_method_anchor("Metadata", "equal", via="Eq"),
  ).to_equal("Metadata.Eq.equal")
  @expect.expect(
    @model.api_method_anchor("Validate", "validate", via="Map[String, T]"),
  ).to_equal("Validate.Map[String,T].validate")
}

///|
test "missing docstrings are listed by anchor" {
  let api = @model.ApiPackage::parse("package_data.json", notebooks_package_data)
  let missing = @model.api_missing_docstrings(api)
  @expect.expect(missing.contains("CellKind.equal")).to_be_true()
  @expect.expect(missing.contains("CellKind")).to_be_false()
  @expect.expect(missing.contains("Metadata.Eq.equal")).to_be_true()
}

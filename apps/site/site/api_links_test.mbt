///|
/// A site with one API package, `moonrockz/notebooks`, that has the type `CellKind`.
let notebooks_api : @site.ApiSite = {
  commit: "abc",
  modules: [
    {
      dir: "pkgs/notebooks",
      name: "moonrockz/notebooks",
      packages: [
        {
          path: "moonrockz/notebooks",
          types: [
            {
              entry: {
                name: "CellKind",
                docstring: "",
                signature: "pub(all) enum CellKind",
                loc: { path: "moonrockz/notebooks", file: "navigation.mbt", line: 4 },
              },
              methods: [],
              impls: [],
            },
          ],
          errors: [],
          traits: [],
          aliases: [],
          values: [],
        },
      ],
      readmes: {},
    },
  ],
}

///|
test "Item link" {
  let prepared = @site.prepare(
    { ..lander, api: ["pkgs/notebooks"] },
    [source("docs/a.md", "# A\n\n[CellKind](api:moonrockz/notebooks#CellKind)\n")],
    main_build=true,
    api=notebooks_api,
  )
  assert_true(
    page(prepared, "/docs/a/").html.contains(
      "href=\"/moon-lander/api/moonrockz/notebooks/#CellKind\"",
    ),
  )
}

///|
test "Unknown item" {
  let problems = try
    @site.prepare(
      { ..lander, api: ["pkgs/notebooks"] },
      [source("docs/a.md", "# A\n\n[x](api:moonrockz/notebooks#NoSuchItem)\n")],
      main_build=true,
      api=notebooks_api,
    )
    |> ignore
  catch {
    @model.Invalid(problems) => problems.map(p => p.render())
  } noraise {
    _ => []
  }
  assert_eq(problems, [
    "docs/a.md: API link `api:moonrockz/notebooks#NoSuchItem`: the API page of `moonrockz/notebooks` has no item or method `#NoSuchItem`",
  ])
}

///|
test "an api: link without API pages is an error" {
  assert_eq(
    scenario_problems([source("docs/a.md", "# A\n\n[x](api:moonrockz/notebooks)\n")]),
    [
      "docs/a.md: API link `api:moonrockz/notebooks`: no API page for the package `moonrockz/notebooks`",
    ],
  )
}

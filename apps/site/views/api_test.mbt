///|
async test "the header has an API link only when the site has API pages" {
  let without = @views.render(meta("/docs/", "Docs", Docs), @views.raw(""))
  assert_false(without.contains("href=\"/m/api/\""))
  let with_api : @views.PageMeta = {
    config: { ..config, api: ["pkgs/notebooks"] },
    route: "/api/",
    title: "API reference",
    description: "d",
    section: Api,
  }
  let out = @views.render(with_api, @views.raw(""))
  assert_true(out.contains("href=\"/m/api/\""))
  assert_true(out.contains("aria-current=\"page\""))
}

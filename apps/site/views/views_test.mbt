///|
fn config() -> @model.SiteConfig {
  {
    title: "Moon-Lander",
    description: "An application framework for MoonBit.",
    base_path: "/moon-lander/",
    site_url: "https://moonrockz.github.io/moon-lander/",
    repo_url: "https://github.com/moonrockz/moon-lander",
    packages: [],
  }
}

///|
async test "layout links use the base path" {
  let page = @views.render(
    { config: config(), route: "/", title: "", description: "d" },
    @views.raw("<p>Hello</p>"),
  )
  assert_true(page.contains("<html data-base=\"/moon-lander/\" lang=\"en\">"))
  assert_true(page.contains("<title>Moon-Lander</title>"))
  assert_true(page.contains("href=\"/moon-lander/assets/site.css\""))
  assert_true(page.contains("<a href=\"/moon-lander/\" target=\"_self\" class=\"brand\">"))
  assert_true(page.contains("<div class=\"prose\"><p>Hello</p></div>"))
}

///|
async test "a page title comes before the site title" {
  let page = @views.render(
    { config: config(), route: "/docs/", title: "Docs", description: "d" },
    @views.raw(""),
  )
  assert_true(page.contains("<title>Docs · Moon-Lander</title>"))
}

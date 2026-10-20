///|
fn site_json(base_path~ : String = "/moon-lander/") -> String {
  (
    $|{
    $|  "title": "Moon-Lander",
    $|  "description": "An application framework for MoonBit.",
    $|  "base_path": "\{base_path}",
    $|  "site_url": "https://moonrockz.github.io/moon-lander/",
    $|  "repo_url": "https://github.com/moonrockz/moon-lander",
    $|  "packages": ["notebooks"]
    $|}
  )
}

///|
fn problems_of(text : String) -> Array[String] {
  try @model.SiteConfig::parse("site/site.json", text) catch {
    @model.Invalid(problems) => problems.map(p => p.render())
  } noraise {
    _ => []
  }
}

///|
test "parse reads the site configuration" {
  let config = @model.SiteConfig::parse("site/site.json", site_json())
  @expect.expect(config).to_equal({
    title: "Moon-Lander",
    description: "An application framework for MoonBit.",
    base_path: "/moon-lander/",
    site_url: "https://moonrockz.github.io/moon-lander/",
    repo_url: "https://github.com/moonrockz/moon-lander",
    packages: ["notebooks"],
    nav: None,
    chapters: [],
  })
}

///|
test "bad base path names the file and the key" {
  @expect.expect(problems_of(site_json(base_path="/moon-lander"))).to_equal([
    "site/site.json: `base_path` must start and end with `/`",
  ])
  @expect.expect(problems_of(site_json(base_path="moon-lander/"))).to_equal([
    "site/site.json: `base_path` must start and end with `/`",
  ])
}

///|
test "every problem is reported" {
  @expect.expect(problems_of("{\"base_path\": \"x\"}")).to_equal([
    "site/site.json: missing string field `title`",
    "site/site.json: missing string field `description`",
    "site/site.json: missing string field `site_url`",
    "site/site.json: missing string field `repo_url`",
    "site/site.json: `base_path` must start and end with `/`",
  ])
}

///|
test "packages must be an array of strings" {
  for value in ["\"notebooks\"", "{}", "[\"notebooks\", 1]"] {
    @expect.expect(
      problems_of(site_json().replace(old="[\"notebooks\"]", new=value)),
    ).to_equal(["site/site.json: `packages` must be an array of strings"])
  }
}

///|
test "the configuration must be a JSON object" {
  @expect.expect(problems_of("[]")).to_equal([
    "site/site.json: must be a JSON object",
  ])
}

///|
test "links use the base path" {
  let config = @model.SiteConfig::parse("site/site.json", site_json())
  @expect.expect(config.href("/articles/")).to_equal("/moon-lander/articles/")
  @expect.expect(config.href("/")).to_equal("/moon-lander/")
  @expect.expect(config.href("/assets/site.css")).to_equal(
    "/moon-lander/assets/site.css",
  )
  @expect.expect(config.absolute("/articles/")).to_equal(
    "https://moonrockz.github.io/moon-lander/articles/",
  )
}

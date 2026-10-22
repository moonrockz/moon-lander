///|
fn with_api(api : String) -> String {
  site_json().replace(
    old="\"packages\": [\"notebooks\"]",
    new="\"packages\": [\"notebooks\"],\n  \"api\": \{api}",
  )
}

///|
test "api lists module directories below pkgs/" {
  let config = @model.SiteConfig::parse(
    "site/site.json",
    with_api("[\"pkgs/lander\", \"pkgs/notebooks\"]"),
  )
  @expect.expect(config.api).to_equal(["pkgs/lander", "pkgs/notebooks"])
}

///|
test "Unpublished module in the API list" {
  @expect.expect(problems_of(with_api("[\"apps/site\", \"tests\"]"))).to_equal([
    "site/site.json: `api` lists `apps/site`: only module directories below `pkgs/` have API pages",
    "site/site.json: `api` lists `tests`: only module directories below `pkgs/` have API pages",
  ])
  @expect.expect(
    problems_of(
      with_api("[\"pkgs/../apps/site\", \"pkgs/\", \"pkgs/x\", \"pkgs/x\"]"),
    ),
  ).to_equal([
    "site/site.json: `api` lists `pkgs/../apps/site`: only module directories below `pkgs/` have API pages",
    "site/site.json: `api` lists `pkgs/`: only module directories below `pkgs/` have API pages",
    "site/site.json: `api` lists `pkgs/x` more than once",
  ])
  @expect.expect(problems_of(with_api("\"pkgs/x\""))).to_equal([
    "site/site.json: `api` must be an array of module directories",
  ])
}

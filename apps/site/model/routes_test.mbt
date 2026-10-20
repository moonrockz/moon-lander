///|
test "a route is written as the index file of its directory" {
  @expect.expect(@model.route_file("/docs/design/overview/")).to_equal(
    "docs/design/overview/index.html",
  )
  @expect.expect(@model.route_file("/")).to_equal("index.html")
}

///|
let prose_anchors : Map[String, Array[String]] = {
  "moonrockz/notebooks": ["CellKind", "CellKind.equal", "walk"],
}

///|
test "an api: link goes to the API page and anchor" {
  @expect.expect(
    @model.api_prose_link(
      "api:moonrockz/notebooks#CellKind",
      anchors=prose_anchors,
      base_path="/moon-lander/",
    ),
  ).to_equal(Ok("/moon-lander/api/moonrockz/notebooks/#CellKind"))
  @expect.expect(
    @model.api_prose_link(
      "api:moonrockz/notebooks#CellKind.equal",
      anchors=prose_anchors,
      base_path="/moon-lander/",
    ),
  ).to_equal(Ok("/moon-lander/api/moonrockz/notebooks/#CellKind.equal"))
  @expect.expect(
    @model.api_prose_link(
      "api:moonrockz/notebooks",
      anchors=prose_anchors,
      base_path="/moon-lander/",
    ),
  ).to_equal(Ok("/moon-lander/api/moonrockz/notebooks/"))
}

///|
test "an api: link to an unknown package or item is an error" {
  @expect.expect(
    @model.api_prose_link(
      "api:moonrockz/notebooks#NoSuchItem",
      anchors=prose_anchors,
      base_path="/moon-lander/",
    ),
  ).to_equal(
    Err(
      "the API page of `moonrockz/notebooks` has no item or method `#NoSuchItem`",
    ),
  )
  @expect.expect(
    @model.api_prose_link(
      "api:moonrockz/nothing",
      anchors=prose_anchors,
      base_path="/moon-lander/",
    ),
  ).to_equal(Err("no API page for the package `moonrockz/nothing`"))
}

///|
test "the anchors of a package are its items and methods" {
  let api = @model.ApiPackage::parse("package_data.json", notebooks_package_data)
  let anchors = @model.api_anchors(api)
  @expect.expect(anchors.contains("CellKind")).to_be_true()
  @expect.expect(anchors.contains("CellKind.equal")).to_be_true()
  @expect.expect(anchors.contains("Metadata.Eq.equal")).to_be_true()
  @expect.expect(anchors.contains("walk")).to_be_true()
}

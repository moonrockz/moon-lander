///|
/// A consumer's cell can support MIME lookup independently of navigation.
struct MimeCell {
  name : String
  types : ReadOnlyArray[String]
}

///|
impl @notebooks.MimeTyped for MimeCell with fn has_mime_type(self, mime_type) {
  self.types.contains(mime_type)
}

///|
impl @notebooks.CellView for MimeCell with fn kind(_self) {
  @notebooks.Raw
}

///|
impl @notebooks.CellView for MimeCell with fn source(self) {
  Some(self.name)
}

///|
impl @notebooks.CellView for MimeCell with fn mime_capability(self) {
  Some(self as &@notebooks.MimeTyped)
}

///|
test "consumer-defined MIME-capable cells use the shared query" {
  let cells : ReadOnlyArray[MimeCell] = [
    { name: "first", types: ["image/png", "text/plain"], },
    { name: "empty", types: [], },
    { name: "second", types: ["image/png"], },
  ]
  let matches = @notebooks.cells_by_mime_type(cells, "image/png")
  @expect.expect_all(s => {
    s.expect(matches.map(cell => cell.name)).to_equal(["first", "second"])
    s
    .expect(
      @notebooks.cells_by_mime_type(cells, "text/plain").map(cell => cell.name),
    )
    .to_equal(["first"])
    s.expect(@notebooks.cells_by_mime_type(cells, "IMAGE/PNG").length()).to_equal(0)
    s.expect(@notebooks.cells_by_mime_type(cells, "image/jpeg").length()).to_equal(0)
  })
}

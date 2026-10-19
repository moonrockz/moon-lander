///|
struct PlainCell(String)

///|
impl @notebooks.CellView for PlainCell with fn kind(_self) {
  @notebooks.Raw
}

///|
impl @notebooks.CellView for PlainCell with fn source(self) {
  Some(self.0)
}

///|
test "consumer cells opt into runtime capability inspection or use its default" {
  let cells : ReadOnlyArray[&@notebooks.CellView] = [
    MimeCell::{ name: "image", types: ["image/png"], },
    PlainCell("plain"),
    MimeCell::{ name: "empty", types: [], },
  ]
  @expect.expect_all(s => {
    s.expect(cells.map(cell => cell.source())).to_equal([
      Some("image"), Some("plain"), Some("empty"),
    ])
    s.expect(cells.map(cell => cell.kind())).to_equal([
      @notebooks.Raw, @notebooks.Raw, @notebooks.Raw,
    ])
    s.expect(cells.map(cell => cell.metadata())).to_equal([None, None, None])
    s.expect(
      cells.map(cell => cell.mime_capability().map(mime => {
        mime.has_mime_type("image/png")
      })),
    ).to_equal([Some(true), None, Some(false)])
  })
}

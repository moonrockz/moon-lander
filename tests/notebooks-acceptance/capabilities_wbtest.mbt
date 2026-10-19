///|
struct CapabilityWorld {
  cells : Array[&@notebooks.CellView]
  results : Array[String]
}

///|
impl @moonspec.World for CapabilityWorld with fn configure(self, setup) {
  setup.given1("cells from the Jupyter notebook:", (doc : @moonspec.DocString) => {
    for cell in @nbformat.parse(doc.content).cells() {
      self.cells.push(cell)
    }
  })
  setup.given1("cells from the DIB notebook:", (doc : @moonspec.DocString) => {
    for cell in @dib.parse(doc.content).cells() {
      self.cells.push(cell)
    }
  })
  setup.when1("I inspect the mixed cells for MIME type {string}", (
    mime_type : String,
  ) => {
    self.results.clear()
    for cell in self.cells {
      self.results.push(
        match cell.mime_capability() {
          None => "unsupported"
          Some(mime) =>
            if mime.has_mime_type(mime_type) {
              "matched"
            } else {
              "no match"
            }
        },
      )
    }
  })
  setup.then1("the MIME inspection results are {string}", (expected : String) => {
    @expect.expect(self.results.join(",")).to_equal(expected)
  })
}

///|
async test "mixed cell capability inspection" {
  @moonspec.run_or_fail(
    () => CapabilityWorld::{ cells: [], results: [], },
    @moonspec.RunOptions::RunOptions([
      @moonspec.FeatureSource::File(
        "notebooks-acceptance/features/capabilities.feature",
      ),
    ]),
  )
}

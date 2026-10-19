///|
test "MIME queries select rich outputs and attachments once in document order" {
  let source =
    #|{"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[
    #|{"id":"display","cell_type":"code","metadata":{},"source":"","execution_count":null,"outputs":[
    #|  {"output_type":"display_data","metadata":{},"data":{"image/png":"","application/json":null}},
    #|  {"output_type":"execute_result","metadata":{},"execution_count":null,"data":{"image/png":"another image"}}]},
    #|{"id":"markdown","cell_type":"markdown","metadata":{},"source":"","attachments":{
    #|  "first.png":{"image/png":"abc"},"second.png":{"image/png":"def","image/svg+xml":"<svg/>"}}},
    #|{"id":"result","cell_type":"code","metadata":{},"source":"","execution_count":null,"outputs":[
    #|  {"output_type":"execute_result","metadata":{},"execution_count":null,"data":{"application/json":{"answer":42}}}]},
    #|{"id":"raw","cell_type":"raw","metadata":{},"source":"","attachments":{"data.json":{"application/json":[]}}}]}
  let book = @nbformat.parse(source)
  @expect.expect_all(s => {
    s.expect(book.cells_by_mime_type("image/png")).to_equal([
      book.cells()[0], book.cells()[1],
    ])
    s.expect(book.cells()[0].has_mime_type("application/json")).to_be_true()
    s.expect(book.cells()[0].mime_capability().map(mime => {
      mime.has_mime_type("application/json")
    })).to_equal(Some(true))
    s.expect(book.cells()[1].has_mime_type("image/png")).to_be_true()
    s.expect(book.cells()[2].has_mime_type("image/png")).to_be_false()
    s.expect(book.cells_by_mime_type("application/json")).to_equal([
      book.cells()[0], book.cells()[2], book.cells()[3],
    ])
    s.expect(book.cells_by_mime_type("image/svg+xml")).to_equal([book.cells()[1]])
    s.expect(book.cells_by_mime_type("image/jpeg")).to_equal([])
    s.expect(book.cells_by_mime_type("IMAGE/PNG")).to_equal([])
    s.expect(book.cells_by_mime_type("image/*")).to_equal([])
    s.expect(book.cells_by_mime_type("image/png; charset=utf-8")).to_equal([])
    s.expect(@nbformat.parse(book.to_string())).to_equal(book)
  })
}

///|
test "MIME queries do not infer MIME data from sources metadata or unknown fields" {
  let source =
    #|{"nbformat":4,"nbformat_minor":5,"metadata":{"language_info":{"name":"python","mimetype":"text/plain"}},"cells":[
    #|{"id":"source","cell_type":"markdown","metadata":{"image/png":"abc"},"source":"image/png","attachments":{}},
    #|{"id":"raw","cell_type":"raw","metadata":{"format":"text/plain"},"source":"raw text"},
    #|{"id":"empty","cell_type":"code","metadata":{},"source":"print(1)","execution_count":null,"outputs":[]},
    #|{"id":"outputs","cell_type":"code","metadata":{},"source":"","execution_count":null,"outputs":[
    #|  {"output_type":"stream","name":"stdout","text":"image/png"},
    #|  {"output_type":"error","ename":"Error","evalue":"image/png","traceback":[]},
    #|  {"output_type":"widget","data":{"image/png":"abc"}},
    #|  {"output_type":"display_data","data":{},"metadata":{"image/png":{"width":640}}}]},
    #|{"id":"unknown","cell_type":"future","metadata":{},"attachments":{"plot":{"image/png":"abc"}}}]}
  let book = @nbformat.parse(source)
  @expect.expect_all(s => {
    s.expect(book.cells_by_mime_type("image/png")).to_equal([])
    s.expect(book.cells_by_mime_type("text/plain")).to_equal([])
    s.expect(book.cells_by_mime_type("")).to_equal([])
    s
    .expect(@nbformat.Notebook::Notebook([]).cells_by_mime_type("image/png"))
    .to_equal([])
  })
}

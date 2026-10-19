///|
fn tree() -> @nbformat.Notebook raise {
  let source =
    #|{"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[
    #|{"id":"a","cell_type":"code","metadata":{},"source":"","execution_count":null,"outputs":[{"output_type":"stream","name":"stdout","text":"a"},{"output_type":"stream","name":"stderr","text":"b"}]},
    #|{"id":"b","cell_type":"markdown","metadata":{},"source":"","attachments":{"plot":{"image/png":"abc"}}}]}
  @nbformat.parse(source)
}

///|
test "cursor boundaries and subtree walks retain context" {
  let book = tree()
  let root = book.cursor()
  guard root.first_child() is Some(first) else { fail("no first cell") }
  guard first.first_child() is Some(output) else { fail("no output") }
  guard root.last_child() is Some(last) else { fail("no last cell") }
  let paths = []
  first.walk(cursor => {
    paths.push(cursor.path().to_string())
    Continue
  })
  @expect.expect_all(s => {
    s.expect(root.parent() is None).to_be_true()
    s.expect(root.next_sibling() is None).to_be_true()
    s.expect(root.previous_sibling() is None).to_be_true()
    s.expect(first.previous_sibling() is None).to_be_true()
    s.expect(last.next_sibling() is None).to_be_true()
    s.expect(output.first_child() is None).to_be_true()
    s.expect(output.last_child() is None).to_be_true()
    s
    .expect(first.next_sibling().map(cursor => cursor.node()))
    .to_equal(Some(last.node()))
    s.expect(paths).to_equal(["$[0]", "$[0][0]", "$[0][1]"])
    s.expect(first.path().to_string()).to_equal("$[0]")
    s.expect(first.node().cursor().path().to_string()).to_equal("$")
  })
}

///|
test "walk pruning leaves skipped cells and stopping cancels pending leaves" {
  let book = tree()
  let pruned = []
  @nbformat.walk_cursor(
    book.root(),
    cursor => {
      pruned.push("enter " + cursor.path().to_string())
      if cursor.path().to_string() == "$[0]" {
        SkipChildren
      } else {
        Continue
      }
    },
    leave=cursor => pruned.push("leave " + cursor.path().to_string()),
  )
  let stopped = []
  @nbformat.walk_cursor(
    book.root(),
    cursor => {
      stopped.push("enter " + cursor.path().to_string())
      if cursor.path().to_string() == "$[0][0]" {
        Stop
      } else {
        Continue
      }
    },
    leave=cursor => stopped.push("leave " + cursor.path().to_string()),
  )
  @expect.expect_all(s => {
    s
    .expect(pruned)
    .to_equal([
      "enter $", "enter $[0]", "leave $[0]", "enter $[1]", "enter $[1][0]", "leave $[1][0]",
      "leave $[1]", "leave $",
    ])
    s.expect(stopped).to_equal(["enter $", "enter $[0]", "enter $[0][0]"])
  })
}

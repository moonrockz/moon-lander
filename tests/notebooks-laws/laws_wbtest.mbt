///|
priv struct NotebookCase {
  choices : ReadOnlyArray[UInt32]
  style : UInt32
} derive(Debug)

///|
impl @quickcheck.Arbitrary for NotebookCase with fn arbitrary(size, state) {
  let (choices, style) : (ReadOnlyArray[UInt32], UInt32) = @quickcheck.Arbitrary::arbitrary(
    size, state,
  )
  { choices, style, }
}

///|
impl @shrink.Shrink for NotebookCase with fn shrink(self) {
  @shrink.Shrink::shrink((self.choices, self.style)).map(parts => {
    let (choices, style) = parts
    { choices, style, }
  })
}

///|
/// Sources and IDs stay valid when the generation choices shrink.
fn NotebookCase::pair(
  self : NotebookCase,
) -> (@nbformat.Notebook, @dib.Notebook) raise {
  let choices : ReadOnlyArray[UInt32] = if self.choices.is_empty() {
    [0U]
  } else {
    self.choices
  }
  let jupyter = []
  let dib = []
  for i, choice in choices {
    let markdown = choice % 2 == 0
    let source = if markdown {
      "# 🌙 Cell \{i}\n\nCafé \{choice}"
    } else {
      "#!share --from csharp value\nprint(\{choice})"
    }
    let content = if markdown {
      @nbformat.Markdown(source~, attachments=None)
    } else {
      @nbformat.Code(source~, execution_count=None, outputs=[])
    }
    jupyter.push(
      @nbformat.Cell::Cell(content, id=Some(@nbformat.CellId("cell-\{i}"))),
    )
    dib.push(
      @dib.Cell::Cell(
        source,
        kernel=@dib.KernelName(if markdown { "markdown" } else { "csharp" }),
      ),
    )
  }
  (
    @nbformat.Notebook::Notebook(ReadOnlyArray::from_array(jupyter[:])),
    @dib.Notebook::Notebook(ReadOnlyArray::from_array(dib[:])),
  )
}

///|
fn[N : @notebooks.Node] sources(
  root : N,
) -> ReadOnlyArray[(@notebooks.CellKind, String?)] {
  let values = []
  @notebooks.walk(root, node => {
    if node.kind() is Cell(kind) {
      values.push((kind, node.source()))
    }
    Continue
  })
  ReadOnlyArray::from_array(values[:])
}

///|
test "law: one generic source traversal observes both notebook formats" {
  @expect.for_all(
    (input : NotebookCase) => {
      let (jupyter, dib) = input.pair()
      @expect.expect(sources(jupyter.root())).to_equal(sources(dib.root()))
    },
    count=200,
    max_size=16,
    max_shrinks=200,
    seed=4101,
  )
}

///|
fn[N : @notebooks.Node] recursive_paths(
  root : N,
  prefix : ReadOnlyArray[Int32],
) -> ReadOnlyArray[String] {
  let paths = [@notebooks.NodePath(prefix).to_string()]
  for i, child in root.children() {
    let next = ReadOnlyArray::from_iter(prefix.iter().concat([i].iter()))
    paths.append(recursive_paths(child, next)[:])
  }
  ReadOnlyArray::from_array(paths[:])
}

///|
fn[N : @notebooks.Node + Eq + @debug.Debug] check_navigation(
  root : N,
) -> Unit raise {
  let positions = []
  @notebooks.walk_cursor(root, cursor => {
    positions.push(cursor)
    Continue
  })
  let expected = recursive_paths(root, [])
  @expect.expect_all(s => {
    s
    .expect(
      ReadOnlyArray::from_array(
        positions.map(cursor => cursor.path().to_string())[:],
      ),
    )
    .to_equal(expected)
    s
    .expect(@notebooks.fold(root, 0, (count, _) => count + 1))
    .to_equal(expected.length())
    for cursor in positions {
      s.expect(@notebooks.at(root, cursor.path())).to_equal(Some(cursor.node()))
      s.expect(cursor.depth()).to_equal(cursor.path().indices().length())
      if cursor.next_sibling() is Some(next) {
        s
        .expect(next.previous_sibling().map(previous => previous.path()))
        .to_equal(Some(cursor.path()))
      }
      if cursor.first_child() is Some(child) {
        s
        .expect(child.parent().map(parent => parent.path()))
        .to_equal(Some(cursor.path()))
      }
      let subtree = []
      cursor.walk(child => {
        subtree.push(child.path().to_string())
        Continue
      })
      s.expect(subtree[0]).to_equal(cursor.path().to_string())
    }
  })
}

///|
test "law: shared cursor paths and document order hold for both concrete trees" {
  @expect.for_all(
    (input : NotebookCase) => {
      let (jupyter, dib) = input.pair()
      check_navigation(jupyter.root())
      check_navigation(dib.root())
    },
    count=200,
    max_size=16,
    max_shrinks=200,
    seed=4102,
  )
}

///|
test "law: DIB rendering normalizes aliases and newlines without losing source" {
  @expect.for_all(
    (input : NotebookCase) => {
      let (_, book) = input.pair()
      let rendered = book.to_string()
      let newline = if input.style % 2 == 0 { "\r\n" } else { "\r" }
      let changed = rendered
        .replace_all(old="#!csharp\n", new="#!c#\n")
        .replace_all(old="#!markdown\n", new="#!md\n")
        .replace_all(old="\n", new=newline)
      @expect.expect_all(s => {
        s.expect(@dib.parse(rendered)).to_equal(book)
        s.expect(@dib.parse(changed)).to_equal(book)
        s.expect(@dib.parse(rendered).to_string()).to_equal(rendered)
      })
    },
    count=200,
    max_size=16,
    max_shrinks=200,
    seed=4103,
  )
}

///|
fn[N : @notebooks.Node] recursive_events(
  root : N,
  path : ReadOnlyArray[Int32],
  stop : Int32,
  visited : Array[Int32],
  events : Array[String],
) -> Bool {
  let position = @notebooks.NodePath(path).to_string()
  visited[0] += 1
  events.push("enter " + position)
  if visited[0] == stop {
    return true
  }
  if !(root.kind() is Cell(_)) {
    for i, child in root.children() {
      let next = ReadOnlyArray::from_iter(path.iter().concat([i].iter()))
      if recursive_events(child, next, stop, visited, events) {
        return true
      }
    }
  }
  events.push("leave " + position)
  false
}

///|
fn[N : @notebooks.Node] check_control(root : N, stop : Int32) -> Unit raise {
  let expected = []
  ignore(recursive_events(root, [], stop, [0], expected))
  let events = []
  let mut count = 0
  @notebooks.walk_cursor(
    root,
    cursor => {
      count += 1
      events.push("enter " + cursor.path().to_string())
      if count == stop {
        Stop
      } else if cursor.node().kind() is Cell(_) {
        SkipChildren
      } else {
        Continue
      }
    },
    leave=cursor => events.push("leave " + cursor.path().to_string()),
  )
  @expect.expect(events).to_equal(expected)
}

///|
test "law: pruning and immediate stop agree with a recursive model" {
  @expect.for_all(
    (input : NotebookCase) => {
      let (jupyter, dib) = input.pair()
      let stop = (input.style % 20).reinterpret_as_int()
      check_control(jupyter.root(), stop)
      check_control(dib.root(), stop)
    },
    count=200,
    max_size=16,
    max_shrinks=200,
    seed=4104,
  )
}

///|
fn[N : @notebooks.Node] own_metadata(root : N) -> @notebooks.Metadata? {
  root.metadata()
}

///|
test "law: native Ion metadata survives DIB output without down-conversion" {
  @expect.for_all(
    (input : NotebookCase) => {
      let (_, dib) = input.pair()
      let value = @ion.Ion::from_fields([
        @ion.field("choices", @ion.Ion::list(input.choices.iter().map(choice => {
          @ion.Ion::int(choice.reinterpret_as_int())
        }).collect()).with_annotation(@ion.symbol("generated"))),
        @ion.field("typed", @ion.Ion::typed_null(@ion.IonType::Int)),
        @ion.field("decimal", @ion.Ion::decimal(@ion.Decimal::parse("\{input.style}.50"))),
        @ion.field("timestamp", @ion.Ion::timestamp(@ion.Timestamp::parse("2026-10-19T12:30:00Z"))),
      ])
      let metadata = @notebooks.Metadata::from_ion(value)
      let book = @dib.Notebook::Notebook(dib.cells(), metadata~)
      let reread = @dib.parse(book.to_string())
      @expect.expect_all(s => {
        s.expect(reread).to_equal(book)
        s.expect(reread.metadata().to_ion().equals(value)).to_be_true()
      })
    },
    count=100,
    max_size=16,
    max_shrinks=200,
    seed=4106,
  )
}

///|
test "law: shared metadata survives both format codecs and mutable exports" {
  @expect.for_all(
    (input : NotebookCase) => {
      let (jupyter, dib) = input.pair()
      let value : Json = {
        "vendor": {
          "choices": Json(
            input.choices
            .iter()
            .map(choice => Json(choice.reinterpret_as_int()))
            .collect(),
          ),
          "style": Json(input.style.reinterpret_as_int()),
          "null": null,
        },
      }
      let metadata = @notebooks.Metadata(value)
      let jupyter = @nbformat.Notebook::Notebook(jupyter.cells(), metadata~)
      let dib = @dib.Notebook::Notebook(dib.cells(), metadata~)
      let reread_jupyter = @nbformat.parse(jupyter.to_string())
      let reread_dib = @dib.parse(dib.to_string())
      if metadata.to_json() is Object(fields) {
        fields.clear()
      }
      if metadata.get_json("vendor") is Some(Object(fields)) {
        fields.clear()
      }
      @expect.expect_all(s => {
        s.expect(metadata.to_json()).to_equal(value)
        s.expect(own_metadata(reread_jupyter.root())).to_equal(Some(metadata))
        s.expect(own_metadata(reread_dib.root())).to_equal(Some(metadata))
      })
    },
    count=200,
    max_size=16,
    max_shrinks=200,
    seed=4105,
  )
}

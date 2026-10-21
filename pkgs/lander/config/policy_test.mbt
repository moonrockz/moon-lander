///|
test "Append lists" {
  let config = @config.build([
    named({ "plugins": ["a"] }, "base"),
    named({ "plugins": ["b"] }, "overlay").with_key_policy(key("plugins"), Append),
  ])
  @expect.expect(config.value()).to_equal(
    tree([
      ("plugins", @config.list([@config.string("a"), @config.string("b")])),
    ]),
  )
}

///|
test "Key path policy beats source policy" {
  let config = @config.build([
    named({ "plugins": ["a"], "other": ["x"] }, "base"),
    named({ "plugins": ["b"], "other": ["y"] }, "overlay")
    .with_policy(Append)
    .with_key_policy(key("plugins"), Replace),
  ])
  @expect.expect(config.get(key("plugins"))).to_equal(
    Some(@config.list([@config.string("b")])),
  )
  @expect.expect(config.get(key("other"))).to_equal(
    Some(@config.list([@config.string("x"), @config.string("y")])),
  )
}

///|
test "Merge by key" {
  let config = @config.build([
    named(
      {
        "servers": [
          { "name": "a", "port": 1 },
          { "name": "b", "port": 2 },
        ],
      },
      "base",
    ),
    named(
      {
        "servers": [
          { "name": "b", "port": 3 },
          { "name": "c", "port": 4 },
        ],
      },
      "overlay",
    ).with_key_policy(key("servers"), MergeByKey("name")),
  ])
  @expect.expect(config.value()).to_equal(
    tree([
      (
        "servers",
        @config.list([
          tree([("name", @config.string("a")), ("port", @config.int(1))]),
          tree([("name", @config.string("b")), ("port", @config.int(3))]),
          tree([("name", @config.string("c")), ("port", @config.int(4))]),
        ]),
      ),
    ]),
  )
}

///|
test "Merge-by-key item without the key" {
  try
    @config.build([
      named({ "servers": [{ "name": "a", "port": 1 }] }, "base"),
      named({ "servers": [{ "port": 3 }] }, "overlay").with_key_policy(
        key("servers"),
        MergeByKey("name"),
      ),
    ])
  catch {
    error => {
      guard error is MergeKey(key~, index~, source~) else {
        fail("wrong error")
      }
      @expect.expect(key.to_string()).to_equal("servers")
      @expect.expect(index).to_equal(0)
      @expect.expect(source).to_equal("overlay")
    }
  } noraise {
    _ => fail("expected MergeKey")
  }
}

///|
test "Appended list has all contributors" {
  let config = @config.build([
    named({ "plugins": ["a"] }, "a"),
    named({ "plugins": ["b"] }, "b").with_key_policy(key("plugins"), Append),
  ])
  @expect.expect(
    config.origins(key("plugins")).map(origin => origin.source),
  ).to_equal(["a", "b"])
}

///|
test "law: provenance entries are never empty" {
  @expect.for_all(
    (input : (TreeCase, TreeCase, Bool)) => {
      let base = named_value(input.0.tree(), "base")
      let mut overlay = named_value(input.1.tree(), "overlay")
      if input.2 {
        overlay = overlay.with_policy(Append)
      }
      let config = @config.build([base, overlay])
      for record in config.provenance() {
        @expect.expect(record.1.is_empty()).to_be_false()
      }
    },
    count=200,
    max_size=30,
    max_shrinks=100,
    seed=4211,
  )
}

///|
fn named_value(value : @config.ConfigValue, name : String) -> @config.ConfigSource {
  @config.in_memory(value, name~) catch {
    error => abort(error.message())
  }
}

///|
test "Merge-by-key rejects a repeated key in one overlay list" {
  try
    @config.build([
      named({ "servers": [{ "name": "a", "port": 1 }] }, "base"),
      named(
        {
          "servers": [
            { "name": "b", "port": 2 },
            { "name": "b", "port": 3 },
          ],
        },
        "overlay",
      ).with_key_policy(key("servers"), MergeByKey("name")),
    ])
  catch {
    error => {
      guard error is MergeKey(key~, index~, source~) else {
        fail("wrong error")
      }
      @expect.expect(key.to_string()).to_equal("servers")
      @expect.expect(index).to_equal(1)
      @expect.expect(source).to_equal("overlay")
    }
  } noraise {
    _ => fail("expected MergeKey")
  }
}

///|
test "a list policy replacing a scalar keeps one origin" {
  let config = @config.build([
    named({ "plugins": "alone" }, "base"),
    named({ "plugins": ["b"] }, "overlay").with_key_policy(key("plugins"), Append),
  ])
  @expect.expect(
    config.origins(key("plugins")).map(origin => origin.source),
  ).to_equal(["overlay"])
}

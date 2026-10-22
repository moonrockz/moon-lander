///|
test "the scanner finds links without escape=true" {
  assert_eq(
    @site.unescaped_links(
      "@html.a(href=\"x\", \"A\")\n@html.a(href=\"y\", [text(\"(\")], escape=true)",
    ),
    [1],
  )
  assert_eq(
    @site.unescaped_links("@html.a(\n  href=\"a)b\",\n  escape=true,\n)"),
    [],
  )
  assert_eq(
    @site.unescaped_links("let x = 1\n\n@html.a(href=f(x), \"B\")"),
    [3],
  )
}

///|
test "only the own named argument of the link counts" {
  // Not text, not a nested call, not a nested link.
  assert_eq(
    @site.unescaped_links("@html.a(href=\"x\", \"escape=true\")"),
    [1],
  )
  assert_eq(
    @site.unescaped_links("@html.a(href=\"x\", [inner(escape=true)])"),
    [1],
  )
  assert_eq(
    @site.unescaped_links(
      "@html.a(href=\"x\", [@html.a(href=\"y\", \"C\", escape=true)])",
    ),
    [1],
  )
}

///|
test "a link nested in an escaped link is checked too" {
  assert_eq(
    @site.unescaped_links(
      "@html.a(\n  href=\"x\",\n  [@html.a(href=\"y\", \"C\")],\n  escape=true,\n)",
    ),
    [3],
  )
}

///|
test "call text in a string is not a call" {
  assert_eq(
    @site.unescaped_links(
      "@html.a(href=\"x\", \"see @html.a(href)\", escape=true)",
    ),
    [],
  )
}

///|
/// The `file:line` of each link without `escape=true` in the `.mbt` files of `dir`, relative to the
/// module directory, where `moon test` runs.
async fn unescaped_in(dir : String) -> Array[String] {
  let found = []
  for name in @fs.readdir(dir, sort=true) {
    if name.has_suffix(".mbt") {
      let file = "\{dir}/\{name}"
      for line in @site.unescaped_links(@fs.read_file(file).text()) {
        found.push("\{file}:\{line}")
      }
    }
  }
  found
}

///|
async test "island links skip Rabbita link capture" {
  // Add `escape=true` to each `@html.a` call that this test names: the islands have no router.
  assert_eq(unescaped_in("islands"), [])
}

///|
async test "Guard test" {
  assert_eq(unescaped_in("fixtures/link-guard"), [
    "fixtures/link-guard/unescaped.mbt:5",
  ])
}

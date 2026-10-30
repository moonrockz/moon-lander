///|
fn input(language : String, body : String, ordinal~ : Int = 1) -> @extensions.RenderInput {
  { source: "docs/example.md", route: "/docs/example/", base_path: "/moon-lander/", language, body, ordinal }
}

///|
test "Mermaid stays inline and diagram identifiers do not collide" {
  let registry = registry()
  let a = @extensions.render_fence(registry, input("mermaid", "graph LR\nA --> B"))
  let b = @extensions.render_fence(registry, input("mermaid", "graph LR\nA --> B", ordinal=2))
  guard a is Ok(a) && b is Ok(b) else { fail("valid diagrams failed") }
  assert_true(a.body_html.contains("<figure class=\"diagram\"><svg"))
  let first = @content.ids_in(a.body_html)
  let second = @content.ids_in(b.body_html)
  assert_true(!first.is_empty())
  assert_true(first.iter().all(id => !second.contains(id)))
  assert_true(a.body_html.contains("url(#lander-diagram-1-"))
}

///|
test "invalid diagrams name source and ordinal" {
  let result = @extensions.render_fence(registry(), input("mermaid", "gantt\ntitle unsupported", ordinal=3))
  guard result is Err(problems) else { fail("unsupported diagram succeeded") }
  assert_true(problems[0].render().contains("docs/example.md"))
  assert_true(problems[0].message.contains("diagram 3"))
}

///|
test "layers use the shared renderer and escape text" {
  let result = @extensions.render_fence(registry(), input("layers", "Overrides | --set x=<y>\nDefaults | code"))
  guard result is Ok(result) else { fail("valid layers failed") }
  assert_true(result.body_html.contains("<figure class=\"layer-stack\"><ol>"))
  assert_true(result.body_html.contains("&lt;y&gt;"))
  assert_eq(result.body_html.split("<li>").count(), 3)
}

///|
test "invalid layers name their source and ordinal" {
  let result = @extensions.render_fence(registry(), input("layers", "No separator", ordinal=4))
  guard result is Err(problems) else { fail("invalid layers succeeded") }
  assert_true(problems[0].render().contains("docs/example.md"))
  assert_true(problems[0].message.contains("layers block 4"))
}

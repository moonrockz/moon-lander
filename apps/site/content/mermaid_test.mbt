///|
test "diagram renders" {
  let pass = @content.render_mermaid_blocks(
    "a.md", "<p>x</p><pre><code class=\"language-mermaid\">graph LR\nA --&gt; B\n</code></pre><p>y</p>",
  )
  assert_true(pass.html.has_prefix("<p>x</p><figure class=\"diagram\"><svg"))
  assert_true(pass.html.has_suffix("</svg></figure><p>y</p>"))
  assert_false(pass.html.contains("<pre"))
  assert_eq(pass.problems, [])
}

///|
test "diagram does not render" {
  let pass = @content.render_mermaid_blocks(
    "docs/a.md", "<pre><code class=\"language-mermaid\">graph LR\nA --&gt; B\n</code></pre><pre><code class=\"language-mermaid\">gantt\ntitle x\n</code></pre>",
  )
  assert_eq(pass.problems.length(), 1)
  assert_true(
    pass.problems[0]
    .render()
    .has_prefix("docs/a.md: Mermaid diagram 2 does not render"),
  )
  assert_false(pass.html.contains("class=\"mermaid\""))
}

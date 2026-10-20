///|
fn render(source : String) -> String {
  let doc = @content.render_markdown("docs/a.md", source) catch {
    _ => abort("does not render")
  }
  @content.render_callouts(doc.html)
}

///|
test "warning callout" {
  inspect(
    render("> [!WARNING]\n> Do not do it.\n> More.\n"),
    content=(
      #|<aside class="callout warning"><p class="callout-label">Warning</p><p>Do not do it.
      #|More.</p>
      #|</aside>
      #|
    ),
  )
}

///|
test "each alert kind has its label" {
  for kind in [
    ("NOTE", "Note"),
    ("TIP", "Tip"),
    ("IMPORTANT", "Important"),
    ("WARNING", "Warning"),
    ("CAUTION", "Caution"),
  ] {
    let html = render("> [!\{kind.0}]\n> Text.\n")
    assert_true(
      html.contains(
        "<aside class=\"callout \{kind.0.to_lower()}\"><p class=\"callout-label\">\{kind.1}</p>",
      ),
      msg=html,
    )
  }
}

///|
test "a plain block quote stays a block quote" {
  inspect(
    render("> plain quote\n\n> [!UNKNOWN]\n> x\n"),
    content=(
      #|<blockquote>
      #|<p>plain quote</p>
      #|</blockquote>
      #|<blockquote>
      #|<p>[!UNKNOWN]
      #|x</p>
      #|</blockquote>
      #|
    ),
  )
}

///|
test "a callout keeps a nested block quote" {
  let html = render("> [!NOTE]\n> Outer.\n>\n> > Inner.\n")
  assert_true(html.has_prefix("<aside class=\"callout note\">"), msg=html)
  assert_true(html.contains("<blockquote>\n<p>Inner.</p>\n</blockquote>"))
  assert_true(html.has_suffix("</aside>\n"), msg=html)
}

///|
test "layer stack" {
  let doc = @content.render_markdown(
    "docs/a.md", "```layers\nOverrides | --set key=value\n\nDefaults | code\n```\n",
  ) catch {
    _ => abort("does not render")
  }
  let pass = @content.render_layers("docs/a.md", doc.html)
  assert_eq(pass.problems, [])
  inspect(
    pass.html,
    content=(
      #|<figure class="layer-stack"><ol><li><span class="layer-name">Overrides</span><span class="layer-detail">--set key=value</span></li><li><span class="layer-name">Defaults</span><span class="layer-detail">code</span></li></ol></figure>
      #|
    ),
  )
}

///|
test "bad layer line" {
  let pass = @content.render_layers(
    "docs/a.md", "<pre><code class=\"language-layers\">Overrides\nDefaults | code\n</code></pre>",
  )
  assert_eq(pass.problems.map(p => p.render()), [
    "docs/a.md: layers block 1: line `Overrides` must have the form `name | detail`",
  ])
}

///|
test "untested example in docs" {
  let problems = @content.check_moonbit_fences(
    "docs/a.md",
    "# A\n\n```moonbit\nlet x = 1\n```\n\n```mbt\nlet y = 2\n```\n",
    first_line=4,
  )
  assert_eq(problems.map(p => p.render()), [
    "docs/a.md:6: a `moonbit` fence outside a `.mbt.md` file is not compiled: write ```moonbit notest, or move the example to a tested `.mbt.md` file",
    "docs/a.md:10: a `mbt` fence outside a `.mbt.md` file is not compiled: write ```mbt notest, or move the example to a tested `.mbt.md` file",
  ])
}

///|
test "example of a proposed API" {
  assert_eq(
    @content.check_moonbit_fences(
      "docs/a.md", "```moonbit notest\nlet x = 1\n```\n\n~~~toml\n```moonbit\n~~~\n",
    ),
    [],
  )
}

///|
test "a fence inside a block quote, a callout or a list is checked" {
  let problems = @content.check_moonbit_fences(
    "docs/a.md", "> [!NOTE]\n> ```moonbit\n> let x = 1\n> ```\n\n- Item:\n\n  ```mbt\n  let y = 2\n  ```\n\n1. Step\n   ```moonbit notest\n   let z = 3\n   ```\n",
  )
  assert_eq(problems.map(p => p.line), [2, 8])
}

///|
fn output(html : String, text : String) -> @extensions.RenderOutput {
  { body_html: html, text, headings: [], assets: [], problems: [] }
}

///|
/// Namespace each renderer-owned SVG identifier, including marker and link references.
fn prefix_ids(svg : String, ordinal : Int) -> String {
  let ids = []
  let mut rest = svg[:]
  while rest.find("id=\"") is Some(start) {
    let after = rest[start + 4:]
    guard after.find("\"") is Some(end) else { break }
    ids.push(after[:end].to_owned())
    rest = after[end + 1:]
  }
  let mut result = svg
  for id in ids {
    let name = "lander-diagram-\{ordinal}-\{id}"
    result = result
      .replace_all(old="id=\"\{id}\"", new="id=\"\{name}\"")
      .replace_all(old="url(#\{id})", new="url(#\{name})")
      .replace_all(old="href=\"#\{id}\"", new="href=\"#\{name}\"")
  }
  result
}

///|
fn mermaid(input : @extensions.RenderInput) -> Result[@extensions.RenderOutput, @extensions.AdapterError] {
  let svg = @mermaid.render_mermaid(input.body) catch {
    error => return Err({ stage: "render", message: "Mermaid diagram \{input.ordinal} does not render: \{error}" })
  }
  Ok(output("<figure class=\"diagram\">\{prefix_ids(svg, input.ordinal)}</figure>", input.body))
}

///|
fn layers(input : @extensions.RenderInput) -> Result[@extensions.RenderOutput, @extensions.AdapterError] {
  let rendered = @content.render_layers(input.source, "<pre><code class=\"language-layers\">\{@content.escape(input.body)}</code></pre>")
  if rendered.problems is [problem, ..] {
    return Err({ stage: "render", message: problem.message.replace_all(old="layers block 1", new="layers block \{input.ordinal}") })
  }
  Ok(output(rendered.html, input.body))
}

///|
/// The two consumer-owned fence renderers. Telescope supplies the remaining site behavior.
pub fn registry() -> @extensions.Registry {
  { pages: [], islands: [], fences: [
    { id: "moon-lander-mermaid", contract_version: 1, labels: ["mermaid"], render: mermaid },
    { id: "moon-lander-layers", contract_version: 1, labels: ["layers"], render: layers },
  ] }
}

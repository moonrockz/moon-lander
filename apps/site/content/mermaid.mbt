///|
/// The result of the Mermaid pass over one page.
pub(all) struct MermaidPass {
  html : String
  /// One problem for each diagram that does not render.
  problems : Array[@model.Problem]
}

///|
let mermaid_open : String = "<pre><code class=\"language-mermaid\">"

///|
let mermaid_close : String = "</code></pre>"

///|
/// Replace each Mermaid code block with an inline SVG in a `figure.diagram`. A diagram that does
/// not render gives a problem with the file and the diagram number. There is no client renderer.
pub fn render_mermaid_blocks(file : String, html : String) -> MermaidPass {
  let out = StringBuilder()
  let problems = []
  let mut rest = html[:]
  let mut index = 0
  while rest.find(mermaid_open) is Some(start) {
    let body = rest[start + mermaid_open.length():]
    guard body.find(mermaid_close) is Some(end) else { break }
    index += 1
    out.write_view(rest[:start])
    let svg = @mermaid.render_mermaid(unescape(body[:end].to_owned())) catch {
      error => {
        problems.push(
          @model.problem(file, "Mermaid diagram \{index} does not render: \{error}"),
        )
        ""
      }
    }
    out.write_string("<figure class=\"diagram\">\{svg}</figure>")
    rest = body[end + mermaid_close.length():]
  }
  out.write_view(rest)
  { html: out.to_string(), problems }
}

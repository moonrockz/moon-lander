///|
/// The GitHub alert kinds and their labels.
let callout_kinds : Array[(String, String)] = [
  ("NOTE", "Note"),
  ("TIP", "Tip"),
  ("IMPORTANT", "Important"),
  ("WARNING", "Warning"),
  ("CAUTION", "Caution"),
]

///|
let quote_open : String = "<blockquote>\n<p>"

///|
/// The index of the `</blockquote>` that closes the block quote whose content starts at 0 of `text`.
fn quote_end(text : StringView) -> Int? {
  let mut depth = 1
  let mut i = 0
  while i < text.length() {
    let rest = text[i:]
    if rest.has_prefix("<blockquote>") {
      depth += 1
      i += 12
    } else if rest.has_prefix("</blockquote>") {
      depth -= 1
      if depth == 0 {
        return Some(i)
      }
      i += 13
    } else {
      i += 1
    }
  }
  None
}

///|
/// Turn each block quote whose first line is `[!NOTE]`, `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]` or
/// `[!CAUTION]` into `aside.callout.<kind>` with a label. Other block quotes stay as they are.
pub fn render_callouts(html : String) -> String {
  let out = StringBuilder()
  let mut rest = html[:]
  while rest.find(quote_open) is Some(start) {
    let inner = rest[start + quote_open.length():]
    let kind = callout_kinds.iter().find_first(k => inner.has_prefix("[!\{k.0}]"))
    guard kind is Some((name, label)) && quote_end(inner) is Some(end) else {
      out.write_view(rest[:start + quote_open.length()])
      rest = inner
      continue
    }
    let marker = "[!\{name}]"
    let body = inner[marker.length():end].to_owned()
    let body = if body.has_prefix("\n") { body[1:].to_owned() } else { body }
    // The marker had its own line: the first paragraph now starts with the text after it.
    let body = if body.has_prefix("</p>\n") {
      body[5:].to_owned()
    } else {
      "<p>" + body
    }
    out.write_view(rest[:start])
    out.write_string(
      "<aside class=\"callout \{name.to_lower()}\"><p class=\"callout-label\">\{label}</p>\{render_callouts(body)}</aside>",
    )
    rest = inner[end + "</blockquote>".length():]
  }
  out.write_view(rest)
  out.to_string()
}

///|
/// The result of the layer-stack pass over one page.
pub(all) struct LayersPass {
  html : String
  problems : Array[@model.Problem]
}

///|
let layers_open : String = "<pre><code class=\"language-layers\">"

///|
/// Replace each `layers` code block with `figure.layer-stack`: an ordered list with one layer for each
/// non-empty `name | detail` line, the first line at the top. A line without `|` gives a problem.
pub fn render_layers(file : String, html : String) -> LayersPass {
  let out = StringBuilder()
  let problems = []
  let mut rest = html[:]
  let mut index = 0
  while rest.find(layers_open) is Some(start) {
    let body = rest[start + layers_open.length():]
    guard body.find("</code></pre>") is Some(end) else { break }
    index += 1
    out.write_view(rest[:start])
    let items = StringBuilder()
    for line in unescape(body[:end].to_owned()).split("\n") {
      let line = line.trim().to_owned()
      if line == "" {
        continue
      }
      guard line.find("|") is Some(bar) else {
        problems.push(
          @model.problem(
            file,
            "layers block \{index}: line `\{line}` must have the form `name | detail`",
          ),
        )
        continue
      }
      let name = escape(line[:bar].trim().to_owned())
      let detail = escape(line[bar + 1:].trim().to_owned())
      items.write_string(
        "<li><span class=\"layer-name\">\{name}</span><span class=\"layer-detail\">\{detail}</span></li>",
      )
    }
    out.write_string(
      "<figure class=\"layer-stack\"><ol>\{items.to_string()}</ol></figure>",
    )
    rest = body[end + "</code></pre>".length():]
  }
  out.write_view(rest)
  { html: out.to_string(), problems }
}

///|
/// The length of a list item marker at the start of `text`, such as `- `, `* `, `+ `, `1. ` or `1) `,
/// or 0.
fn list_marker(text : String) -> Int {
  if text.has_prefix("- ") || text.has_prefix("* ") || text.has_prefix("+ ") {
    return 2
  }
  let mut n = 0
  while n < text.length() && text[n] >= '0' && text[n] <= '9' {
    n += 1
  }
  if n > 0 &&
    n + 1 < text.length() &&
    (text[n] == '.' || text[n] == ')') &&
    text[n + 1] == ' ' {
    n + 2
  } else {
    0
  }
}

///|
/// `line` without its leading white space, block quote markers and list item markers, so a fence
/// inside a block quote, a callout or a list item is found too.
fn without_containers(line : String) -> String {
  let mut rest = line
  while true {
    let trimmed = rest.trim_start(chars=" \t").to_owned()
    if trimmed.has_prefix(">") {
      rest = trimmed[1:].to_owned()
    } else if list_marker(trimmed) is n && n > 0 {
      rest = trimmed[n:].to_owned()
    } else {
      return trimmed
    }
  }
  rest
}

///|
/// Check the MoonBit fences of a Markdown source that `moon test` does not compile: each fence whose
/// language is `moonbit` or `mbt` must have the word `notest` after the language. `first_line` is the
/// line number of the first line of `source` in the file.
pub fn check_moonbit_fences(
  file : String,
  source : String,
  first_line~ : Int = 1,
) -> Array[@model.Problem] {
  let problems = []
  let mut fence : String? = None
  for i, line in source.split("\n").collect() {
    let trimmed = without_containers(line.to_owned())
    let marker = if trimmed.has_prefix("```") {
      "```"
    } else if trimmed.has_prefix("~~~") {
      "~~~"
    } else {
      ""
    }
    if marker == "" {
      continue
    }
    match fence {
      Some(open) => {
        // A closing fence has only fence characters, at least as many as the opening fence.
        let closing = trimmed.trim_end().to_owned()
        if closing.length() >= open.length() &&
          closing.iter().all(c => c.to_int() == open.code_unit_at(0).to_int()) {
          fence = None
        }
      }
      None => {
        let mut n = 0
        while n < trimmed.length() && trimmed[n] == trimmed[0] {
          n += 1
        }
        fence = Some(trimmed[:n].to_owned())
        let words = trimmed[n:]
          .trim()
          .split(" ")
          .filter(w => w != "")
          .map(w => w.to_owned())
          .collect()
        if words is [lang, ..] &&
          (lang == "moonbit" || lang == "mbt") &&
          !words[1:].contains("notest") {
          problems.push(
            @model.problem(
              file,
              "a `\{lang}` fence outside a `.mbt.md` file is not compiled: write ```\{lang} notest, or move the example to a tested `.mbt.md` file",
              line=first_line + i,
            ),
          )
        }
      }
    }
  }
  problems
}

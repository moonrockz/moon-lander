///|
// Telescope generates /api/ but omits it from content route resolution.
// Remove this marker/pass once a pinned release accepts ordinary /api/ links.
let api_index_marker : String = "moon-lander-route://api-index"

///|
fn resolve_api_index(
  file : String,
  html : String,
  base : @policy.BasePath,
) -> String raise @model.Invalid {
  let problems = []
  let result = @content.map_urls(html, url => {
    if url == api_index_marker {
      base.text() + "api/"
    } else if url.has_prefix("moon-lander-route://") {
      problems.push(@model.problem(file, "unknown site compatibility route: \{url}"))
      url
    } else {
      url
    }
  })
  guard problems.is_empty() else { raise @model.Invalid(problems) }
  result
}

///|
/// Resolve the one consumer marker before the completed build is returned.
async fn finish_api_links(
  out : String,
  base : @policy.BasePath,
  prefix~ : String = "",
) -> Unit {
  let directory = if prefix == "" { out } else { "\{out}/\{prefix}" }
  for name in @fs.readdir(directory) {
    let rel = if prefix == "" { name } else { "\{prefix}/\{name}" }
    let file = "\{out}/\{rel}"
    match @fs.kind(file, follow_symlink=false) {
      Directory => finish_api_links(out, base, prefix=rel)
      Regular if name.has_suffix(".html") => {
        let html = @fs.read_file(file).text()
        if html.contains(api_index_marker) {
          guard @fs.exists(out + "/api/index.html") &&
            @fs.kind(out + "/api/index.html", follow_symlink=false) is Regular else {
            raise @model.Invalid([@model.problem(rel, "API index compatibility link requires generated api/index.html")])
          }
        }
        let result = resolve_api_index(rel, html, base)
        if result != html {
          @fs.write_file(file, result, create_mode=CreateOrTruncate)
        }
      }
      _ => ()
    }
  }
}

///|
pub(all) struct SearchEntry {
  route : String
  title : String
  section : String
  summary : String
  headings : Array[String]
  text : String
} derive(Eq, Debug)

///|
pub extend SearchEntry with Eq::{equal, not_equal}

///|
pub extend SearchEntry with @debug.Debug::{to_repr}

///|
pub fn SearchEntry::to_json(self : SearchEntry) -> Json {
  {
    "route": Json(self.route),
    "title": Json(self.title),
    "section": Json(self.section),
    "summary": Json(self.summary),
    "headings": Json(self.headings),
    "text": Json(self.text),
  }
}

///|
pub fn SearchEntry::from_json(json : Json) -> SearchEntry? {
  guard json is Object(f) else { return None }
  let text = fn(key : String) -> String? {
    if f.get(key) is Some(String(value)) {
      Some(value)
    } else {
      None
    }
  }
  guard text("route") is Some(route) &&
    text("title") is Some(title) &&
    text("section") is Some(section) &&
    text("summary") is Some(summary) &&
    text("text") is Some(body) &&
    f.get("headings") is Some(Array(items)) else {
    return None
  }
  let headings = items.filter_map(item => {
    if item is String(h) {
      Some(h)
    } else {
      None
    }
  })
  Some({ route, title, section, summary, headings, text: body, })
}

///|
fn words(text : String) -> Array[String] {
  let out = []
  let current = StringBuilder()
  for c in text.to_lower() {
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c.to_int() > 127 {
      current.write_char(c)
    } else if current.to_string() != "" {
      out.push(current.to_string())
      current.reset()
    }
  }
  if current.to_string() != "" {
    out.push(current.to_string())
  }
  out
}

///|
fn prefix_hit(haystack : Array[String], token : String) -> Bool {
  haystack.iter().any(w => w.has_prefix(token))
}

///|
/// Rank entries for a query. Every query token must prefix a word of the entry.
/// A token scores 3 in the title, 2 in a heading, 1 in the text. Ties keep index order.
pub fn search(
  entries : Array[SearchEntry],
  query : String,
  limit~ : Int32 = 10,
) -> Array[SearchEntry] {
  let tokens = words(query)
  if tokens.is_empty() {
    return []
  }
  let scored = []
  for i, e in entries {
    let title = words(e.title)
    let headings = words(e.headings.join(" "))
    let text = words(e.text)
    let mut score = 0
    let mut all = true
    for t in tokens {
      if prefix_hit(title, t) {
        score += 3
      } else if prefix_hit(headings, t) {
        score += 2
      } else if prefix_hit(text, t) {
        score += 1
      } else {
        all = false
        break
      }
    }
    if all {
      scored.push((score, i))
    }
  }
  scored.sort_by((a, b) => if a.0 != b.0 { b.0 - a.0 } else { a.1 - b.1 })
  scored.iter().take(limit).map(s => entries[s.1]).collect()
}

///|
/// The entry of one row that the search island reads from `search-index.json`:
/// `[route, title, section, summary, text, ...headings]`. A row with fewer than five fields gives
/// `None`. The island reads the index with `JSON.parse`, not `@json`, to keep its bundle small
/// (design D11), so it passes plain text fields.
pub fn SearchEntry::from_fields(fields : Array[String]) -> SearchEntry? {
  guard fields.length() >= 5 else { return None }
  Some({
    route: fields[0],
    title: fields[1],
    section: fields[2],
    summary: fields[3],
    text: fields[4],
    headings: fields[5:].to_owned(),
  })
}

///|
/// The selected result after the key `key` in a list of `count` results, when `selected` is
/// selected. `ArrowDown` and `ArrowUp` move the selection and stay in the list. Another key keeps it.
pub fn move_selection(selected : Int, count : Int, key : String) -> Int {
  match key {
    "ArrowDown" => (selected + 1).min(count - 1).max(0)
    "ArrowUp" => (selected - 1).max(0)
    _ => selected
  }
}

///|
/// The URL of the result `entry` on a site with the base path `base`. The route starts with `/`, and
/// can end with an anchor, for example `/api/moonrockz/notebooks/#CellKind`.
pub fn result_url(base : String, entry : SearchEntry) -> String {
  base + entry.route[1:].to_owned()
}

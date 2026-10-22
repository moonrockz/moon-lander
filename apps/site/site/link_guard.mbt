///|
/// The call that the link guard looks for.
let link_call : Array[Char] = "@html.a(".to_array()

///|
/// The lines of the `@html.a(...)` calls in the MoonBit text `source` that do not pass
/// `escape=true` as their own named argument. Text in strings and arguments of nested calls do not
/// count.
///
/// Rabbita prevents the default action of each link click that it renders and sends the URL to the
/// router of the app. The islands have no router, so a link without `escape=true` does nothing when a
/// user clicks it (design D12). The server-rendered views are not checked: Rabbita does not run on
/// those pages.
pub fn unescaped_links(source : String) -> Array[Int] {
  let chars = source.to_array()
  let lines = []
  let mut at = find_chars(chars, link_call, 0)
  while at >= 0 {
    let mut depth = 0
    let mut end = at + link_call.length() - 1
    let mut quoted = false
    // The text of the call at its own argument level, without strings.
    let own = StringBuilder()
    while end < chars.length() {
      let c = chars[end]
      if quoted {
        if c == '\\' {
          end += 1
        } else if c == '"' {
          quoted = false
        }
      } else if c == '"' {
        quoted = true
      } else if c == '(' || c == '[' || c == '{' {
        depth += 1
      } else if c == ')' || c == ']' || c == '}' {
        depth -= 1
        if depth == 0 {
          break
        }
        if depth == 1 {
          own.write_char(c)
        }
      } else if depth == 1 {
        own.write_char(c)
      }
      end += 1
    }
    if !has_escape_true(own.to_string().to_array()) {
      lines.push(line_at(chars, at))
    }
    at = find_chars(chars, link_call, end)
  }
  lines
}

///|
/// The index of the first `pattern` in `chars` at or after `from`, or -1.
fn find_chars(chars : Array[Char], pattern : Array[Char], from : Int) -> Int {
  let last = chars.length() - pattern.length()
  for i in from.max(0)..=last {
    let mut same = true
    for j, p in pattern {
      if chars[i + j] != p {
        same = false
        break
      }
    }
    if same {
      return i
    }
  }
  -1
}

///|
/// The line number of the index `at` in `chars`, from 1.
fn line_at(chars : Array[Char], at : Int) -> Int {
  let mut line = 1
  for i in 0..<at {
    if chars[i] == '\n' {
      line += 1
    }
  }
  line
}

///|
fn is_word_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

///|
/// Whether `own` has the argument `escape = true`: the word `escape` at the start or after a space
/// or a comma, then `=`, then the word `true`, with optional spaces between them.
fn has_escape_true(own : Array[Char]) -> Bool {
  let name = "escape".to_array()
  let value = "true".to_array()
  let mut at = find_chars(own, name, 0)
  while at >= 0 {
    let starts = at == 0 || is_space(own[at - 1]) || own[at - 1] == ','
    let mut i = at + name.length()
    while i < own.length() && is_space(own[i]) {
      i += 1
    }
    if starts && i < own.length() && own[i] == '=' {
      i += 1
      while i < own.length() && is_space(own[i]) {
        i += 1
      }
      let end = i + value.length()
      if find_chars(own, value, i) == i &&
        (end >= own.length() || !is_word_char(own[end])) {
        return true
      }
    }
    at = find_chars(own, name, at + 1)
  }
  false
}

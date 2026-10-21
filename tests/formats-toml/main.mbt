///|
fn main {
  let formats = @formats.formats()
  for format in formats {
    println(format.name + ":" + format.extensions.join(","))
  }
  // Keep every selected parser reachable with exactly the same application.
  for format in formats {
    let text = if format.name == "TOML" {
      "answer = 42"
    } else if format.name == "YAML" {
      "answer: 42"
    } else {
      "{answer: 42}"
    }
    let value = (format.parse)(text, "fixture") catch {
      error => abort(error.message())
    }
    println(@debug.Debug::to_repr(value.to_ion()))
  }
}

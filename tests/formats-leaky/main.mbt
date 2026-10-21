///|
fn main {
  let formats = [..@formats.formats(), @yaml.format()]
  for format in formats {
    let text = if format.name == "TOML" { "answer = 42" } else { "answer: 42" }
    let value = (format.parse)(text, "fixture") catch {
      error => abort(error.message())
    }
    println(@debug.Debug::to_repr(value.to_ion()))
  }
}

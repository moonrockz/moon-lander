///|
/// The parts as text: `"..."` for literal text and `{Name}` for a hole.
fn show_parts(template : String) -> String {
  parse_template(template)
  .map(part => match part {
    Text(text) => text.escape()
    Hole(name) => "{\{name}}"
  })
  .join(" ")
}

///|
test "one hole" {
  inspect(show_parts("Disk {Name} is low"), content=(
    #|"Disk " {Name} " is low"
  ))
}

///|
test "two holes and a hole at each end" {
  inspect(show_parts("Loaded {Count} files from {Path}"), content=(
    #|"Loaded " {Count} " files from " {Path}
  ))
  inspect(show_parts("{A}{B_2}"), content="{A} {B_2}")
}

///|
test "doubled braces are literal braces" {
  inspect(show_parts("Use {{Name}} for {Value}"), content=(
    #|"Use {Name} for " {Value}
  ))
}

///|
test "malformed holes are literal text" {
  inspect(show_parts("Value {Name"), content=(
    #|"Value {Name"
  ))
  inspect(show_parts("Empty {} here"), content=(
    #|"Empty {} here"
  ))
  inspect(show_parts("A {first name} B"), content=(
    #|"A {first name} B"
  ))
  inspect(show_parts("Close } only"), content=(
    #|"Close } only"
  ))
  inspect(show_parts(""), content="")
}

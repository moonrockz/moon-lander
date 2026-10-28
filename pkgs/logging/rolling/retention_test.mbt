///|
/// The set of stem `acme` in text format with a daily policy.
fn daily_set() -> @rolling.FileSet raise {
  @rolling.FileSet::new(@rolling.LogFileStem::parse("acme"), Text, Daily)
}

///|
/// Keep the newest `count` files.
fn keep(count : Int) -> @rolling.Retention raise {
  KeepNewest(@rolling.RetainedFileCount::count(count))
}

///|
/// A listing of regular files of size 1 with the names `names`.
fn files(names : Array[String]) -> Array[@rolling.ListedFile] {
  names.map(name => { name, size: 1L, regular: true })
}

///|
test "retention keeps the newest files including the active file" {
  let set = daily_set()
  let listing = files([
    "acme-20261027_001.log", "acme-20261025.log", "acme-20261028.log", "acme-20261027.log",
    "acme-20261026.log",
  ])
  let active = set.parse_name("acme-20261028.log").unwrap()
  inspect(set.retention(keep(3), listing, active).join(" "), content=(
    #|acme-20261025.log acme-20261026.log
  ))
  inspect(set.retention(keep(1), listing, active).join(" "), content=(
    #|acme-20261025.log acme-20261026.log acme-20261027.log acme-20261027_001.log
  ))
  assert_eq(set.retention(keep(5), listing, active), [])
  assert_eq(set.retention(keep(31), listing, active), [])
  assert_eq(set.retention(KeepAll, listing, active), [])
}

///|
test "retention counts the active file when the listing does not have it" {
  let set = daily_set()
  let active = set.parse_name("acme-20261029.log").unwrap()
  let listing = files(["acme-20261027.log", "acme-20261028.log"])
  inspect(set.retention(keep(2), listing, active).join(" "), content=(
    #|acme-20261027.log
  ))
}

///|
test "retention never deletes the active file, even when it is not newest" {
  let set = daily_set()
  let active = set.parse_name("acme-20261027.log").unwrap()
  let listing = files(["acme-20261027.log", "acme-20261028.log", "acme-20261026.log"])
  inspect(set.retention(keep(2), listing, active).join(" "), content=(
    #|acme-20261026.log
  ))
}

///|
test "retention sorts by sequence number, not by name text" {
  let set = daily_set()
  let active = set.parse_name("acme-20261027_1001.log").unwrap()
  let listing = files([
    "acme-20261027_1000.log", "acme-20261027_999.log", "acme-20261027_998.log",
  ])
  inspect(set.retention(keep(3), listing, active).join(" "), content=(
    #|acme-20261027_998.log
  ))
}

///|
test "retention deletes only regular files of the complete owned form" {
  let set = daily_set()
  let active = set.parse_name("acme-20261028.log").unwrap()
  let listing = files([
    "acme-old.log", "acme-20261027.log.bak", "acmex.log", "other-20261020.log", "acme-20261020.jsonl",
    "acme.log.lock", "acme.log", "notes.txt",
  ])
  listing.push({ name: "acme-20261021.log", size: 0L, regular: false })
  listing.push({ name: "acme-20261022.log", size: 1L, regular: false })
  listing.push({ name: "acme-20261023.log", size: 1L, regular: true })
  listing.push({ name: "acme-20261023.log", size: 1L, regular: true })
  inspect(set.retention(keep(1), listing, active).join(" "), content=(
    #|acme-20261023.log
  ))
}

///|
test "two formats of one stem keep their own files" {
  let stem = @rolling.LogFileStem::parse("acme")
  let text = @rolling.FileSet::new(stem, Text, Daily)
  let json = @rolling.FileSet::new(stem, JsonLines, Daily)
  let listing = files([
    "acme-20261026.log", "acme-20261027.log", "acme-20261026.jsonl", "acme-20261027.jsonl",
  ])
  let text_active = text.parse_name("acme-20261027.log").unwrap()
  let json_active = json.parse_name("acme-20261027.jsonl").unwrap()
  assert_eq(text.retention(keep(1), listing, text_active), ["acme-20261026.log"])
  assert_eq(json.retention(keep(1), listing, json_active), ["acme-20261026.jsonl"])
}

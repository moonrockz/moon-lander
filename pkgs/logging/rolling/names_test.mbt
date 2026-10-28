///|
/// The file set of `stem` in `format` with `policy`.
fn file_set(
  stem : String,
  format : @rolling.FileFormat,
  policy : @rolling.RollingPolicy,
) -> @rolling.FileSet raise {
  @rolling.FileSet::new(@rolling.LogFileStem::parse(stem), format, policy)
}

///|
/// The owned name of `text` in `set`, as text, or `"-"` when it is not owned.
fn owned(set : @rolling.FileSet, text : String) -> String {
  match set.parse_name(text) {
    Some(name) => {
      let day = match name.epoch_day() {
        Some(day) => "Some(\{day})"
        None => "None"
      }
      "\{name} day=\{day} seq=\{name.sequence()}"
    }
    None => "-"
  }
}

///|
test "dated names parse with their day and sequence" {
  let set = file_set("acme", Text, Daily)
  inspect(owned(set, "acme-20261027.log"), content=(
    #|acme-20261027.log day=Some(20753) seq=0
  ))
  inspect(owned(set, "acme-20261027_001.log"), content=(
    #|acme-20261027_001.log day=Some(20753) seq=1
  ))
  inspect(owned(set, "acme-20261027_999.log"), content=(
    #|acme-20261027_999.log day=Some(20753) seq=999
  ))
  inspect(owned(set, "acme-20261027_1000.log"), content=(
    #|acme-20261027_1000.log day=Some(20753) seq=1000
  ))
  inspect(owned(set, "acme-19700101.log"), content=(
    #|acme-19700101.log day=Some(0) seq=0
  ))
  inspect(owned(set, "acme-99991231.log"), content=(
    #|acme-99991231.log day=Some(2932896) seq=0
  ))
  inspect(owned(set, "acme-20240229.log"), content=(
    #|acme-20240229.log day=Some(19782) seq=0
  ))
}

///|
test "names without a date belong to a size-only set" {
  let set = file_set("acme", JsonLines, Size(@rolling.FileByteLimit::default()))
  inspect(owned(set, "acme.jsonl"), content="acme.jsonl day=None seq=0")
  inspect(owned(set, "acme_001.jsonl"), content="acme_001.jsonl day=None seq=1")
  inspect(owned(set, "acme_2147483647.jsonl"), content=(
    #|acme_2147483647.jsonl day=None seq=2147483647
  ))
  inspect(owned(set, "acme-20261027.jsonl"), content="-")
  inspect(owned(set, "acme.log"), content="-")
}

///|
test "names with a similar form are not owned" {
  let set = file_set("acme", Text, DailyAndSize(@rolling.FileByteLimit::default()))
  for name in [
    "acme-old.log", "acme-20261027.log.bak", "acmex.log", "acme.log", "acme_001.log",
    "other-20261027.log", "ACME-20261027.log", "acme-20261027.jsonl", "acme.log.lock",
    set.marker_name(), "acme-2026102.log", "acme-202610271.log", "acme-20260231.log",
    "acme-20261301.log", "acme-20261000.log", "acme-19691231.log", "acme-20230229.log",
    "acme-20261027_.log", "acme-20261027_000.log", "acme-20261027_01.log", "acme-20261027_0001.log",
    "acme-20261027_0999.log", "acme-20261027_2147483648.log", "acme-20261027_99999999999.log",
    "acme-20261027_001_001.log", "acme-20261027-001.log", "acme-20261027.", "acme-20261027",
    "acme", "", "acme-20261027.LOG", "acme-+0261027.log",
  ] {
    assert_eq(owned(set, name), "-")
  }
}

///|
test "the marker name has the stem and the format" {
  assert_eq(file_set("acme", Text, Daily).marker_name(), "acme.log.lock")
  assert_eq(
    file_set("acme", JsonLines, Size(@rolling.FileByteLimit::default())).marker_name(),
    "acme.jsonl.lock",
  )
}

///|
test "names of one set sort by day and then by sequence" {
  let set = file_set("acme", Text, Daily)
  let names = [
    "acme-20261028.log", "acme-20261027_1000.log", "acme-20261027_999.log", "acme-20261027.log",
  ].map(text => set.parse_name(text).unwrap())
  names.sort()
  inspect(names.map(name => name.to_string()).join(" "), content=(
    #|acme-20261027.log acme-20261027_999.log acme-20261027_1000.log acme-20261028.log
  ))
}

///|
/// The time `millis` milliseconds after the start of 2026-10-27 UTC, plus
/// `days` days.
fn on(days : Int64, millis? : Int64 = 0L) -> @formatting.LogTimestamp raise {
  @formatting.LogTimestamp::from_epoch_millis(
    1793059200000L + days * 86400000L + millis,
  )
}

///|
/// A regular file of the listing.
fn regular(name : String, size : Int64) -> @rolling.ListedFile {
  { name, size, regular: true }
}

///|
/// A set of stem `acme` in text format with `policy`.
fn acme(policy : @rolling.RollingPolicy) -> @rolling.FileSet raise {
  @rolling.FileSet::new(@rolling.LogFileStem::parse("acme"), Text, policy)
}

///|
/// The plan as short text: the action and the file name.
fn show_plan(plan : @rolling.FilePlan) -> String {
  match plan {
    Append(name) => "append \{name}"
    Open(name, existing_size~) => "open \{name} at \{existing_size}"
    Roll(name) => "roll \{name}"
  }
}

///|
/// Do the action of `plan` for a record of `bytes` bytes, as an adapter does
/// after its I/O succeeds.
fn apply(
  state : @rolling.RollingState,
  plan : @rolling.FilePlan,
  bytes : Int64,
) -> @rolling.RollingState {
  let opened = match plan {
    Append(_) => state
    Open(name, existing_size~) => state.opened(name, existing_size)
    Roll(name) => state.opened(name, 0L)
  }
  opened.wrote(bytes)
}

///|
/// Write records of the sizes `sizes` at `now` from `state`, and give the plans
/// as text and the last state.
fn write_all(
  state : @rolling.RollingState,
  now : @formatting.LogTimestamp,
  sizes : Array[Int64],
) -> (String, @rolling.RollingState) raise {
  let plans = []
  let mut current = state
  for size in sizes {
    let plan = current.plan(now, size, [])
    plans.push(show_plan(plan))
    current = apply(current, plan, size)
  }
  (plans.join("\n"), current)
}

///|
test "the first record opens the first file of the day" {
  let state = @rolling.RollingState::new(acme(@rolling.RollingPolicy::default()))
  inspect(show_plan(state.plan(on(0L), 10L, [])), content=(
    #|open acme-20261027.log at 0
  ))
  let size_only = @rolling.RollingState::new(
    acme(Size(@rolling.FileByteLimit::default())),
  )
  inspect(show_plan(size_only.plan(on(0L), 10L, [])), content="open acme.log at 0")
}

///|
test "an exact fit appends and one byte over rolls" {
  let limit = @rolling.FileByteLimit::bytes(100L)
  let state = @rolling.RollingState::new(acme(DailyAndSize(limit)))
  let (plans, last) = write_all(state, on(0L), [60L, 40L, 1L])
  inspect(plans, content=(
    #|open acme-20261027.log at 0
    #|append acme-20261027.log
    #|roll acme-20261027_001.log
  ))
  assert_eq(last.size(), 1L)
  let (over, _) = write_all(state, on(0L), [60L, 41L])
  inspect(over, content=(
    #|open acme-20261027.log at 0
    #|roll acme-20261027_001.log
  ))
}

///|
test "a record larger than the limit goes whole into an empty file" {
  let limit = @rolling.FileByteLimit::bytes(10L)
  let state = @rolling.RollingState::new(acme(Size(limit)))
  let (plans, last) = write_all(state, on(0L), [25L, 1L, 25L, 25L])
  inspect(plans, content=(
    #|open acme.log at 0
    #|roll acme_001.log
    #|roll acme_002.log
    #|roll acme_003.log
  ))
  assert_eq(last.size(), 25L)
}

///|
test "multibyte text counts UTF-8 bytes" {
  let record = "é✓😀\n"
  let bytes = @formatting.utf8_length(record)
  assert_eq(bytes, 10L)
  let limit = @rolling.FileByteLimit::bytes(20L)
  let state = @rolling.RollingState::new(acme(Size(limit)))
  let (plans, _) = write_all(state, on(0L), [bytes, bytes, bytes])
  inspect(plans, content=(
    #|open acme.log at 0
    #|append acme.log
    #|roll acme_001.log
  ))
}

///|
test "a new UTC day rolls to the first file of that day" {
  let limit = @rolling.FileByteLimit::bytes(100L)
  let state = @rolling.RollingState::new(acme(DailyAndSize(limit)))
  let (_, day27) = write_all(state, on(0L), [90L, 90L])
  assert_eq(day27.active().map(name => name.to_string()), Some("acme-20261027_001.log"))
  let before_midnight = on(0L, millis=86399999L)
  inspect(show_plan(day27.plan(before_midnight, 5L, [])), content=(
    #|append acme-20261027_001.log
  ))
  let midnight = on(1L)
  inspect(show_plan(day27.plan(midnight, 5L, [])), content=(
    #|roll acme-20261028.log
  ))
}

///|
test "a clock that moves back stays in the day of the active file" {
  let state = @rolling.RollingState::new(acme(Daily))
  let (_, day28) = write_all(state, on(1L), [10L])
  inspect(show_plan(day28.plan(on(0L), 10L, [])), content=(
    #|append acme-20261028.log
  ))
  inspect(show_plan(day28.plan(on(2L), 10L, [])), content=(
    #|roll acme-20261029.log
  ))
}

///|
test "a size-only policy does not roll at a new day" {
  let limit = @rolling.FileByteLimit::bytes(100L)
  let state = @rolling.RollingState::new(acme(Size(limit)))
  let (_, opened) = write_all(state, on(0L), [10L])
  inspect(show_plan(opened.plan(on(5L), 10L, [])), content="append acme.log")
}

///|
test "a daily-only policy does not roll at any size" {
  let state = @rolling.RollingState::new(acme(Daily))
  let (plans, last) = write_all(state, on(0L), [
    100000000L, 100000000L, 100000000L,
  ])
  inspect(plans, content=(
    #|open acme-20261027.log at 0
    #|append acme-20261027.log
    #|append acme-20261027.log
  ))
  assert_eq(last.size(), 300000000L)
}

///|
test "an open file does not read the listing" {
  let state = @rolling.RollingState::new(acme(Daily))
  let (_, opened) = write_all(state, on(0L), [10L])
  let listing = [regular("acme-20261027_005.log", 1L)]
  inspect(show_plan(opened.plan(on(0L), 10L, listing)), content=(
    #|append acme-20261027.log
  ))
}

///|
test "a restart appends to the newest file of the day when it has room" {
  let limit = @rolling.FileByteLimit::bytes(100L)
  let state = @rolling.RollingState::new(acme(DailyAndSize(limit)))
  let listing = [
    regular("acme-20261027_001.log", 50L),
    regular("acme-20261026_007.log", 1L),
    regular("acme-20261027.log", 100L),
    regular("acme-old.log", 1L),
  ]
  inspect(show_plan(state.plan(on(0L), 50L, listing)), content=(
    #|open acme-20261027_001.log at 50
  ))
  inspect(show_plan(state.plan(on(0L), 51L, listing)), content=(
    #|open acme-20261027_002.log at 0
  ))
  inspect(show_plan(state.plan(on(1L), 51L, listing)), content=(
    #|open acme-20261028.log at 0
  ))
}

///|
test "a restart puts an oversized record in an empty newest file" {
  let limit = @rolling.FileByteLimit::bytes(10L)
  let state = @rolling.RollingState::new(acme(Size(limit)))
  let listing = [regular("acme.log", 10L), regular("acme_001.log", 0L)]
  inspect(show_plan(state.plan(on(0L), 50L, listing)), content=(
    #|open acme_001.log at 0
  ))
}

///|
test "a restart of a daily-only set appends at any size" {
  let state = @rolling.RollingState::new(acme(Daily))
  let listing = [regular("acme-20261027.log", 999999999L)]
  inspect(show_plan(state.plan(on(0L), 50L, listing)), content=(
    #|open acme-20261027.log at 999999999
  ))
}

///|
test "a restart does not append to a directory or a link" {
  let limit = @rolling.FileByteLimit::bytes(100L)
  let state = @rolling.RollingState::new(acme(Size(limit)))
  let listing = [
    regular("acme.log", 1L),
    { name: "acme_001.log", size: 0L, regular: false },
  ]
  inspect(show_plan(state.plan(on(0L), 1L, listing)), content=(
    #|open acme_002.log at 0
  ))
}

///|
test "the state counts the existing size after a restart" {
  let limit = @rolling.FileByteLimit::bytes(100L)
  let state = @rolling.RollingState::new(acme(Size(limit)))
  let plan = state.plan(on(0L), 30L, [regular("acme.log", 60L)])
  let after = apply(state, plan, 30L)
  assert_eq(after.size(), 90L)
  inspect(show_plan(after.plan(on(0L), 10L, [])), content="append acme.log")
  inspect(show_plan(after.plan(on(0L), 11L, [])), content="roll acme_001.log")
}

///|
test "the last sequence number is exhausted, not used again" {
  let limit = @rolling.FileByteLimit::bytes(10L)
  let set = acme(Size(limit))
  let last = set.parse_name("acme_2147483647.log").unwrap()
  let state = @rolling.RollingState::new(set).opened(last, 10L)
  let now = on(0L)
  let failure = try {
    ignore(state.plan(now, 1L, []))
    None
  } catch {
    SequenceExhausted(last~) => Some(last)
    _ => None
  }
  assert_eq(failure, Some("acme_2147483647.log"))
  inspect(show_plan(state.plan(on(0L), 0L, [])), content=(
    #|append acme_2147483647.log
  ))
  let restart = try {
    ignore(
      @rolling.RollingState::new(set).plan(now, 1L, [
        regular("acme_2147483647.log", 10L),
      ]),
    )
    None
  } catch {
    SequenceExhausted(last~) => Some(last)
    _ => None
  }
  assert_eq(restart, Some("acme_2147483647.log"))
}

///|
test "a negative record size is an error" {
  let state = @rolling.RollingState::new(acme(Daily))
  let now = on(0L)
  let failure = try {
    ignore(state.plan(now, -1L, []))
    None
  } catch {
    NegativeRecordBytes(bytes~) => Some(bytes)
    _ => None
  }
  assert_eq(failure, Some(-1L))
  inspect(show_plan(state.plan(on(0L), 0L, [])), content=(
    #|open acme-20261027.log at 0
  ))
}

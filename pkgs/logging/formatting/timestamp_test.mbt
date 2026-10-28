///|
/// The timestamp of `millis`, for times that are in range.
fn at(millis : Int64) -> @formatting.LogTimestamp raise {
  @formatting.LogTimestamp::from_epoch_millis(millis)
}

///|
/// The millis of a failed constructor call, or `None` when it succeeds.
fn out_of_range(millis : Int64) -> Int64? {
  try {
    ignore(@formatting.LogTimestamp::from_epoch_millis(millis))
    None
  } catch {
    TimestampOutOfRange(millis~) => Some(millis)
  }
}

///|
test "the earliest and the latest times are the limits of the range" {
  inspect(at(0L), content="1970-01-01T00:00:00.000Z")
  inspect(at(253402300799999L), content="9999-12-31T23:59:59.999Z")
  assert_eq(@formatting.LogTimestamp::earliest(), at(0L))
  assert_eq(@formatting.LogTimestamp::latest(), at(253402300799999L))
  assert_eq(@formatting.LogTimestamp::earliest().epoch_millis(), 0L)
  assert_eq(@formatting.LogTimestamp::latest().epoch_day(), 2932896L)
}

///|
test "a time on each side of each limit" {
  assert_eq(out_of_range(-1L), Some(-1L))
  assert_eq(out_of_range(0L), None)
  assert_eq(out_of_range(253402300799999L), None)
  assert_eq(out_of_range(253402300800000L), Some(253402300800000L))
  assert_eq(
    out_of_range(-9223372036854775807L - 1L),
    Some(-9223372036854775807L - 1L),
  )
}

///|
test "the error names the input and the range" {
  let result : Result[_, @formatting.TimestampError] = try
    Ok(@formatting.LogTimestamp::from_epoch_millis(-1L))
  catch {
    error => Err(error)
  }
  guard result is Err(failure) else { fail("no range error") }
  inspect(failure.message(), content=(
    #|Invalid log timestamp -1: the value must be from 0 (1970-01-01T00:00:00.000Z) to 253402300799999 (9999-12-31T23:59:59.999Z) milliseconds after the Unix epoch
  ))
}

///|
test "the text forms of one time" {
  let time = at(1793110987024L)
  assert_eq(time.to_iso8601(), "2026-10-27T14:23:07.024Z")
  assert_eq(time.to_string(), "2026-10-27T14:23:07.024Z")
  assert_eq(time.time_of_day(), "14:23:07.024Z")
  assert_eq(time.compact_date(), "20261027")
  assert_eq(time.epoch_millis(), 1793110987024L)
  assert_eq(time.epoch_day(), 20753L)
}

///|
test "milliseconds and the day boundary" {
  inspect(at(1L), content="1970-01-01T00:00:00.001Z")
  inspect(at(999L), content="1970-01-01T00:00:00.999Z")
  inspect(at(86399999L), content="1970-01-01T23:59:59.999Z")
  inspect(at(86400000L), content="1970-01-02T00:00:00.000Z")
  assert_eq(at(86399999L).epoch_day(), 0L)
  assert_eq(at(86400000L).epoch_day(), 1L)
}

///|
test "leap days" {
  // 2024-02-29 is a leap day; 2023 has no leap day.
  inspect(at(1709164800000L), content="2024-02-29T00:00:00.000Z")
  inspect(at(1709251200000L), content="2024-03-01T00:00:00.000Z")
  inspect(at(1677628800000L), content="2023-03-01T00:00:00.000Z")
  // 2000 is a leap year because 400 divides it; 2100 is not.
  inspect(at(951782400000L), content="2000-02-29T00:00:00.000Z")
  inspect(at(4107542400000L), content="2100-03-01T00:00:00.000Z")
  inspect(at(4107456000000L), content="2100-02-28T00:00:00.000Z")
  inspect(at(1704067199999L), content="2023-12-31T23:59:59.999Z")
  inspect(at(1704067200000L), content="2024-01-01T00:00:00.000Z")
  assert_eq(at(1709164800000L).compact_date(), "20240229")
}

///|
test "timestamps compare in time order" {
  assert_true(at(1L) < at(2L))
  assert_true(@formatting.LogTimestamp::earliest() <
    @formatting.LogTimestamp::latest())
  assert_eq(at(5L), at(5L))
}

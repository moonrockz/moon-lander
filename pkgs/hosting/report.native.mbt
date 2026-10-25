///|
// The async stdio handle permits one writer at a time. Concurrent host runs
// share this lock so their default reports do not submit overlapping writes.
let report_lock : @async.Mutex = @async.Mutex::Mutex()

///|
async fn write_report_line(text : String) -> Unit {
  report_lock.acquire()
  defer report_lock.release()
  @stdio.stderr.write(text + "\n")
}

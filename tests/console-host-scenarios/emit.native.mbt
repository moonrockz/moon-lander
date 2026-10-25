///|
/// Write one line to standard output with no buffer, so the parent process
/// reads it before the next step of the child.
async fn emit(line : String) -> Unit {
  @stdio.stdout.write(line + "\n")
}

///|
/// The native driver ends the process with libc `exit`, so no open timer can
/// keep it running.
fn leave_timer_open() -> Unit {
  ()
}

///|
/// Write one line to standard output with no buffer, so the parent process
/// reads it before the next step of the child.
async fn emit(line : String) -> Unit {
  @stdio.stdout.write(line + "\n")
}

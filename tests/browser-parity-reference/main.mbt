///|
/// Print the reference parity observation of the pure loader on this target.
fn main {
  println(@parity.reference()) catch { error => abort(@parity.failure(error)) }
}

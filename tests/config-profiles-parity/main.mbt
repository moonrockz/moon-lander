///|
fn main {
  println(@profiles_fixture.observations() catch { error => abort(error.message()) })
}

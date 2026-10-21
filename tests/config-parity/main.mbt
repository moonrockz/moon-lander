///|
fn main {
  let config = @fixture.load() catch { error => abort(error.message()) }
  println(@debug.Debug::to_repr(config.value().to_ion()))
  println(@debug.Debug::to_repr(config.provenance()))
  println(@debug.Debug::to_repr(config.reports()))
}

///|
async fn poll_stop(ctx : @hosting.Context[Unit], stopped : () -> Unit) -> Unit {
  emit("ready")
  let count = Ref(0UL)
  while !ctx.stop_requested() { count.val += 1UL }
  stopped()
}

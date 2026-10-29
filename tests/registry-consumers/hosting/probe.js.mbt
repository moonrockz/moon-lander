///|
extern "js" fn foreign_read(read : () -> Bool) -> @js_async.Promise[Bool] =
  #|read => new Promise((resolve, reject) => setTimeout(() => {
  #|  try { resolve(read()); } catch (error) { reject(error); }
  #|}, 0))

///|
async fn poll(read : () -> Bool) -> Bool { foreign_read(read).wait() }

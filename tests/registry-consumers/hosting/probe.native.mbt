///|
async fn poll(read : () -> Bool) -> Bool { @async.sleep(1); read() }

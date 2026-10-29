///|
/// A worker can block its stdout acknowledgement while it polls synchronously.
/// Use the launcher's independent control port before entering that loop.
extern "js" fn announce_ready() -> Unit =
  #|() => {
  #|  const ready = globalThis.landerWorkerReady;
  #|  if (typeof ready === "function") ready(); else console.log("ready");
  #|}

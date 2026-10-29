import { Worker, isMainThread, parentPort, workerData } from "node:worker_threads";

// Unpublished acceptance fixture. MoonBit owns build and process lifecycle.
if (isMainThread) {
  const signals = new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT);
  const publishInterrupt = () => Atomics.store(new Int32Array(signals), 0, 1);
  const publishTerminate = () => Atomics.store(new Int32Array(signals), 0, 2);
  process.on("SIGINT", publishInterrupt);
  process.on("SIGTERM", publishTerminate);
  const worker = new Worker(process.argv[1], {
    workerData: { signals, program: process.argv[2] },
  });
  let ready = false;
  worker.on("message", message => {
    if (message !== "lander:ready" || ready) {
      throw new Error("Unexpected worker readiness message");
    }
    ready = true;
    console.log("ready");
  });
  worker.on("error", error => { throw error; });
  worker.on("exit", code => {
    if (!process.listeners("SIGINT").includes(publishInterrupt) ||
        !process.listeners("SIGTERM").includes(publishTerminate)) {
      throw new Error("Enclosing listeners were removed");
    }
    console.log("owner-listeners=intact");
    process.removeListener("SIGINT", publishInterrupt);
    process.removeListener("SIGTERM", publishTerminate);
    process.exitCode = code;
  });
} else {
  (globalThis as any).landerSignals = new Int32Array(workerData.signals);
  (globalThis as any).landerWorkerReady = () => {
    // Keep stdout pending when the worker enters its non-yielding loop. Its
    // write acknowledgement needs the worker event loop; readiness must not.
    console.log("worker-stdout-pending");
    parentPort!.postMessage("lander:ready");
  };
  const originalOn = process.on;
  process.on = function (event: string, ...args: any[]) {
    if (["SIGINT", "SIGTERM", "SIGQUIT", "SIGBREAK", "SIGHUP"].includes(event)) {
      throw new Error("Console installed competing signal listener: " + event);
    }
    return originalOn.call(this, event, ...args);
  } as typeof process.on;
  require(workerData.program);
}

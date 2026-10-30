const { parentPort, workerData } = require('node:worker_threads');
const stop = new Int32Array(workerData);
parentPort.postMessage('ready');
// Deliberately never yields: only the Node owner's explicit shared stop request
// makes this computation finish. No parent-death behavior is involved.
while (Atomics.load(stop, 0) === 0) {}
parentPort.postMessage('stopped');
parentPort.close();

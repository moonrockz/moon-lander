// Test-only Node boundary. The compiled MoonBit console host owns signal
// handling and completion; this adapter supplies actual worker lifetime only.
const { Worker } = require('node:worker_threads');
const { join } = require('node:path');
const shared = new SharedArrayBuffer(4);
const stop = new Int32Array(shared);
let worker;
let exit;
globalThis.moonxFixture = {
  start() {
    return new Promise((resolve, reject) => {
      worker = new Worker(join(__dirname, 'worker.cjs'), { workerData: shared });
      exit = new Promise((done, failed) => {
        worker.once('exit', code => code === 0 ? done() : failed(new Error(`Worker exit ${code}`)));
        worker.once('error', failed);
      });
      worker.on('message', message => {
        if (message === 'ready') resolve();
        if (message === 'stopped') process.stdout.write('WORKER_STOPPED\n');
      });
      worker.once('error', reject);
    });
  },
  stop() { Atomics.store(stop, 0, 1); },
  join() { return exit ?? Promise.resolve(); },
};
process.stdout.write(`READY ${process.pid}\n`);
require(process.env.MOONX_HOST_PROGRAM);

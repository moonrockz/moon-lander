// Prints the gzip size in bytes of the file in the first argument, compressed with zlib at its
// default level. Browsers get the islands bundle compressed in the same way, so the islands budget
// of design D13 uses this size. `scripts/site.mbtx build` runs this script with Bun.
import { readFileSync } from "node:fs";
import { gzipSync } from "node:zlib";

const file = process.argv[2];
if (!file) {
  console.error("usage: gzip-size.ts <file>");
  process.exit(2);
}
process.stdout.write(String(gzipSync(readFileSync(file)).length));

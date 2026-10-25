// Test-only capture. This entry point never enters the library bundle.
import { stderr } from "node:process";

export function captureStderr(prefix: string): { finish(): string } {
  const original = stderr.write;
  let text = "";
  stderr.write = ((chunk: string, callback: (error?: Error) => void) => {
    // Moon runs async tests concurrently; leave other reports on stderr.
    if (!chunk.startsWith(prefix)) return original.call(stderr, chunk, callback);
    // Delay completion so the test also verifies that the driver awaits it.
    setTimeout(() => {
      text += chunk;
      callback();
    }, 1);
    return true;
  }) as typeof stderr.write;
  return { finish() { stderr.write = original; return text; } };
}

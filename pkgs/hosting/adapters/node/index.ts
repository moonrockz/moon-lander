import { stderr } from "node:process";

// Resolve only after the stream has completed this write.
export function writeStderr(text: string): Promise<void> {
  return new Promise((resolve, reject) => {
    stderr.write(text, error => error ? reject(error) : resolve());
  });
}

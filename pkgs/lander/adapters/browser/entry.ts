import { read, readFile, normalizeBase, supported } from "./index";
declare function receiveBrowserAdapter(adapter: {
  read: typeof read; readFile: typeof readFile; normalizeBase: typeof normalizeBase; supported: typeof supported;
}): void;
receiveBrowserAdapter({ read, readFile, normalizeBase, supported });

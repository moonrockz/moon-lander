import { read, readFile, listDirectory, readDirectoryFile, normalizeBase, supported } from "./index";
declare function receiveBrowserAdapter(adapter: {
  read: typeof read; readFile: typeof readFile; listDirectory: typeof listDirectory;
  readDirectoryFile: typeof readDirectoryFile; normalizeBase: typeof normalizeBase; supported: typeof supported;
}): void;
receiveBrowserAdapter({ read, readFile, listDirectory, readDirectoryFile, normalizeBase, supported });

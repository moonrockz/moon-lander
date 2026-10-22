import {
  read, readFile, listDirectory, readDirectoryFile, openStore, writeText, removeFile, normalizeBase, supported,
} from "./index";
declare function receiveBrowserAdapter(adapter: {
  read: typeof read; readFile: typeof readFile; listDirectory: typeof listDirectory;
  readDirectoryFile: typeof readDirectoryFile; openStore: typeof openStore; writeText: typeof writeText;
  removeFile: typeof removeFile; normalizeBase: typeof normalizeBase; supported: typeof supported;
}): void;
receiveBrowserAdapter({
  read, readFile, listDirectory, readDirectoryFile, openStore, writeText, removeFile, normalizeBase, supported,
});

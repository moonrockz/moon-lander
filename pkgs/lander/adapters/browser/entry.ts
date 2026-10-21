import { read, normalizeBase, supported } from "./index";
declare function receiveBrowserAdapter(adapter: { read: typeof read; normalizeBase: typeof normalizeBase; supported: typeof supported }): void;
receiveBrowserAdapter({ read, normalizeBase, supported });

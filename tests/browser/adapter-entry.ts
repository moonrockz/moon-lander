import { fetchText } from "../../pkgs/lander/adapters/browser/feasibility";

// Supplied lexically by the generated MoonBit factory, never a browser global.
declare function receiveBrowserAdapter(adapter: { fetchText: typeof fetchText }): void;
receiveBrowserAdapter({ fetchText });

import { register, origin, signal, fileCount, fileAt, handle, between, makeFile, registerParity } from "./fixture";
declare function receiveBrowserAdapter(adapter: {
  register: typeof register; origin: typeof origin; signal: typeof signal; fileCount: typeof fileCount;
  fileAt: typeof fileAt; handle: typeof handle; between: typeof between; makeFile: typeof makeFile;
  registerParity: typeof registerParity;
}): void;
receiveBrowserAdapter({ register, origin, signal, fileCount, fileAt, handle, between, makeFile, registerParity });

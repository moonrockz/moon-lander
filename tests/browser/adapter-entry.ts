import { register, origin, signal, fileCount, fileAt } from "./fixture";
declare function receiveBrowserAdapter(adapter: {
  register: typeof register; origin: typeof origin; signal: typeof signal; fileCount: typeof fileCount; fileAt: typeof fileAt;
}): void;
receiveBrowserAdapter({ register, origin, signal, fileCount, fileAt });

import { register, origin, signal } from "./fixture";
declare function receiveBrowserAdapter(adapter: { register: typeof register; origin: typeof origin; signal: typeof signal }): void;
receiveBrowserAdapter({ register, origin, signal });

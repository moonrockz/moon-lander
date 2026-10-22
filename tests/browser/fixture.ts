export function register(run: (request: string) => Promise<string>, probe: (url: string) => Promise<string>) {
  Object.assign(globalThis, {
    landerRun: async (request: unknown) => JSON.parse(await run(JSON.stringify(request))),
    landerProbe: probe,
  });
}

export function origin() { return location.origin; }
export function signal() { return (globalThis as any).testSignal ?? new AbortController().signal; }

/** Files that the test put into one plain HTML file input of the test page. */
function selected(selector: string): File[] {
  const input = document.querySelector(selector);
  return input instanceof HTMLInputElement && input.files ? Array.from(input.files) : [];
}
export function fileCount(selector: string) { return selected(selector).length; }
export function fileAt(selector: string, index: number) { return selected(selector)[index]; }

/** A directory handle that the test created in OPFS or wrapped for error injection. */
export function handle(name: string) { return (globalThis as any).testHandles?.[name]; }
/** Let the test change a live backend between two loads. */
export async function between() { await (globalThis as any).betweenLoads?.(); return true; }
/** A File made from fixture text, for the cross-target parity check. */
export function makeFile(name: string, text: string) { return new File([text], name, { type: "text/plain" }); }
/** Expose the parity observation of the shared cases. */
export function registerParity(parity: () => Promise<string>) { Object.assign(globalThis, { landerParity: parity }); }

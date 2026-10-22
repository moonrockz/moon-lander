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

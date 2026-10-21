export function register(run: (request: string) => Promise<string>, probe: (url: string) => Promise<string>) {
  Object.assign(globalThis, {
    landerRun: async (request: unknown) => JSON.parse(await run(JSON.stringify(request))),
    landerProbe: probe,
  });
}

export function origin() { return location.origin; }
export function signal() { return (globalThis as any).testSignal ?? new AbortController().signal; }

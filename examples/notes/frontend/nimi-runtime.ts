declare global {
  interface Window {
    nimi: { call(method: string, ...args: unknown[]): Promise<unknown> };
    mygo?: { call(method: string, ...args: unknown[]): Promise<unknown> };
  }
}

export function call<T>(method: string, ...args: unknown[]): Promise<T> {
  return window.nimi.call(method, ...args) as Promise<T>;
}

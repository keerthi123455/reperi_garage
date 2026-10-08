export class AssertionError extends Error {}
export function assert(c: unknown, msg = "assertion failed"): asserts c { if (!c) throw new AssertionError(msg); }
export function assertEquals(a: unknown, b: unknown) {
  const s = (x: unknown) => JSON.stringify(x);
  if (s(a) !== s(b)) throw new AssertionError(`\n  actual:   ${s(a)}\n  expected: ${s(b)}`);
}
export async function assertRejects(fn: () => Promise<unknown>, cls: new (...a: any[]) => Error, includes?: string) {
  try { await fn(); } catch (e) {
    if (!(e instanceof cls)) throw new AssertionError(`wrong error type: ${e}`);
    if (includes && !(e as Error).message.includes(includes)) throw new AssertionError(`message "${(e as Error).message}" lacks "${includes}"`);
    return;
  }
  throw new AssertionError("expected rejection");
}

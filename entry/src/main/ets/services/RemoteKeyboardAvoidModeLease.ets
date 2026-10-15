export interface RemoteKeyboardAvoidModePort { get(): number; set(mode: number): void; }
export class RemoteKeyboardAvoidModeCallbacks implements RemoteKeyboardAvoidModePort {
  private read: () => number;
  private write: (mode: number) => void;
  constructor(read: () => number, write: (mode: number) => void) { this.read = read; this.write = write; }
  get(): number { return this.read(); }
  set(mode: number): void { this.write(mode); }
}
interface RemoteKeyboardAvoidModeEntry { owner: number; baseline: number; port: RemoteKeyboardAvoidModePort; }
/** Window-scoped ownership. A retired page cannot restore over its successor or a local form. */
export class RemoteKeyboardAvoidModeLease {
  private static owners: number = 0;
  private static windows: Map<string, RemoteKeyboardAvoidModeEntry> = new Map();
  static owner(): number { return ++RemoteKeyboardAvoidModeLease.owners; }
  static acquire(window: string, owner: number, none: number, port: RemoteKeyboardAvoidModePort): void {
    const old = RemoteKeyboardAvoidModeLease.windows.get(window);
    const baseline: number = old === undefined ? port.get() : old.baseline;
    port.set(none);
    RemoteKeyboardAvoidModeLease.windows.set(window, { owner, baseline, port });
  }
  static release(window: string, owner: number, none: number): void {
    const current = RemoteKeyboardAvoidModeLease.windows.get(window);
    if (current === undefined || current.owner !== owner) { return; }
    RemoteKeyboardAvoidModeLease.windows.delete(window);
    if (current.port.get() === none) { current.port.set(current.baseline); }
  }
}

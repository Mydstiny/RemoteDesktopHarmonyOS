/** Per-page input ownership. No transport or remote focus changes are made here. */
export class RemoteInputOverlay {
  token: number = 0;
  name: string = '';
  kind: string = 'menu';
}

export class RemoteSessionInputOwner {
  private epochValue: number = 0;
  private nextToken: number = 1;
  private flags: string = '';
  private overlays: Array<RemoteInputOverlay> = [];
  private physicalDown: Array<number> = [];
  private actionDepth: number = 0;
  private notify: () => void = (): void => {};

  observe(notify: () => void): void { this.notify = notify; }
  epoch(): number { return this.epochValue; }
  current(epoch: number): boolean { return epoch === this.epochValue; }
  /** Flags fence the opening frame, native leases fence the closing animation. */
  setFlags(names: Array<string>): void {
    const next: string = names.slice().sort().join('|');
    if (next !== this.flags) { this.flags = next; this.physicalDown = []; this.epochValue++; }
  }
  acquire(name: string, kind: string = 'menu'): number {
    const lease: RemoteInputOverlay = new RemoteInputOverlay();
    lease.token = this.nextToken++; lease.name = name; lease.kind = kind;
    this.overlays.push(lease); this.changed();
    return lease.token;
  }
  release(token: number): void {
    const index: number = this.overlays.findIndex((entry: RemoteInputOverlay): boolean => entry.token === token);
    if (index < 0) { return; }
    this.overlays.splice(index, 1); this.changed();
  }
  /**
   * Native instances disappear in presentation order; a late parent cannot retire its child.
   * One lease per ArkUI instance: onWillAppear/onDisappear are paired per instance, and a sheet
   * reopened while its previous instance is still animating out holds two leases, so the old
   * instance's disappear cannot unblock input while the new one is visible or closing.
   */
  appeared(name: string): void { this.acquire(name); }
  visible(name: string, visible: boolean): void {
    const exists: boolean = this.overlays.some((item: RemoteInputOverlay): boolean => item.name === name);
    if (visible && !exists) { this.appeared(name); }
    else if (!visible && exists) { this.disappeared(name); }
  }
  disappeared(name: string): void {
    const entry: RemoteInputOverlay | undefined = this.overlays.find((item: RemoteInputOverlay): boolean => item.name === name);
    if (entry !== undefined) { this.release(entry.token); }
  }
  wrapDisappear(name: string, callback: () => void): () => void {
    return (): void => { this.disappeared(name); callback(); };
  }
  allowsPhysical(code: number, down: boolean): boolean {
    if (this.blocked()) { this.physicalDown = []; return false; }
    const index: number = this.physicalDown.indexOf(code);
    if (down) { if (index < 0) { this.physicalDown.push(code); } return true; }
    if (index < 0) { return false; }
    this.physicalDown.splice(index, 1); return true;
  }
  blocked(): boolean { return this.flags.length > 0 || this.overlays.length > 0; }
  /** Overlay leases only; page flags are evaluated by their owner without mutating state. */
  overlaysActive(): boolean { return this.overlays.length > 0; }
  /**
   * Drop every lease of a closed overlay whose state says it is gone. A sheet torn down
   * without its onDisappear (closed during its opening animation) would otherwise block
   * remote input for the rest of the session.
   */
  retire(name: string): number {
    const before: number = this.overlays.length;
    this.overlays = this.overlays.filter((entry: RemoteInputOverlay): boolean => entry.name !== name);
    const removed: number = before - this.overlays.length;
    if (removed > 0) { this.changed(); }
    return removed;
  }
  /** Flags and overlay names for diagnostics (no user content). */
  debugString(): string {
    return 'flags=[' + this.flags + '] overlays=[' +
      this.overlays.map((entry: RemoteInputOverlay): string => entry.kind + ':' + entry.name).join(',') + ']';
  }
  allowsInput(): boolean { return !this.blocked() || this.actionAllowed(); }
  actionAllowed(): boolean {
    return this.actionDepth > 0 && !this.flags.split('|').some((name: string): boolean =>
      name.indexOf('Auth') >= 0 || name.indexOf('Certificate') >= 0 || name.indexOf('Passphrase') >= 0 ||
      name.indexOf('TwoFactor') >= 0 || name.indexOf('Security') >= 0) && !this.overlays.some((entry: RemoteInputOverlay): boolean =>
      entry.kind === 'system' || entry.kind === 'editor');
  }
  /** Only explicitly invoked remote controls call this; physical input never enters an action lease. */
  runAction(action: () => void): void {
    this.actionDepth++;
    try { action(); } finally { this.actionDepth--; }
  }
  guardedAction(action: () => boolean): () => boolean {
    const epoch: number = this.epochValue;
    const explicit: boolean = this.actionAllowed();
    return (): boolean => {
      if (!this.current(epoch) || (this.blocked() && !explicit)) { return false; }
      let result: boolean = false;
      if (explicit) { this.runAction((): void => { result = action(); }); }
      else { result = action(); }
      return result;
    };
  }
  invalidate(): void { this.physicalDown = []; this.epochValue++; }
  dispose(): void { this.flags = ''; this.overlays = []; this.changed(); this.notify = (): void => {}; }
  private changed(): void { this.physicalDown = []; this.epochValue++; this.notify(); }
}

/** Acquire before opening an OS dialog, release on success, cancellation and synchronous failure. */
export async function withRemoteInputDialog<T>(owner: RemoteSessionInputOwner,
  open: () => Promise<T>): Promise<T> {
  const token: number = owner.acquire('system-dialog', 'system');
  try { return await open(); } finally { owner.release(token); }
}

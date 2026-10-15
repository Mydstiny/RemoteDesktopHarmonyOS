/** One ArkUI IME client. Focus operations wait for the system session to stop, then for committed FIFO admission. */
export class RemoteImeFocusBarrier {
  private phase: string = 'idle';
  private epoch: number = 0;
  private actions: Array<() => boolean> = [];
  private timer: number = -1;
  private failure: (() => void) | null = null;

  stopping(): boolean { return this.phase === 'stopping'; }
  replaying(): boolean { return this.phase === 'replaying'; }

  enqueue(action: () => boolean): boolean {
    if (!this.stopping()) { return false; }
    if (this.actions.length >= 128) { this.cancel(); return false; }
    this.actions.push(action);
    return true;
  }

  cancel(): void {
    const failure: (() => void) | null = this.failure;
    this.failure = null;
    this.epoch++;
    this.phase = 'idle';
    this.actions = [];
    if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
    if (failure !== null) { failure(); }
  }

  begin(stop: () => Promise<boolean>, current: () => boolean, flush: () => boolean,
    beforeReplay: () => void, settled: (success: boolean) => void): void {
    if (this.phase !== 'idle') { return; }
    const epoch: number = ++this.epoch;
    this.phase = 'stopping';
    this.failure = (): void => settled(false);
    const finish = (success: boolean): void => {
      if (epoch !== this.epoch || !this.stopping()) { return; }
      if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; }
      try {
        if (!success || !current()) { this.cancel(); return; }
        this.phase = 'draining';
        if (!flush()) { this.cancel(); return; }
        this.phase = 'replaying';
        beforeReplay();
        let accepted: boolean = true;
        const actions: Array<() => boolean> = this.actions;
        this.actions = [];
        for (const action of actions) {
          if (!current() || !action()) { accepted = false; break; }
        }
        this.phase = 'idle';
        this.failure = null;
        settled(accepted);
      } catch (_error) {
        this.cancel();
      }
    };
    this.timer = setTimeout((): void => finish(false), 1500);
    try { stop().then((success: boolean): void => finish(success), (): void => finish(false)); }
    catch (_error) { finish(false); }
  }
}

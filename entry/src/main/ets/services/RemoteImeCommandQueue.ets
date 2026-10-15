/**
 * RemoteImeCommandQueue.ets - ordered, privacy-safe remote IME commands.
 *
 * A command is consumed exactly once by the page-level dispatcher.  Keeping
 * text and cursor commands in one FIFO prevents a large gesture from being
 * overtaken by text committed immediately afterwards.
 */

export enum RemoteImeCommandKind {
  TEXT = 0,
  KEY_TAPS = 1
}

export interface RemoteImeCommand {
  kind: RemoteImeCommandKind;
  text: string;
  keyCode: number;
  tapCount: number;
  generation: number;
  source: string;
}

export class RemoteImeCommandQueue {
  private commands: RemoteImeCommand[] = [];

  enqueueText(text: string, generation: number, source: string): void {
    if (text.length === 0) {
      return;
    }
    this.commands.push({
      kind: RemoteImeCommandKind.TEXT,
      text,
      keyCode: 0,
      tapCount: 0,
      generation,
      source
    });
  }

  enqueueKeyTaps(keyCode: number, count: number, generation: number, source: string): void {
    if (count <= 0) {
      return;
    }
    this.commands.push({
      kind: RemoteImeCommandKind.KEY_TAPS,
      text: '',
      keyCode,
      tapCount: count,
      generation,
      source
    });
  }

  shift(): RemoteImeCommand | null {
    return this.commands.length > 0 ? this.commands.shift()! : null;
  }

  pushFront(command: RemoteImeCommand): void {
    this.commands.unshift(command);
  }

  clear(): void {
    this.commands = [];
  }

  size(): number {
    return this.commands.length;
  }

  /**
   * Drain committed operations into the protocol's ordered input lane before a pointer/Tab.
   * Preedit is never in this queue. Dispatch reduces tapCount after each accepted tap so a failed
   * suffix cannot replay an accepted prefix. A disconnected or oversized queue leaves focus unchanged.
   * This is wire ordering, not an assertion that a remote application acknowledged the text.
   */
  drainBeforeFocusChange(generation: number, ready: boolean,
    dispatch: (command: RemoteImeCommand) => boolean): boolean {
    if (!ready || this.commands.length > 128) { return false; }
    let taps: number = 0;
    let units: number = 0;
    for (const command of this.commands) {
      if (command.generation !== generation) { return false; }
      taps += command.tapCount;
      units += command.text.length;
    }
    if (taps > 512 || units > 65536) { return false; }
    while (this.commands.length > 0) {
      const command: RemoteImeCommand = this.commands[0];
      if (!dispatch(command)) { return false; }
      this.commands.shift();
    }
    return true;
  }
}

/** Tracks keys actually admitted to one native owner, separately from the local modifier UI. */
export class RemoteHardwareKeyLease {
  private owner: string = '';
  private held: Array<number> = [];

  send(owner: string, code: number, pressed: boolean, dispatch: (code: number, pressed: boolean) => boolean): boolean {
    if (owner.length === 0 || !Number.isSafeInteger(code) || code < 0) { return false; }
    if (this.owner !== owner) { this.owner = owner; this.held = []; }
    if (!dispatch(code, pressed)) { return false; }
    const index: number = this.held.indexOf(code);
    if (pressed && index < 0) { this.held.push(code); }
    else if (!pressed && index >= 0) { this.held.splice(index, 1); }
    return true;
  }

  release(owner: string, dispatch: (code: number, pressed: boolean) => boolean): boolean {
    if (this.owner !== owner || owner.length === 0) { this.forget(); return true; }
    let accepted: boolean = true;
    const held: Array<number> = this.held.slice();
    for (const code of held) {
      if (!this.send(owner, code, false, dispatch)) { accepted = false; }
    }
    return accepted;
  }

  forget(): void { this.owner = ''; this.held = []; }
  heldCount(): number { return this.held.length; }
  holds(owner: string, code: number): boolean { return owner === this.owner && this.held.indexOf(code) >= 0; }
  owns(owner: string): boolean { return owner.length > 0 && owner === this.owner; }
}

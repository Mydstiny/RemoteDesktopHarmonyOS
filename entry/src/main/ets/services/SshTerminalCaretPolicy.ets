/** Local xterm geometry only. No remote application/widget semantics or terminal text crosses this bridge. */
export interface SshTerminalCaretSnapshot {
  sequence: number;
  x: number;
  y: number;
  width: number;
  height: number;
  viewportWidth: number;
  viewportHeight: number;
  visible: boolean;
  followingBottom: boolean;
  alternateBuffer: boolean;
}

export function validSshTerminalCaret(snapshot: SshTerminalCaretSnapshot, previousSequence: number): boolean {
  return Number.isSafeInteger(snapshot.sequence) && snapshot.sequence > previousSequence &&
    Number.isFinite(snapshot.x) && Number.isFinite(snapshot.y) && Number.isFinite(snapshot.width) &&
    Number.isFinite(snapshot.height) && Number.isFinite(snapshot.viewportWidth) && Number.isFinite(snapshot.viewportHeight) &&
    snapshot.viewportWidth > 0 && snapshot.viewportWidth <= 32768 && snapshot.viewportHeight > 0 &&
    snapshot.viewportHeight <= 32768 && snapshot.width > 0 && snapshot.height > 0 &&
    snapshot.width <= snapshot.viewportWidth && snapshot.height <= snapshot.viewportHeight &&
    Math.abs(snapshot.x) <= snapshot.viewportWidth * 2 && Math.abs(snapshot.y) <= snapshot.viewportHeight * 2;
}

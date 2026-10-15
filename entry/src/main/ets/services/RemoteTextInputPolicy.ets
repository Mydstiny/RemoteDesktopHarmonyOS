/** Device-local intent and bounded, content-free remote text-focus state. */
export type RemoteKeyboardAutoOpenPolicy = 'off' | 'smart' | 'compatibilityClick';
export type RemoteKeyboardInputIntent = 'automatic' | 'virtual' | 'physical';
export type RemoteKeyboardPlacement = 'nearKeyboard' | 'keepVisible';
export type RemoteTextSource = 'terminal' | 'rdpTextChannel' | 'hostHelper' | 'compatibilityClick';

export const REMOTE_KEYBOARD_BEHAVIOR_VERSION_KEY: string = 'remoteKeyboardBehaviorVersion';
export const REMOTE_KEYBOARD_AUTO_OPEN_POLICY_KEY: string = 'remoteKeyboardAutoOpenPolicy';
export const REMOTE_KEYBOARD_INPUT_INTENT_KEY: string = 'remoteKeyboardInputIntent';
export const REMOTE_KEYBOARD_AVOIDANCE_ENABLED_KEY: string = 'remoteKeyboardAvoidanceEnabled';
export const REMOTE_KEYBOARD_PLACEMENT_KEY: string = 'remoteKeyboardPlacement';
export const REMOTE_KEYBOARD_GAP_KEY: string = 'remoteKeyboardGapVp';
export const REMOTE_TEXT_USER_INTENT_MS: number = 1500;

export interface RemoteKeyboardBehavior {
  version: number;
  autoOpenPolicy: RemoteKeyboardAutoOpenPolicy;
  inputIntent: RemoteKeyboardInputIntent;
  avoidanceEnabled: boolean;
  placement: RemoteKeyboardPlacement;
  gapVp: number;
}

export interface RemoteInputRect { x: number; y: number; width: number; height: number; }

export interface RemoteTextOwner {
  protocol: string;
  protocolSessionId?: string;
  sessionId: number;
  generation: number;
  geometryEpoch: number;
  displayId: number;
  desktopBinding: string;
  frameWidth: number;
  frameHeight: number;
}

export interface RemoteTextTarget {
  owner: RemoteTextOwner;
  source: RemoteTextSource;
  focusToken: string;
  sequence: number;
  editable: boolean;
  readOnly: boolean;
  enabled: boolean;
  visible: boolean;
  /** Set by the authenticated adapter, never accepted from a wire boolean. */
  verified: boolean;
  inputKind: string;
  controlRect: RemoteInputRect | null;
  caretRect: RemoteInputRect | null;
}

export interface RemoteTextOpenContext {
  policy: RemoteKeyboardAutoOpenPolicy;
  virtualInput: boolean;
  connected: boolean;
  inputReady: boolean;
  foreground: boolean;
  modalOwnsInput: boolean;
  readOnly: boolean;
  keyboardOpen: boolean;
}

export function normalizeRemoteKeyboardAutoOpenPolicy(value: string | undefined,
  legacyClick: boolean = false): RemoteKeyboardAutoOpenPolicy {
  if (value === 'off' || value === 'smart' || value === 'compatibilityClick') { return value; }
  // A missing version migrates the old boolean; a corrupt saved enum fails closed.
  return value === undefined || value.length === 0 ?
    (legacyClick ? 'compatibilityClick' : 'off') : 'off';
}

export function normalizeRemoteKeyboardInputIntent(value: string | undefined): RemoteKeyboardInputIntent {
  return value === 'virtual' || value === 'physical' ? value : 'automatic';
}

export function normalizeRemoteKeyboardPlacement(value: string | undefined): RemoteKeyboardPlacement {
  return value === 'keepVisible' ? 'keepVisible' : 'nearKeyboard';
}

export function normalizeRemoteKeyboardGap(value: number | undefined): number {
  return value !== undefined && Number.isFinite(value) ? Math.max(8, Math.min(32, value)) : 16;
}

export function defaultRemoteKeyboardBehavior(legacyClick: boolean = false): RemoteKeyboardBehavior {
  return { version: 1, autoOpenPolicy: legacyClick ? 'compatibilityClick' : 'off',
    inputIntent: 'automatic', avoidanceEnabled: true, placement: 'nearKeyboard', gapVp: 16 };
}

export function normalizeRemoteKeyboardBehavior(value: RemoteKeyboardBehavior | undefined,
  legacyClick: boolean = false): RemoteKeyboardBehavior {
  if (value === undefined) { return defaultRemoteKeyboardBehavior(legacyClick); }
  return { version: 1, autoOpenPolicy: normalizeRemoteKeyboardAutoOpenPolicy(value.autoOpenPolicy),
    inputIntent: normalizeRemoteKeyboardInputIntent(value.inputIntent),
    avoidanceEnabled: value.avoidanceEnabled === true,
    placement: normalizeRemoteKeyboardPlacement(value.placement), gapVp: normalizeRemoteKeyboardGap(value.gapVp) };
}

export function remoteVirtualKeyboardIntent(intent: RemoteKeyboardInputIntent,
  physicalKeyboardConnected: boolean, keyboardMouseMode: boolean): boolean {
  if (intent === 'virtual') { return true; }
  if (intent === 'physical') { return false; }
  return !physicalKeyboardConnected || !keyboardMouseMode;
}

export function sameRemoteTextOwner(a: RemoteTextOwner, b: RemoteTextOwner): boolean {
  return a.protocol === b.protocol && (a.protocolSessionId ?? '') === (b.protocolSessionId ?? '') && a.sessionId === b.sessionId &&
    a.generation === b.generation && a.geometryEpoch === b.geometryEpoch &&
    a.displayId === b.displayId && a.desktopBinding === b.desktopBinding &&
    a.frameWidth === b.frameWidth && a.frameHeight === b.frameHeight;
}

export function copyRemoteTextOwner(owner: RemoteTextOwner): RemoteTextOwner {
  return { protocol: owner.protocol, protocolSessionId: owner.protocolSessionId ?? '', sessionId: owner.sessionId, generation: owner.generation,
    geometryEpoch: owner.geometryEpoch, displayId: owner.displayId,
    desktopBinding: owner.desktopBinding, frameWidth: owner.frameWidth, frameHeight: owner.frameHeight };
}

export function copyRemoteInputRect(rect: RemoteInputRect | null): RemoteInputRect | null {
  return rect === null ? null : { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
}

/** Rectangles here are frame-local pixels. Global coordinates must be converted by the provider. */
export function boundedRemoteInputRect(rect: RemoteInputRect | null,
  frameWidth: number, frameHeight: number): RemoteInputRect | null {
  if (rect === null || !Number.isFinite(frameWidth) || !Number.isFinite(frameHeight) ||
    frameWidth <= 0 || frameHeight <= 0 || frameWidth > 32768 || frameHeight > 32768 ||
    !Number.isFinite(rect.x) || !Number.isFinite(rect.y) || !Number.isFinite(rect.width) ||
    !Number.isFinite(rect.height) || rect.width < 0 || rect.height <= 0 ||
    rect.width > 32768 || rect.height > 32768) { return null; }
  const x: number = Math.max(0, rect.x);
  const y: number = Math.max(0, rect.y);
  const right: number = Math.min(frameWidth, rect.x + Math.max(1, rect.width));
  const bottom: number = Math.min(frameHeight, rect.y + rect.height);
  return right > x && bottom > y ? { x, y, width: right - x, height: bottom - y } : null;
}

function copyTarget(target: RemoteTextTarget): RemoteTextTarget {
  return { owner: copyRemoteTextOwner(target.owner), source: target.source,
    focusToken: target.focusToken, sequence: target.sequence, editable: target.editable,
    readOnly: target.readOnly, enabled: target.enabled, visible: target.visible,
    verified: target.verified, inputKind: target.inputKind,
    controlRect: copyRemoteInputRect(target.controlRect), caretRect: copyRemoteInputRect(target.caretRect) };
}

/** No text, password, window title, persisted focus or wall-clock comparison. */
export class RemoteTextInputSession {
  private owner: RemoteTextOwner | null = null;
  private target: RemoteTextTarget | null = null;
  private lastSequences: number[] = [-1, -1, -1, -1];
  private intentAt: number = -1;
  private intentUntil: number = -1;
  private suppressedToken: string = '';
  private inputGeneration: number = 0;
  private sourceAvailable: boolean = false;

  setOwner(owner: RemoteTextOwner): void {
    if (this.owner !== null && sameRemoteTextOwner(this.owner, owner)) { return; }
    this.reset();
    this.owner = copyRemoteTextOwner(owner);
  }

  reset(): void {
    this.owner = null;
    this.target = null;
    this.lastSequences = [-1, -1, -1, -1];
    this.intentAt = -1;
    this.intentUntil = -1;
    this.suppressedToken = '';
    this.sourceAvailable = false;
    this.inputGeneration++;
  }

  /** Called after the page's queue/transport barrier, before a focus-changing operation. */
  beginFocusMutation(now: number): number {
    this.target = null;
    this.suppressedToken = '';
    this.intentAt = Number.isFinite(now) ? now : -1;
    this.intentUntil = Number.isFinite(now) ? now + REMOTE_TEXT_USER_INTENT_MS : -1;
    return ++this.inputGeneration;
  }

  recordUserIntent(now: number): void {
    if (!Number.isFinite(now)) { return; }
    this.suppressedToken = '';
    this.intentAt = now;
    this.intentUntil = now + REMOTE_TEXT_USER_INTENT_MS;
  }

  /** Authenticated binding changes only this source on an otherwise identical native/capture owner. */
  bindDesktop(binding: string): void {
    if (this.owner === null || this.owner.desktopBinding === binding) { return; }
    this.owner.desktopBinding = binding;
    this.lastSequences[this.sourceIndex('hostHelper')] = -1;
    this.sourceAvailable = false;
    if (this.target !== null && this.target.source === 'compatibilityClick') { this.target.owner.desktopBinding = binding; }
    else { this.target = null; }
    this.inputGeneration++;
  }

  restartHelperSource(): void {
    this.lastSequences[this.sourceIndex('hostHelper')] = -1;
    this.sourceLost();
  }

  recordClick(x: number, y: number, sequence: number, now: number): boolean {
    if (this.owner === null) { return false; }
    const rect: RemoteInputRect | null = boundedRemoteInputRect(
      { x: x - 2, y: y - 12, width: 4, height: 24 }, this.owner.frameWidth, this.owner.frameHeight);
    if (rect === null) { return false; }
    this.recordUserIntent(now);
    return this.acceptTarget({ owner: this.owner, source: 'compatibilityClick',
      focusToken: 'click:' + this.inputGeneration.toString(), sequence,
      editable: false, readOnly: false, enabled: true, visible: true, verified: false,
      inputKind: 'unknown', controlRect: rect, caretRect: null });
  }

  /** Relative-only pointer lanes know that a click occurred, but cannot invent its remote position. */
  recordUnlocatedClick(sequence: number, now: number): boolean {
    if (this.owner === null) { return false; }
    this.recordUserIntent(now);
    return this.acceptTarget({ owner: this.owner, source: 'compatibilityClick',
      focusToken: 'click:' + this.inputGeneration.toString(), sequence, editable: false,
      readOnly: false, enabled: true, visible: true, verified: false, inputKind: 'unknown',
      controlRect: null, caretRect: null });
  }

  acceptTarget(event: RemoteTextTarget): boolean {
    const sourceIndex: number = this.sourceIndex(event.source);
    if (this.owner === null || this.owner.sessionId <= 0 || this.owner.generation <= 0 ||
      !sameRemoteTextOwner(this.owner, event.owner) || !Number.isSafeInteger(event.sequence) ||
      sourceIndex < 0 || event.sequence <= this.lastSequences[sourceIndex] ||
      event.focusToken.length === 0 || event.focusToken.length > 128 ||
      (event.source === 'rdpTextChannel' && this.owner.protocol !== 'rdp') ||
      (event.source === 'terminal' && this.owner.protocol !== 'ssh') ||
      (event.source !== 'compatibilityClick' && !event.verified) ||
      (event.source === 'hostHelper' && this.owner.desktopBinding.length === 0)) { return false; }
    this.lastSequences[sourceIndex] = event.sequence;
    if (!event.enabled || !event.visible || event.readOnly ||
      (!event.editable && event.source !== 'compatibilityClick' && event.source !== 'terminal')) {
      this.target = null;
      return true;
    }
    const rect: RemoteInputRect | null = boundedRemoteInputRect(event.controlRect,
      this.owner.frameWidth, this.owner.frameHeight);
    const caret: RemoteInputRect | null = boundedRemoteInputRect(event.caretRect,
      this.owner.frameWidth, this.owner.frameHeight);
    this.target = copyTarget(event);
    this.target.controlRect = rect;
    this.target.caretRect = caret;
    this.sourceAvailable = event.source !== 'compatibilityClick';
    return true;
  }

  loseFocus(token: string, sequence: number): boolean {
    if (this.target === null || token !== this.target.focusToken ||
      !Number.isSafeInteger(sequence) || sequence <= this.lastSequences[this.sourceIndex(this.target.source)]) {
      return false;
    }
    this.lastSequences[this.sourceIndex(this.target.source)] = sequence;
    this.target = null;
    this.inputGeneration++;
    return true;
  }

  sourceLost(): void {
    this.sourceAvailable = false;
    if (this.target !== null && this.target.source !== 'compatibilityClick') {
      this.target = null;
      this.inputGeneration++;
    }
  }

  suppressKeyboard(): void {
    this.intentAt = -1;
    this.intentUntil = -1;
    this.suppressedToken = this.target === null ? '*' : this.target.focusToken;
  }

  canAutoOpen(context: RemoteTextOpenContext, now: number): boolean {
    if (context.policy === 'off' || !context.virtualInput || !context.connected || !context.inputReady ||
      !context.foreground || context.modalOwnsInput || context.readOnly || context.keyboardOpen ||
      this.target === null || this.suppressedToken === '*' ||
      this.suppressedToken === this.target.focusToken || !Number.isFinite(now) || now < this.intentAt || now > this.intentUntil) {
      return false;
    }
    if (context.policy === 'compatibilityClick') { return true; }
    return this.sourceAvailable && this.target.verified &&
      (this.target.editable || this.target.source === 'terminal');
  }

  snapshot(): RemoteTextTarget | null { return this.target === null ? null : copyTarget(this.target); }
  generation(): number { return this.inputGeneration; }
  private sourceIndex(source: RemoteTextSource): number {
    if (source === 'terminal') { return 0; }
    if (source === 'rdpTextChannel') { return 1; }
    if (source === 'hostHelper') { return 2; }
    return source === 'compatibilityClick' ? 3 : -1;
  }
  targetRect(): RemoteInputRect | null {
    return this.target === null ? null : copyRemoteInputRect(this.target.caretRect ?? this.target.controlRect);
  }
}

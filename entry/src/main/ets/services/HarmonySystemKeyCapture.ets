import rdpnapi, { SystemKeyCaptureEvent } from 'librdpnapi.so';
import { inputConsumer } from '@kit.InputKit';
import { HARMONY_HOTKEY_SEED, HarmonyHotkeySeed } from './HarmonySystemHotkeySeed';
import { hilog } from '@kit.PerformanceAnalysisKit';

export interface HarmonySystemHotkey { preKeys: Array<number>; finalKey: number; }
export interface HarmonySystemHotkeyEvidence {
  id: string; preKeys: Array<number>; finalKey: number; seedIds: Array<string>; status: string;
}
export interface HarmonySystemHotkeyReport {
  schema: number; deviceType: string; apiVersion: number; osVersion: string;
  state: string; captureStatus: number; coverage: string; entries: Array<HarmonySystemHotkeyEvidence>;
}
export type HarmonySystemKeySender = (keyCode: number, pressed: boolean) => boolean;

const RELEASE_RETRY_BASE_MS: number = 200;
const RELEASE_RETRY_MAX_MS: number = 5000;

/** Process interceptor: one active window and one source of key down/up at a time. */
export class HarmonySystemKeyCapture {
  private static shared: HarmonySystemKeyCapture = new HarmonySystemKeyCapture();
  private owner: string = '';
  private identity: string = '';
  private token: number = 0;
  private epoch: number = 0;
  private held: Array<number> = [];
  private sender: HarmonySystemKeySender | null = null;
  private statusCode: number = 0;
  private failedIdentity: string = '';
  private releaseTimer: number = -1;
  private releaseAttempts: number = 0;
  private releasePending: boolean = false;
  private releaseFailurePublished: boolean = false;
  private hotkeys: Array<HarmonySystemHotkey> = [];
  private catalogState: string = 'unknown';
  private inventoryEpoch: number = 0;

  static getInstance(): HarmonySystemKeyCapture { return HarmonySystemKeyCapture.shared; }
  activeFor(owner: string): boolean { return this.owner === owner && this.token > 0 && !this.releasePending; }
  resetFailure(): void { this.failedIdentity = ''; }
  private publishCapability(code: number): void {
    AppStorage.setOrCreate<string>('systemKeyCaptureCapability', code === 0 ? 'available' :
      (code === 201 || code === 202 ? 'permission-denied' : (code === 801 ? 'unsupported' : 'failed')));
    AppStorage.setOrCreate<number>('systemKeyCaptureCode', code);
  }
  status(): number { return this.statusCode; }
  inventoryState(): string { return this.catalogState; }
  inventory(): Array<HarmonySystemHotkey> {
    return this.hotkeys.map((item: HarmonySystemHotkey): HarmonySystemHotkey =>
      ({ preKeys: item.preKeys.slice(), finalKey: item.finalKey }));
  }
  inventoryEvidence(): Array<HarmonySystemHotkeyEvidence> {
    return this.hotkeys.map((item: HarmonySystemHotkey): HarmonySystemHotkeyEvidence => {
      const signature: string = Array.from(new Set<number>(item.preKeys))
        .sort((a: number, b: number): number => a - b).join('+') + ':' + item.finalKey.toString();
      const seed: HarmonyHotkeySeed | undefined = HARMONY_HOTKEY_SEED.find(
        (candidate: HarmonyHotkeySeed): boolean => candidate.signature === signature);
      return { id: 'runtime:' + signature, preKeys: item.preKeys.slice(), finalKey: item.finalKey,
        seedIds: seed === undefined ? [] : seed.ids.slice(),
        status: seed === undefined ? 'UNKNOWN_DEVICE_OPEN' : 'CANDIDATE_DEVICE_OPEN' };
    });
  }
  inventoryReport(deviceType: string, apiVersion: number, osVersion: string): string {
    const report: HarmonySystemHotkeyReport = { schema: 1, deviceType, apiVersion, osVersion,
      state: this.catalogState, captureStatus: this.statusCode, coverage: 'DEVICE_OPEN',
      entries: this.inventoryEvidence() };
    return JSON.stringify(report, null, 2);
  }
  async refreshInventory(): Promise<void> {
    const epoch: number = ++this.inventoryEpoch;
    try {
      const items = await inputConsumer.getAllSystemHotkeys();
      if (epoch !== this.inventoryEpoch) { return; }
      this.hotkeys = items.map((item: inputConsumer.HotkeyOptions): HarmonySystemHotkey =>
        ({ preKeys: item.preKeys.slice().sort((a: number, b: number): number => a - b), finalKey: item.finalKey }));
      this.catalogState = items.length > 0 ? 'reported' : 'empty-unverified';
    } catch (_error) {
      if (epoch !== this.inventoryEpoch) { return; }
      this.hotkeys = []; this.catalogState = 'unavailable';
    }
    AppStorage.setOrCreate<string>('systemHotkeyInventoryState', this.catalogState);
    AppStorage.setOrCreate<number>('systemHotkeyInventoryCount', this.hotkeys.length);
    AppStorage.setOrCreate<number>('systemHotkeyUnknownCount', this.inventoryEvidence().filter(
      (item: HarmonySystemHotkeyEvidence): boolean => item.seedIds.length === 0).length);
  }
  activate(owner: string, identity: string, windowId: number,
    eligible: () => boolean, send: HarmonySystemKeySender): boolean {
    if (!eligible() || windowId < 0 || owner.length === 0) { this.deactivate(owner); return false; }
    if (this.activeFor(owner) && this.identity === identity) { return true; }
    if (this.token > 0) { this.deactivate(this.owner); }
    if (this.token > 0 || this.failedIdentity === identity) { return false; }
    const epoch: number = ++this.epoch;
    this.owner = owner; this.identity = identity; this.sender = send; this.held = [];
    try {
      const result = rdpnapi.startSystemKeyCapture((event: SystemKeyCaptureEvent): void => {
        if (epoch !== this.epoch || event.token !== this.token || this.releasePending) { return; }
        if (event.overflow !== 0 || !eligible() || event.windowId !== windowId) {
          this.deactivate(owner); return;
        }
        if (event.action === 0) { this.releaseHeld(); return; }
        if (event.action !== 1 && event.action !== 2) { return; }
        const down: boolean = event.action === 1;
        const index: number = this.held.indexOf(event.keyCode);
        // Ignore UP for a key whose DOWN belonged to a different owner/capture generation.
        if (!down && index < 0) { return; }
        let accepted: boolean = false;
        try { accepted = send(event.keyCode, down); } catch (_error) {}
        if (!accepted) { this.deactivate(owner); return; }
        if (down && index < 0) { this.held.push(event.keyCode); }
        else if (!down) { this.held.splice(index, 1); }
      });
      this.statusCode = result.status; this.publishCapability(result.status);
      if (result.status === 0 && result.token > 0) {
        this.token = result.token; this.failedIdentity = ''; this.releaseAttempts = 0;
        return true;
      }
    } catch (_error) { this.statusCode = -1; }
    this.publishCapability(this.statusCode);
    this.failedIdentity = identity; this.owner = ''; this.sender = null;
    hilog.warn(0x0014, 'SystemKeyCapture', 'capture unavailable code=' + this.statusCode.toString());
    return false;
  }
  deactivate(owner: string): void {
    if (owner !== this.owner) { return; }
    this.epoch++; this.releasePending = true;
    this.releaseHeld();
    if (this.token <= 0) { this.finishRelease(); return; }
    try { this.statusCode = rdpnapi.stopSystemKeyCapture(this.token); }
    catch (_error) { this.statusCode = -1; }
    if (this.statusCode === 0) { this.finishRelease(); return; }
    AppStorage.setOrCreate<string>('systemKeyCaptureCapability', 'release-failed');
    this.releaseFailurePublished = true;
    // Keep the failed removal token. Never admit another owner or claim local input was restored.
    // The interceptor still swallows local keys, so keep retrying with a capped backoff until
    // the system releases it; a later activate() also retries immediately.
    if (this.releaseTimer < 0) {
      const delay: number = Math.min(RELEASE_RETRY_MAX_MS, RELEASE_RETRY_BASE_MS * Math.pow(2,
        Math.min(this.releaseAttempts, 5)));
      this.releaseAttempts++;
      this.releaseTimer = setTimeout((): void => { this.releaseTimer = -1; this.deactivate(owner); }, delay);
    }
  }
  private releaseHeld(): void {
    const held: Array<number> = this.held.slice().reverse(); this.held = [];
    const send: HarmonySystemKeySender | null = this.sender;
    if (send === null) { return; }
    for (const code of held) { try { send(code, false); } catch (_error) {} }
  }
  private finishRelease(): void {
    if (this.releaseTimer >= 0) { clearTimeout(this.releaseTimer); this.releaseTimer = -1; }
    this.token = 0; this.owner = ''; this.identity = ''; this.sender = null; this.releasePending = false;
    this.releaseAttempts = 0;
    if (this.releaseFailurePublished) { this.releaseFailurePublished = false; this.publishCapability(0); }
  }
}

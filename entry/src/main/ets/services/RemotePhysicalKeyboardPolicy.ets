/**
 * Physical-keyboard policy for RDP and RustDesk remote sessions.
 *
 * RDP is a Windows-only remote desktop protocol in this app, so it always
 * uses the Windows layout. RustDesk, VNC and Moonlight can target macOS or
 * Windows and therefore require an explicit choice.
 */
export enum RemoteKeyboardLayout {
  WINDOWS = 'windows',
  MACOS = 'macos'
}

/** PC sessions default to the physical keyboard/mouse path (mode 2). */
export function remoteControlModeDefaultForDevice(isDesktopDevice: boolean): number {
  return isDesktopDevice ? 2 : 0;
}

export const HARMONY_KEYCODE_CTRL_LEFT: number = 2072;
export const HARMONY_KEYCODE_CTRL_RIGHT: number = 2073;
export const HARMONY_KEYCODE_META_LEFT: number = 2076;
export const HARMONY_KEYCODE_META_RIGHT: number = 2077;
export const MACOS_CAPS_LOCK_LONG_PRESS_MS: number = 350;

export function isMacCapsLockLongPress(durationMs: number): boolean {
  return durationMs >= MACOS_CAPS_LOCK_LONG_PRESS_MS;
}

export function mapPhysicalKeyForRemoteLayout(layout: RemoteKeyboardLayout, keyCode: number): number {
  if (layout !== RemoteKeyboardLayout.MACOS) {
    return keyCode;
  }
  switch (keyCode) {
    case HARMONY_KEYCODE_CTRL_LEFT: return HARMONY_KEYCODE_META_LEFT;
    case HARMONY_KEYCODE_CTRL_RIGHT: return HARMONY_KEYCODE_META_RIGHT;
    case HARMONY_KEYCODE_META_LEFT: return HARMONY_KEYCODE_CTRL_LEFT;
    case HARMONY_KEYCODE_META_RIGHT: return HARMONY_KEYCODE_CTRL_RIGHT;
    default: return keyCode;
  }
}

/**
 * The keyboard physically attached to this device. A Mac (Apple) keyboard reports
 * Command as META and Control as CTRL; a PC keyboard reports Ctrl and Win.
 */
export enum LocalKeyboardKind {
  PC = 'pc',
  MAC = 'mac'
}

/** User choice for the local keyboard: detect from the device, or force one kind. */
export type LocalKeyboardPreference = 'auto' | 'pc' | 'mac';
export const LOCAL_KEYBOARD_KIND_STORAGE_KEY: string = 'remoteLocalKeyboardKind';
const APPLE_USB_VENDOR_ID: number = 0x05AC;
/** Apple's Bluetooth SIG company id, reported by Bluetooth Magic Keyboards. */
const APPLE_BLUETOOTH_VENDOR_ID: number = 0x004C;

export function normalizeLocalKeyboardPreference(value: string | undefined | null): LocalKeyboardPreference {
  return value === 'pc' || value === 'mac' ? value : 'auto';
}

/** Apple keyboards (USB vendor 0x05AC, Bluetooth company 0x004C, or a Magic/Apple keyboard name). */
export function detectLocalKeyboardKind(vendorId: number, name: string): LocalKeyboardKind {
  const lower: string = name.trim().toLowerCase();
  if (vendorId === APPLE_USB_VENDOR_ID || vendorId === APPLE_BLUETOOTH_VENDOR_ID ||
    lower.indexOf('apple') >= 0 || lower.indexOf('magic keyboard') >= 0 ||
    lower.indexOf('macbook') >= 0) {
    return LocalKeyboardKind.MAC;
  }
  return LocalKeyboardKind.PC;
}

export function resolveLocalKeyboardKind(preference: LocalKeyboardPreference,
  detected: LocalKeyboardKind): LocalKeyboardKind {
  if (preference === 'pc') { return LocalKeyboardKind.PC; }
  if (preference === 'mac') { return LocalKeyboardKind.MAC; }
  return detected;
}

/**
 * Ctrl and Command change places exactly when the local keyboard and the remote system
 * disagree: a PC keyboard driving macOS (Ctrl → Command, Win → Control), or a Mac keyboard
 * driving Windows/Linux (Command → Ctrl, Control → Win). A Mac keyboard on macOS and a PC
 * keyboard on Windows keep every key.
 */
export function shouldSwapCtrlMeta(remote: RemoteKeyboardLayout, local: LocalKeyboardKind): boolean {
  return (remote === RemoteKeyboardLayout.MACOS) !== (local === LocalKeyboardKind.MAC);
}

export function mapPhysicalKeyForRemote(remote: RemoteKeyboardLayout, local: LocalKeyboardKind,
  keyCode: number): number {
  return mapPhysicalKeyForRemoteLayout(shouldSwapCtrlMeta(remote, local) ?
    RemoteKeyboardLayout.MACOS : RemoteKeyboardLayout.WINDOWS, keyCode);
}

/** The remote system a RustDesk PeerInfo platform names, or null when it is unknown. */
export function remoteKeyboardLayoutForPeerPlatform(platform: string): RemoteKeyboardLayout | null {
  const value: string = platform.trim().toLowerCase();
  if (value === 'macos' || value === 'mac os' || value === 'mac' || value === 'darwin') {
    return RemoteKeyboardLayout.MACOS;
  }
  if (value === 'windows' || value === 'linux') { return RemoteKeyboardLayout.WINDOWS; }
  return null;
}

/** Remote-side modifier state after the Ctrl/Command mapping, for chords the app handles itself. */
export interface RemoteModifierChordState {
  ctrl: boolean;
  meta: boolean;
}

export function remoteModifierChordState(swap: boolean, physicalCtrlDown: boolean,
  physicalWinDown: boolean): RemoteModifierChordState {
  return swap ? { ctrl: physicalWinDown, meta: physicalCtrlDown } :
    { ctrl: physicalCtrlDown, meta: physicalWinDown };
}

export function shouldChoosePhysicalKeyboardLayout(protocol: string, _isDesktopDevice: boolean,
  _breakpoint: string): boolean {
  // 键盘布局描述的是远端系统，不取决于控制端是 PC、Pad 还是 Phone。
  // RDP 目标固定为 Windows；RustDesk/VNC must not infer a remote OS from
  // the controller, so they use an explicit session choice.
  return protocol === 'rustdesk' || protocol === 'vnc' || protocol === 'moonlight';
}

/** RDP always targets Windows, including when a session surface is reused. */
export function physicalKeyboardLayoutForProtocol(protocol: string,
  selectedLayout: RemoteKeyboardLayout): RemoteKeyboardLayout {
  return protocol === 'rdp' ? RemoteKeyboardLayout.WINDOWS : selectedLayout;
}

export function shouldConsumeRemoteBack(connected: boolean, isDesktopDevice: boolean,
  _breakpoint: string, keyboardMouseMode: boolean, physicalKeyboardConnected: boolean,
  hardwareKeyboardProxyActive: boolean): boolean {
  return connected && isDesktopDevice && keyboardMouseMode &&
    physicalKeyboardConnected && hardwareKeyboardProxyActive;
}

export function shouldAutoSwitchVncKeyboardMouseMode(
  protocol: string,
  connected: boolean,
  viewOnly: boolean,
  externalKeyboardMouseConnected: boolean,
  currentMode: number,
  sessionId: number,
  alreadyAppliedSessionId: number
): boolean {
  return protocol === 'vnc' && connected && !viewOnly &&
    externalKeyboardMouseConnected && currentMode !== 2 && sessionId > 0 &&
    alreadyAppliedSessionId !== sessionId;
}

export function remoteKeyboardLayoutDescription(layout: RemoteKeyboardLayout): string {
  if (layout === RemoteKeyboardLayout.MACOS) {
    return 'PC 键盘：Ctrl 作 Command、Win 作 Control；Mac 键盘按原键位。两种键盘的 Caps Lock 短按都切换输入法。';
  }
  return 'PC 键盘按原键位；Mac 键盘的 Command 作 Ctrl、Control 作 Win，复制粘贴习惯不变。';
}

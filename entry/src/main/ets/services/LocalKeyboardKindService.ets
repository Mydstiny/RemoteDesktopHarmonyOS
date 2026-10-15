import { inputDevice } from '@kit.InputKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  detectLocalKeyboardKind,
  LOCAL_KEYBOARD_KIND_STORAGE_KEY,
  LocalKeyboardKind,
  normalizeLocalKeyboardPreference,
  resolveLocalKeyboardKind
} from './RemotePhysicalKeyboardPolicy';

/**
 * Which keyboard (Apple or PC) produced a key event. Detected once per input device from
 * its vendor/name; the user preference (auto / pc / mac) overrides the detection. Events
 * without a device (the native interceptor) use the keyboard that sent the last ArkUI event,
 * or, before any, the attached alphabetic keyboards (Mac when any of them is an Apple one).
 */
export class LocalKeyboardKindService {
  private static shared: LocalKeyboardKindService = new LocalKeyboardKindService();
  private byDevice: Map<number, LocalKeyboardKind> = new Map<number, LocalKeyboardKind>();
  private lastSeen: LocalKeyboardKind | null = null;
  private attached: LocalKeyboardKind = LocalKeyboardKind.PC;
  private watching: boolean = false;

  static getInstance(): LocalKeyboardKindService { return LocalKeyboardKindService.shared; }

  /** Track attached keyboards for device-less events; safe to call repeatedly. */
  watchDevices(): void {
    if (this.watching) { return; }
    this.watching = true;
    try {
      inputDevice.on('change', (data: inputDevice.DeviceListener): void => {
        // Ids can be reused after a removal, and the last keyboard used may be the one removed.
        this.byDevice.delete(data.deviceId);
        this.lastSeen = null;
        this.refreshAttached();
      });
    } catch (error) {
      hilog.warn(0x0014, 'LocalKeyboard', 'device watch unavailable: ' + JSON.stringify(error));
    }
    this.refreshAttached();
  }

  kindFor(deviceId: number): LocalKeyboardKind {
    this.watchDevices();
    let detected: LocalKeyboardKind = this.lastSeen !== null ? this.lastSeen : this.attached;
    if (deviceId >= 0) {
      const cached: LocalKeyboardKind | undefined = this.byDevice.get(deviceId);
      if (cached !== undefined) {
        detected = cached;
      } else {
        const probed: LocalKeyboardKind | null = this.probe(deviceId, false);
        // A failed probe is not cached, so the next event retries it.
        if (probed !== null) {
          detected = probed;
          this.byDevice.set(deviceId, probed);
          hilog.info(0x0014, 'LocalKeyboard', 'device=' + deviceId.toString() + ' kind=' + probed);
        }
      }
      this.lastSeen = detected;
    }
    const preference: string = AppStorage.get<string>(LOCAL_KEYBOARD_KIND_STORAGE_KEY) ?? 'auto';
    return resolveLocalKeyboardKind(normalizeLocalKeyboardPreference(preference), detected);
  }

  /** Kind of one device; null when it cannot be read or (alphabeticOnly) is not a typing keyboard. */
  private probe(deviceId: number, alphabeticOnly: boolean): LocalKeyboardKind | null {
    try {
      const info: inputDevice.InputDeviceData = inputDevice.getDeviceInfoSync(deviceId);
      if (alphabeticOnly && (info.sources.indexOf('keyboard') < 0 ||
        inputDevice.getKeyboardTypeSync(deviceId) !== inputDevice.KeyboardType.ALPHABETIC_KEYBOARD)) {
        return null;
      }
      return detectLocalKeyboardKind(info.vendor, info.name);
    } catch (_error) {
      return null;
    }
  }

  private refreshAttached(): void {
    inputDevice.getDeviceList().then((ids: Array<number>): void => {
      let kind: LocalKeyboardKind = LocalKeyboardKind.PC;
      for (let index = 0; index < ids.length; index++) {
        if (this.probe(ids[index], true) === LocalKeyboardKind.MAC) {
          kind = LocalKeyboardKind.MAC;
          break;
        }
      }
      this.attached = kind;
      hilog.info(0x0014, 'LocalKeyboard', 'input devices=' + ids.length.toString() + ' kind=' + kind);
    }).catch((error: Error): void => {
      hilog.warn(0x0014, 'LocalKeyboard', 'device list failed: ' + JSON.stringify(error));
    });
  }
}

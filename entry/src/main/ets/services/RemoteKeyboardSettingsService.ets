import { RemotePreferencePort, RemotePreferenceScalar, writeRemoteKeyboardPreferences } from './RemoteKeyboardPreferencesTransaction';
import { LOCAL_KEYBOARD_KIND_STORAGE_KEY, normalizeLocalKeyboardPreference } from './RemotePhysicalKeyboardPolicy';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { settings } from '@kit.BasicServicesKit';
import { inputMethod, InputMethodSubtype } from '@kit.IMEKit';
import {
  defaultRemoteKeyboardBehavior, RemoteKeyboardBehavior,
  normalizeRemoteKeyboardAutoOpenPolicy, normalizeRemoteKeyboardInputIntent,
  normalizeRemoteKeyboardPlacement, normalizeRemoteKeyboardGap,
  REMOTE_KEYBOARD_BEHAVIOR_VERSION_KEY, REMOTE_KEYBOARD_AUTO_OPEN_POLICY_KEY,
  REMOTE_KEYBOARD_INPUT_INTENT_KEY, REMOTE_KEYBOARD_AVOIDANCE_ENABLED_KEY,
  REMOTE_KEYBOARD_PLACEMENT_KEY, REMOTE_KEYBOARD_GAP_KEY
} from './RemoteTextInputPolicy';
import {
  decodeRemoteCustomShortcuts,
  encodeRemoteCustomShortcuts,
  RemoteCustomShortcut,
  REMOTE_CUSTOM_SHORTCUT_STORAGE_KEY
} from './RemoteCustomShortcutPolicy';
import {
  defaultRemoteKeyboardPreferences,
  normalizeRemoteKeyboardPreferences,
  normalizeRemoteShortcutPlatform,
  RemoteKeyboardPreferences,
  RemoteShortcutPlatform,
  REMOTE_KEYBOARD_CLOSE_AFTER_SHORTCUT_KEY,
  REMOTE_KEYBOARD_AUTO_OPEN_ON_REMOTE_CLICK_KEY,
  REMOTE_KEYBOARD_FUNCTION_KEYS_VISIBLE_KEY,
  REMOTE_KEYBOARD_PREFERENCES_NAME,
  REMOTE_KEYBOARD_SHORTCUT_PLATFORM_KEY,
  REMOTE_KEYBOARD_SIMPLE_MODE_KEY
} from './RemoteKeyboardSettingsPolicy';
import {
  decodeHarmonyShortcutBlockingPreferences,
  disabledHarmonyShortcutBlockingPreferences,
  encodeHarmonyShortcutBlockingPreferences,
  HarmonyShortcutBlockingPreferences,
  HarmonyShortcutDeviceClass,
  HarmonyShortcutProtocol,
  HarmonyShortcutStorageTransactionPort,
  HARMONY_SYSTEM_KEY_CAPTURE_STORAGE_KEY,
  mutateHarmonyShortcutBlockingPreferences,
  readHarmonyShortcutBlockingPreferences,
  HARMONY_SHORTCUT_BLOCKING_STORAGE_KEY
} from './HarmonyShortcutBlockingPolicy';

export interface RemoteSystemInputMethodInfo {
  bundleName: string;
  inputMethodId: string;
  label: string;
  current: boolean;
  enabled: boolean;
  subtypeSummary: string;
}
export interface RemoteSystemInputMethodSnapshot {
  available: boolean;
  currentLabel: string;
  currentSubtype: string;
  methods: Array<RemoteSystemInputMethodInfo>;
  error: string;
}

function inputMethodKey(method: inputMethod.InputMethodProperty): string {
  return method.name + ':' + method.id;
}

function inputMethodLabel(method: inputMethod.InputMethodProperty): string {
  const label: string = method.label ?? '';
  return label.trim().length > 0 ? label.trim() : method.name;
}

function subtypeLabel(subtype: InputMethodSubtype): string {
  const label: string = subtype.label ?? '';
  if (label.trim().length > 0) { return label.trim(); }
  if (subtype.locale.trim().length > 0) { return subtype.locale.trim(); }
  if (subtype.language.trim().length > 0) { return subtype.language.trim(); }
  return subtype.name;
}

function emptySystemSnapshot(error: string = ''): RemoteSystemInputMethodSnapshot {
  return {
    available: false,
    currentLabel: '',
    currentSubtype: '',
    methods: [],
    error
  };
}

class HarmonyShortcutPreferencesPort implements HarmonyShortcutStorageTransactionPort {
  private readonly values: preferences.Preferences;

  constructor(values: preferences.Preferences) {
    this.values = values;
  }

  has(key: string): boolean { return this.values.hasSync(key); }

  get(key: string, fallback: string): string {
    return this.values.getSync(key, fallback) as string;
  }

  put(key: string, value: string): void { this.values.putSync(key, value); }

  delete(key: string): void { this.values.deleteSync(key); }

  flush(): void { this.values.flushSync(); }

  publish(key: string, value: string): void {
    AppStorage.setOrCreate<string>(key, value);
  }
}

class RemoteKeyboardPreferencesPort implements RemotePreferencePort {
  private readonly prefs: preferences.Preferences;
  constructor(prefs: preferences.Preferences) { this.prefs = prefs; }
  has(key: string): boolean { return this.prefs.hasSync(key); }
  get(key: string): RemotePreferenceScalar { return this.prefs.getSync(key, '') as RemotePreferenceScalar; }
  put(key: string, value: RemotePreferenceScalar): void { this.prefs.putSync(key, value); }
  delete(key: string): void { this.prefs.deleteSync(key); }
  flush(): void { this.prefs.flushSync(); }
}

export class RemoteKeyboardSettingsService {
  private static instance: RemoteKeyboardSettingsService | null = null;
  private appContext: common.Context | null = null;
  private lastPreferences: RemoteKeyboardPreferences | null = null;
  private preferencesReadFailed: boolean = false;
  private futurePreferencesVersion: boolean = false;
  private preferencesWriteFault: boolean = false;

  private copyPreferences(values: RemoteKeyboardPreferences): RemoteKeyboardPreferences {
    return normalizeRemoteKeyboardPreferences(values.shortcutPlatform, values.simpleKeyboardEnabled,
      values.functionKeysVisible, values.closePanelAfterShortcut, values.autoOpenOnRemoteClick, values.behavior);
  }

  static getInstance(): RemoteKeyboardSettingsService {
    if (RemoteKeyboardSettingsService.instance === null) {
      RemoteKeyboardSettingsService.instance = new RemoteKeyboardSettingsService();
    }
    return RemoteKeyboardSettingsService.instance;
  }

  init(context: common.Context): RemoteKeyboardPreferences {
    this.appContext = context;
    const values: RemoteKeyboardPreferences = this.loadPreferences(context);
    this.publish(values);
    const harmonyShortcutBlocking: HarmonyShortcutBlockingPreferences | null =
      this.tryLoadHarmonyShortcutBlocking(context);
    if (harmonyShortcutBlocking !== null) {
      this.publishHarmonyShortcutBlocking(harmonyShortcutBlocking);
    }
    this.loadSystemKeyCaptureEnabled(context);
    this.loadLocalKeyboardPreference(context);
    this.applySimpleKeyboardMode(values.simpleKeyboardEnabled);
    return values;
  }

  /** Local keyboard kind ('auto' | 'pc' | 'mac'); published to AppStorage. */
  loadLocalKeyboardPreference(context?: common.Context): string {
    const activeContext: common.Context | null = context ?? this.appContext;
    let value: string = AppStorage.get<string>(LOCAL_KEYBOARD_KIND_STORAGE_KEY) ?? 'auto';
    if (activeContext !== null) {
      try {
        const prefs: preferences.Preferences = preferences.getPreferencesSync(
          activeContext, { name: REMOTE_KEYBOARD_PREFERENCES_NAME });
        value = prefs.getSync(LOCAL_KEYBOARD_KIND_STORAGE_KEY, 'auto') as string;
      } catch (_error) { /* keep the runtime value */ }
    }
    const normalized: string = normalizeLocalKeyboardPreference(value);
    AppStorage.setOrCreate<string>(LOCAL_KEYBOARD_KIND_STORAGE_KEY, normalized);
    return normalized;
  }

  saveLocalKeyboardPreference(value: string, context?: common.Context): boolean {
    const normalized: string = normalizeLocalKeyboardPreference(value);
    const activeContext: common.Context | null = context ?? this.appContext;
    if (activeContext === null) { return false; }
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(
        activeContext, { name: REMOTE_KEYBOARD_PREFERENCES_NAME });
      prefs.putSync(LOCAL_KEYBOARD_KIND_STORAGE_KEY, normalized);
      prefs.flushSync();
    } catch (_error) {
      return false;
    }
    AppStorage.setOrCreate<string>(LOCAL_KEYBOARD_KIND_STORAGE_KEY, normalized);
    return true;
  }

  /** Full physical-key capture opt-in (default off); published to AppStorage. */
  loadSystemKeyCaptureEnabled(context?: common.Context): boolean {
    const activeContext: common.Context | null = context ?? this.appContext;
    let enabled: boolean = AppStorage.get<boolean>(HARMONY_SYSTEM_KEY_CAPTURE_STORAGE_KEY) ?? false;
    if (activeContext !== null) {
      try {
        const prefs: preferences.Preferences = preferences.getPreferencesSync(
          activeContext, { name: REMOTE_KEYBOARD_PREFERENCES_NAME });
        enabled = prefs.getSync(HARMONY_SYSTEM_KEY_CAPTURE_STORAGE_KEY, false) === true;
      } catch (_error) {
        // Keep the runtime value; capture stays off unless it was already opted in.
      }
    }
    AppStorage.setOrCreate<boolean>(HARMONY_SYSTEM_KEY_CAPTURE_STORAGE_KEY, enabled);
    return enabled;
  }

  saveSystemKeyCaptureEnabled(enabled: boolean, context?: common.Context): boolean {
    const activeContext: common.Context | null = context ?? this.appContext;
    if (activeContext === null) { return false; }
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(
        activeContext, { name: REMOTE_KEYBOARD_PREFERENCES_NAME });
      prefs.putSync(HARMONY_SYSTEM_KEY_CAPTURE_STORAGE_KEY, enabled);
      prefs.flushSync();
    } catch (_error) {
      return false;
    }
    AppStorage.setOrCreate<boolean>(HARMONY_SYSTEM_KEY_CAPTURE_STORAGE_KEY, enabled);
    return true;
  }

  loadHarmonyShortcutBlocking(
    context?: common.Context
  ): HarmonyShortcutBlockingPreferences {
    const loaded: HarmonyShortcutBlockingPreferences | null =
      this.tryLoadHarmonyShortcutBlocking(context);
    if (loaded !== null) { return loaded; }
    const runtimeEncoded: string | undefined =
      AppStorage.get<string>(HARMONY_SHORTCUT_BLOCKING_STORAGE_KEY);
    return runtimeEncoded === undefined ? disabledHarmonyShortcutBlockingPreferences() :
      decodeHarmonyShortcutBlockingPreferences(runtimeEncoded);
  }

  private tryLoadHarmonyShortcutBlocking(
    context?: common.Context
  ): HarmonyShortcutBlockingPreferences | null {
    const activeContext: common.Context | null = context ?? this.appContext;
    if (activeContext === null) { return null; }
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(
        activeContext, { name: REMOTE_KEYBOARD_PREFERENCES_NAME });
      return readHarmonyShortcutBlockingPreferences(
        new HarmonyShortcutPreferencesPort(prefs));
    } catch (_error) {
      return null;
    }
  }

  setHarmonyShortcutBlockingPreference(
    deviceClass: HarmonyShortcutDeviceClass,
    protocol: HarmonyShortcutProtocol,
    enabled: boolean,
    context?: common.Context
  ): HarmonyShortcutBlockingPreferences | null {
    const activeContext: common.Context | null = context ?? this.appContext;
    if (activeContext === null) { return null; }
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(
        activeContext, { name: REMOTE_KEYBOARD_PREFERENCES_NAME });
      return mutateHarmonyShortcutBlockingPreferences(
        new HarmonyShortcutPreferencesPort(prefs), deviceClass, protocol, enabled);
    } catch (_error) {
      return null;
    }
  }

  setHarmonyShortcutDeviceBlocking(
    deviceClass: HarmonyShortcutDeviceClass,
    enabled: boolean,
    context?: common.Context
  ): HarmonyShortcutBlockingPreferences | null {
    const activeContext: common.Context | null = context ?? this.appContext;
    if (activeContext === null) { return null; }
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(
        activeContext, { name: REMOTE_KEYBOARD_PREFERENCES_NAME });
      return mutateHarmonyShortcutBlockingPreferences(
        new HarmonyShortcutPreferencesPort(prefs), deviceClass, null, enabled);
    } catch (_error) {
      return null;
    }
  }

  loadPreferences(context?: common.Context): RemoteKeyboardPreferences {
    const defaults: RemoteKeyboardPreferences = defaultRemoteKeyboardPreferences();
    if (this.preferencesWriteFault) { this.preferencesReadFailed = true; return this.copyPreferences(this.lastPreferences ?? defaults); }
    const activeContext: common.Context | null = context ?? this.appContext;
    if (activeContext === null) { return defaults; }
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(
        activeContext, { name: REMOTE_KEYBOARD_PREFERENCES_NAME });
      const legacyClick: boolean = prefs.getSync(REMOTE_KEYBOARD_AUTO_OPEN_ON_REMOTE_CLICK_KEY,
        defaults.autoOpenOnRemoteClick) as boolean;
      const version: number = prefs.getSync(REMOTE_KEYBOARD_BEHAVIOR_VERSION_KEY, 0) as number;
      this.futurePreferencesVersion = version !== 0 && version !== 1;
      const behavior: RemoteKeyboardBehavior = version === 0 ? defaultRemoteKeyboardBehavior(legacyClick) : {
        version: 1,
        autoOpenPolicy: version === 1 ? normalizeRemoteKeyboardAutoOpenPolicy(
          prefs.getSync(REMOTE_KEYBOARD_AUTO_OPEN_POLICY_KEY, 'off') as string) : 'off',
        inputIntent: normalizeRemoteKeyboardInputIntent(prefs.getSync(REMOTE_KEYBOARD_INPUT_INTENT_KEY,
          'automatic') as string),
        avoidanceEnabled: prefs.getSync(REMOTE_KEYBOARD_AVOIDANCE_ENABLED_KEY, true) === true,
        placement: normalizeRemoteKeyboardPlacement(prefs.getSync(REMOTE_KEYBOARD_PLACEMENT_KEY,
          'nearKeyboard') as string),
        gapVp: normalizeRemoteKeyboardGap(prefs.getSync(REMOTE_KEYBOARD_GAP_KEY, 16) as number)
      };
      const loaded: RemoteKeyboardPreferences = normalizeRemoteKeyboardPreferences(
        prefs.getSync(REMOTE_KEYBOARD_SHORTCUT_PLATFORM_KEY,
          defaults.shortcutPlatform) as string,
        prefs.getSync(REMOTE_KEYBOARD_SIMPLE_MODE_KEY,
          defaults.simpleKeyboardEnabled) as boolean,
        prefs.getSync(REMOTE_KEYBOARD_FUNCTION_KEYS_VISIBLE_KEY,
          defaults.functionKeysVisible) as boolean,
        prefs.getSync(REMOTE_KEYBOARD_CLOSE_AFTER_SHORTCUT_KEY,
          defaults.closePanelAfterShortcut) as boolean,
        legacyClick, behavior
      );
      this.lastPreferences = this.copyPreferences(loaded);
      this.preferencesReadFailed = false;
      return loaded;
    } catch (_error) {
      this.preferencesReadFailed = true;
      return this.copyPreferences(this.lastPreferences ?? defaults);
    }
  }

  savePreferences(values: RemoteKeyboardPreferences,
    context?: common.Context): boolean {
    const activeContext: common.Context | null = context ?? this.appContext;
    if (activeContext === null) { return false; }
    const current: RemoteKeyboardPreferences = this.loadPreferences(activeContext);
    if (this.preferencesReadFailed || this.futurePreferencesVersion) { return false; }
    const suppliedBehavior: RemoteKeyboardBehavior | undefined = values.behavior ??
      (current.autoOpenOnRemoteClick === values.autoOpenOnRemoteClick ? current.behavior : undefined);
    const normalized: RemoteKeyboardPreferences = normalizeRemoteKeyboardPreferences(
      values.shortcutPlatform,
      values.simpleKeyboardEnabled,
      values.functionKeysVisible,
      values.closePanelAfterShortcut,
      values.autoOpenOnRemoteClick, suppliedBehavior
    );
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(
        activeContext, { name: REMOTE_KEYBOARD_PREFERENCES_NAME });
      const behavior: RemoteKeyboardBehavior = normalized.behavior ?? defaultRemoteKeyboardBehavior();
      const result = writeRemoteKeyboardPreferences(new RemoteKeyboardPreferencesPort(prefs), [
        { key: REMOTE_KEYBOARD_SHORTCUT_PLATFORM_KEY, value: normalized.shortcutPlatform },
        { key: REMOTE_KEYBOARD_SIMPLE_MODE_KEY, value: normalized.simpleKeyboardEnabled },
        { key: REMOTE_KEYBOARD_FUNCTION_KEYS_VISIBLE_KEY, value: normalized.functionKeysVisible },
        { key: REMOTE_KEYBOARD_CLOSE_AFTER_SHORTCUT_KEY, value: normalized.closePanelAfterShortcut },
        { key: REMOTE_KEYBOARD_AUTO_OPEN_ON_REMOTE_CLICK_KEY, value: normalized.autoOpenOnRemoteClick },
        { key: REMOTE_KEYBOARD_AUTO_OPEN_POLICY_KEY, value: behavior.autoOpenPolicy },
        { key: REMOTE_KEYBOARD_INPUT_INTENT_KEY, value: behavior.inputIntent },
        { key: REMOTE_KEYBOARD_AVOIDANCE_ENABLED_KEY, value: behavior.avoidanceEnabled },
        { key: REMOTE_KEYBOARD_PLACEMENT_KEY, value: behavior.placement },
        { key: REMOTE_KEYBOARD_GAP_KEY, value: behavior.gapVp },
        { key: REMOTE_KEYBOARD_BEHAVIOR_VERSION_KEY, value: 1 }
      ]);
      if (!result.ok) { this.preferencesWriteFault = !result.rollbackSucceeded; return false; }
      this.publish(normalized);
      this.lastPreferences = this.copyPreferences(normalized);
      this.applySimpleKeyboardMode(normalized.simpleKeyboardEnabled);
      return true;
    } catch (_error) {
      return false;
    }
  }

  saveShortcutPlatform(platform: RemoteShortcutPlatform,
    context?: common.Context): boolean {
    const current: RemoteKeyboardPreferences = this.loadPreferences(context);
    current.shortcutPlatform = normalizeRemoteShortcutPlatform(platform);
    return this.savePreferences(current, context);
  }

  loadCustomShortcuts(context?: common.Context): Array<RemoteCustomShortcut> {
    const activeContext: common.Context | null = context ?? this.appContext;
    if (activeContext === null) { return []; }
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(
        activeContext, { name: REMOTE_KEYBOARD_PREFERENCES_NAME });
      return decodeRemoteCustomShortcuts(
        prefs.getSync(REMOTE_CUSTOM_SHORTCUT_STORAGE_KEY, '') as string);
    } catch (_error) {
      return [];
    }
  }

  saveCustomShortcuts(shortcuts: Array<RemoteCustomShortcut>,
    context?: common.Context): boolean {
    const activeContext: common.Context | null = context ?? this.appContext;
    if (activeContext === null) { return false; }
    try {
      const prefs: preferences.Preferences = preferences.getPreferencesSync(
        activeContext, { name: REMOTE_KEYBOARD_PREFERENCES_NAME });
      prefs.putSync(REMOTE_CUSTOM_SHORTCUT_STORAGE_KEY,
        encodeRemoteCustomShortcuts(shortcuts));
      prefs.flushSync();
      return true;
    } catch (_error) {
      return false;
    }
  }

  private publish(values: RemoteKeyboardPreferences): void {
    const behavior: RemoteKeyboardBehavior = values.behavior ?? defaultRemoteKeyboardBehavior(values.autoOpenOnRemoteClick);
    AppStorage.setOrCreate<string>(REMOTE_KEYBOARD_SHORTCUT_PLATFORM_KEY,
      values.shortcutPlatform);
    AppStorage.setOrCreate<boolean>(REMOTE_KEYBOARD_SIMPLE_MODE_KEY,
      values.simpleKeyboardEnabled);
    AppStorage.setOrCreate<boolean>(REMOTE_KEYBOARD_FUNCTION_KEYS_VISIBLE_KEY,
      values.functionKeysVisible);
    AppStorage.setOrCreate<boolean>(REMOTE_KEYBOARD_CLOSE_AFTER_SHORTCUT_KEY,
      values.closePanelAfterShortcut);
    AppStorage.setOrCreate<boolean>(REMOTE_KEYBOARD_AUTO_OPEN_ON_REMOTE_CLICK_KEY,
      values.autoOpenOnRemoteClick);
    AppStorage.setOrCreate<string>(REMOTE_KEYBOARD_AUTO_OPEN_POLICY_KEY, behavior.autoOpenPolicy);
    AppStorage.setOrCreate<string>(REMOTE_KEYBOARD_INPUT_INTENT_KEY, behavior.inputIntent);
    AppStorage.setOrCreate<boolean>(REMOTE_KEYBOARD_AVOIDANCE_ENABLED_KEY, behavior.avoidanceEnabled);
    AppStorage.setOrCreate<string>(REMOTE_KEYBOARD_PLACEMENT_KEY, behavior.placement);
    AppStorage.setOrCreate<number>(REMOTE_KEYBOARD_GAP_KEY, behavior.gapVp);
  }

  private publishHarmonyShortcutBlocking(
    values: HarmonyShortcutBlockingPreferences
  ): void {
    AppStorage.setOrCreate<string>(HARMONY_SHORTCUT_BLOCKING_STORAGE_KEY,
      encodeHarmonyShortcutBlockingPreferences(values));
  }

  private applySimpleKeyboardMode(enabled: boolean): void {
    try {
      inputMethod.setSimpleKeyboardEnabled(enabled);
    } catch (_error) {
      // Some form factors do not expose a software keyboard. The preference
      // remains valid and is applied again when a supported window attaches.
    }
  }

  async readSystemInputMethods(): Promise<RemoteSystemInputMethodSnapshot> {
    try {
      const current: inputMethod.InputMethodProperty = inputMethod.getCurrentInputMethod();
      const currentSubtype: InputMethodSubtype = inputMethod.getCurrentInputMethodSubtype();
      const setting: inputMethod.InputMethodSetting = inputMethod.getSetting();
      const enabledMethods: Array<inputMethod.InputMethodProperty> =
        await setting.getInputMethods(true);
      const allMethods: Array<inputMethod.InputMethodProperty> =
        await setting.getAllInputMethods();
      const enabledKeys: Array<string> = enabledMethods.map(
        (method: inputMethod.InputMethodProperty): string => inputMethodKey(method));
      const currentKey: string = inputMethodKey(current);
      const methods: Array<RemoteSystemInputMethodInfo> = [];
      for (let index: number = 0; index < allMethods.length; index++) {
        const method: inputMethod.InputMethodProperty = allMethods[index];
        let subtypeSummary: string = '';
        try {
          const subtypes: Array<InputMethodSubtype> =
            await setting.listInputMethodSubtype(method);
          const labels: Array<string> = subtypes.map(
            (subtype: InputMethodSubtype): string => subtypeLabel(subtype));
          subtypeSummary = labels.join(' · ');
        } catch (_error) {
          subtypeSummary = '';
        }
        methods.push({
          bundleName: method.name,
          inputMethodId: method.id,
          label: inputMethodLabel(method),
          current: inputMethodKey(method) === currentKey,
          enabled: enabledKeys.indexOf(inputMethodKey(method)) >= 0,
          subtypeSummary
        });
      }
      return {
        available: true,
        currentLabel: inputMethodLabel(current),
        currentSubtype: subtypeLabel(currentSubtype),
        methods,
        error: ''
      };
    } catch (error) {
      return emptySystemSnapshot(JSON.stringify(error));
    }
  }

  openSystemInputMethodSettings(context: common.UIAbilityContext): boolean {
    try {
      settings.openInputMethodSettings(context);
      return true;
    } catch (_error) {
      return false;
    }
  }

  openSystemInputMethodDetail(context: common.UIAbilityContext,
    method: RemoteSystemInputMethodInfo): boolean {
    if (method.bundleName.trim().length === 0 ||
      method.inputMethodId.trim().length === 0) { return false; }
    try {
      settings.openInputMethodDetail(context, method.bundleName, method.inputMethodId);
      return true;
    } catch (_error) {
      return false;
    }
  }
}

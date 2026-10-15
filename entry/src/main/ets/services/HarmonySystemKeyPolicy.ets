/**
 * HarmonyOS system keys share numbers with the Android/DOM key tables some input paths
 * still report (16 is volume up here but Shift in DOM; 22 is mute here but the Android
 * Right arrow). A key event is a HarmonyOS system key only when its keyText is exactly
 * that key's own HarmonyOS name, so an Android-coded letter named "KEYCODE_A" is never
 * mistaken for one.
 */
const HARMONY_SYSTEM_KEY_NAMES: Map<number, string> = new Map<number, string>([
  [0, 'KEYCODE_FN'], [1, 'KEYCODE_HOME'], [2, 'KEYCODE_BACK'], [9, 'KEYCODE_SEARCH'],
  [10, 'KEYCODE_MEDIA_PLAY_PAUSE'], [11, 'KEYCODE_MEDIA_STOP'], [12, 'KEYCODE_MEDIA_NEXT'],
  [13, 'KEYCODE_MEDIA_PREVIOUS'], [14, 'KEYCODE_MEDIA_REWIND'], [15, 'KEYCODE_MEDIA_FAST_FORWARD'],
  [16, 'KEYCODE_VOLUME_UP'], [17, 'KEYCODE_VOLUME_DOWN'], [18, 'KEYCODE_POWER'], [19, 'KEYCODE_CAMERA'],
  [22, 'KEYCODE_VOLUME_MUTE'], [23, 'KEYCODE_MUTE'], [40, 'KEYCODE_BRIGHTNESS_UP'],
  [41, 'KEYCODE_BRIGHTNESS_DOWN']
]);

export function isHarmonySystemKeyEvent(keyCode: number, keyText: string | undefined | null): boolean {
  const name: string | undefined = HARMONY_SYSTEM_KEY_NAMES.get(keyCode);
  return name !== undefined && keyText !== undefined && keyText !== null && keyText.toUpperCase() === name;
}

/**
 * Search (9), media stop (11) and mute (22) are forwarded as those keys; Android/DOM tables
 * reuse the numbers (Tab, digits, D-pad Right), so forward them only when the event names
 * the HarmonyOS key. An unnamed event with one of these codes is dropped rather than misread.
 */
const AMBIGUOUS_SYSTEM_KEY_CODES: number[] = [9, 11, 22];

export function isAmbiguousSystemKeyCode(keyCode: number, keyText: string | undefined | null): boolean {
  return AMBIGUOUS_SYSTEM_KEY_CODES.indexOf(keyCode) >= 0 && !isHarmonySystemKeyEvent(keyCode, keyText);
}

/**
 * A key code as it may appear in the device log. Keys that type text (letters, digits,
 * symbols, Space, keypad digits, and every non-HarmonyOS compatibility code) log as "text",
 * so a password typed on a remote lock screen or in a terminal cannot be read back from
 * hilog. Modifiers, navigation, editing and function keys keep their code for diagnostics.
 */
export function keyCodeForLog(keyCode: number): string {
  const safe: boolean = (keyCode >= 2012 && keyCode <= 2015) || (keyCode >= 2045 && keyCode <= 2049) ||
    keyCode === 2054 || keyCode === 2055 || (keyCode >= 2067 && keyCode <= 2083) ||
    (keyCode >= 2090 && keyCode <= 2102) || keyCode === 2119 || (keyCode >= 2816 && keyCode <= 2827) ||
    (keyCode >= 2600 && keyCode !== 2602 && keyCode !== 2603 && keyCode !== 2615 && keyCode < 2816);
  return safe ? keyCode.toString() : 'text';
}

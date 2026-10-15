/**
 * RemotePhysicalKeyboardPolicy.test.ets - 本地键盘类型 × 远端系统的 Ctrl/Command 映射。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  HARMONY_KEYCODE_CTRL_LEFT,
  HARMONY_KEYCODE_CTRL_RIGHT,
  HARMONY_KEYCODE_META_LEFT,
  HARMONY_KEYCODE_META_RIGHT,
  LocalKeyboardKind,
  RemoteKeyboardLayout,
  RemoteModifierChordState,
  detectLocalKeyboardKind,
  mapPhysicalKeyForRemote,
  normalizeLocalKeyboardPreference,
  remoteKeyboardLayoutForPeerPlatform,
  remoteModifierChordState,
  resolveLocalKeyboardKind,
  shouldSwapCtrlMeta
} from '../main/ets/services/RemotePhysicalKeyboardPolicy';
import { isAmbiguousSystemKeyCode, isHarmonySystemKeyEvent, keyCodeForLog } from '../main/ets/services/HarmonySystemKeyPolicy';
import { harmonySystemKeyForVnc } from '../main/ets/services/VncPhysicalKeyboardPolicy';

export default function remotePhysicalKeyboardPolicyTest(): void {
  describe('RemotePhysicalKeyboardPolicy', (): void => {
    it('swaps_ctrl_and_meta_only_when_local_and_remote_disagree', 0, (): void => {
      expect(shouldSwapCtrlMeta(RemoteKeyboardLayout.WINDOWS, LocalKeyboardKind.PC)).assertFalse();
      expect(shouldSwapCtrlMeta(RemoteKeyboardLayout.MACOS, LocalKeyboardKind.MAC)).assertFalse();
      expect(shouldSwapCtrlMeta(RemoteKeyboardLayout.MACOS, LocalKeyboardKind.PC)).assertTrue();
      expect(shouldSwapCtrlMeta(RemoteKeyboardLayout.WINDOWS, LocalKeyboardKind.MAC)).assertTrue();
    });

    it('maps_every_ctrl_and_meta_key_through_the_swap', 0, (): void => {
      const pcToMac: number[] = [HARMONY_KEYCODE_CTRL_LEFT, HARMONY_KEYCODE_CTRL_RIGHT,
        HARMONY_KEYCODE_META_LEFT, HARMONY_KEYCODE_META_RIGHT].map((code: number): number =>
        mapPhysicalKeyForRemote(RemoteKeyboardLayout.MACOS, LocalKeyboardKind.PC, code));
      expect(pcToMac.join(',')).assertEqual([HARMONY_KEYCODE_META_LEFT, HARMONY_KEYCODE_META_RIGHT,
        HARMONY_KEYCODE_CTRL_LEFT, HARMONY_KEYCODE_CTRL_RIGHT].join(','));
      expect(mapPhysicalKeyForRemote(RemoteKeyboardLayout.WINDOWS, LocalKeyboardKind.MAC,
        HARMONY_KEYCODE_META_LEFT)).assertEqual(HARMONY_KEYCODE_CTRL_LEFT);
      expect(mapPhysicalKeyForRemote(RemoteKeyboardLayout.WINDOWS, LocalKeyboardKind.MAC,
        HARMONY_KEYCODE_CTRL_RIGHT)).assertEqual(HARMONY_KEYCODE_META_RIGHT);
      expect(mapPhysicalKeyForRemote(RemoteKeyboardLayout.MACOS, LocalKeyboardKind.MAC,
        HARMONY_KEYCODE_META_LEFT)).assertEqual(HARMONY_KEYCODE_META_LEFT);
      expect(mapPhysicalKeyForRemote(RemoteKeyboardLayout.WINDOWS, LocalKeyboardKind.PC,
        HARMONY_KEYCODE_CTRL_LEFT)).assertEqual(HARMONY_KEYCODE_CTRL_LEFT);
    });

    it('never_changes_non_modifier_keys', 0, (): void => {
      const keys: number[] = [2017, 2045, 2046, 2047, 2074, 2054, 2090, 2816];
      keys.forEach((code: number): void => {
        expect(mapPhysicalKeyForRemote(RemoteKeyboardLayout.MACOS, LocalKeyboardKind.PC, code)).assertEqual(code);
        expect(mapPhysicalKeyForRemote(RemoteKeyboardLayout.WINDOWS, LocalKeyboardKind.MAC, code)).assertEqual(code);
      });
    });

    it('detects_apple_keyboards_by_vendor_or_name', 0, (): void => {
      expect(detectLocalKeyboardKind(0x05AC, 'USB Keyboard')).assertEqual(LocalKeyboardKind.MAC);
      expect(detectLocalKeyboardKind(0x004C, 'Keyboard')).assertEqual(LocalKeyboardKind.MAC);
      expect(detectLocalKeyboardKind(0, 'Magic Keyboard with Touch ID')).assertEqual(LocalKeyboardKind.MAC);
      expect(detectLocalKeyboardKind(0, 'Apple Wireless Keyboard')).assertEqual(LocalKeyboardKind.MAC);
      expect(detectLocalKeyboardKind(0x046D, 'Logitech K380')).assertEqual(LocalKeyboardKind.PC);
      expect(detectLocalKeyboardKind(0, '')).assertEqual(LocalKeyboardKind.PC);
    });

    it('lets_the_user_preference_override_detection', 0, (): void => {
      expect(normalizeLocalKeyboardPreference('mac')).assertEqual('mac');
      expect(normalizeLocalKeyboardPreference('pc')).assertEqual('pc');
      expect(normalizeLocalKeyboardPreference('other')).assertEqual('auto');
      expect(normalizeLocalKeyboardPreference(undefined)).assertEqual('auto');
      expect(resolveLocalKeyboardKind('auto', LocalKeyboardKind.MAC)).assertEqual(LocalKeyboardKind.MAC);
      expect(resolveLocalKeyboardKind('pc', LocalKeyboardKind.MAC)).assertEqual(LocalKeyboardKind.PC);
      expect(resolveLocalKeyboardKind('mac', LocalKeyboardKind.PC)).assertEqual(LocalKeyboardKind.MAC);
    });

    it('reads_the_remote_system_from_the_rustdesk_peer_platform', 0, (): void => {
      expect(remoteKeyboardLayoutForPeerPlatform('Mac OS')).assertEqual(RemoteKeyboardLayout.MACOS);
      expect(remoteKeyboardLayoutForPeerPlatform('macOS')).assertEqual(RemoteKeyboardLayout.MACOS);
      expect(remoteKeyboardLayoutForPeerPlatform('Windows')).assertEqual(RemoteKeyboardLayout.WINDOWS);
      expect(remoteKeyboardLayoutForPeerPlatform('Linux')).assertEqual(RemoteKeyboardLayout.WINDOWS);
      expect(remoteKeyboardLayoutForPeerPlatform('Android') === null).assertTrue();
      expect(remoteKeyboardLayoutForPeerPlatform('') === null).assertTrue();
    });

    it('reports_remote_chord_modifiers_after_the_swap', 0, (): void => {
      const swapped: RemoteModifierChordState = remoteModifierChordState(true, true, false);
      expect(swapped.ctrl).assertFalse();
      expect(swapped.meta).assertTrue();
      const direct: RemoteModifierChordState = remoteModifierChordState(false, true, false);
      expect(direct.ctrl).assertTrue();
      expect(direct.meta).assertFalse();
    });
  });

  describe('HarmonySystemKeyPolicy', (): void => {
    it('requires_the_exact_harmony_key_name', 0, (): void => {
      expect(isHarmonySystemKeyEvent(16, 'KEYCODE_VOLUME_UP')).assertTrue();
      expect(isHarmonySystemKeyEvent(22, 'KEYCODE_VOLUME_MUTE')).assertTrue();
      expect(isHarmonySystemKeyEvent(10, 'keycode_media_play_pause')).assertTrue();
      // DOM Shift (16) and Android Right arrow (22) share the numbers but not the name.
      expect(isHarmonySystemKeyEvent(16, 'Shift')).assertFalse();
      expect(isHarmonySystemKeyEvent(22, 'KEYCODE_DPAD_RIGHT')).assertFalse();
      expect(isHarmonySystemKeyEvent(16, undefined)).assertFalse();
      expect(isHarmonySystemKeyEvent(2017, 'KEYCODE_A')).assertFalse();
    });

    it('never_logs_keys_that_type_text', 0, (): void => {
      const textKeys: number[] = [2000, 2009, 2017, 2042, 2050, 2061, 2065, 2066, 2103, 2116, 2602, 2615, 48, 65, 7];
      textKeys.forEach((code: number): void => { expect(keyCodeForLog(code)).assertEqual('text'); });
      const controlKeys: number[] = [2012, 2045, 2049, 2054, 2055, 2072, 2074, 2077, 2090, 2101, 2102, 2119, 2816];
      controlKeys.forEach((code: number): void => { expect(keyCodeForLog(code)).assertEqual(code.toString()); });
    });

    it('drops_unnamed_search_stop_and_mute_codes', 0, (): void => {
      expect(isAmbiguousSystemKeyCode(9, 'Tab')).assertTrue();
      expect(isAmbiguousSystemKeyCode(22, 'KEYCODE_DPAD_RIGHT')).assertTrue();
      expect(isAmbiguousSystemKeyCode(22, 'KEYCODE_VOLUME_MUTE')).assertFalse();
      expect(isAmbiguousSystemKeyCode(11, 'KEYCODE_MEDIA_STOP')).assertFalse();
      expect(isAmbiguousSystemKeyCode(16, 'Shift')).assertFalse();
      expect(isAmbiguousSystemKeyCode(2017, undefined)).assertFalse();
    });

    it('keeps_vnc_keysym_media_keys_and_drops_the_rest', 0, (): void => {
      expect(harmonySystemKeyForVnc(16, 'KEYCODE_VOLUME_UP')).assertEqual(16);
      expect(harmonySystemKeyForVnc(22, 'KEYCODE_VOLUME_MUTE')).assertEqual(22);
      expect(harmonySystemKeyForVnc(18, 'KEYCODE_POWER')).assertEqual(-1);
      expect(harmonySystemKeyForVnc(16, 'Shift') === null).assertTrue();
    });
  });
}

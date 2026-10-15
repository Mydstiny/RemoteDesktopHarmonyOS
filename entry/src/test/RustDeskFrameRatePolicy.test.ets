import { describe, it, expect } from '@ohos/hypium';
import {
  normalizeRustDeskFps,
  RUSTDESK_BEST_QUALITY_FPS,
  RUSTDESK_FPS_CHOICES,
  rustDeskFpsChoiceLabel,
  rustDeskFpsLockedByQuality,
  rustDeskFpsSummary
} from '../main/ets/services/RustDeskFrameRatePolicy';
import { deviceLocalUserSettingNames } from '../main/ets/services/CloudSyncSettingsPolicy';

export default function rustDeskFrameRatePolicyTest() {
  describe('RustDeskFrameRatePolicy', (): void => {
    it('normalizes_unknown_frame_rates_to_the_tier_default', 0, (): void => {
      expect(normalizeRustDeskFps(30)).assertEqual(30);
      expect(normalizeRustDeskFps(60)).assertEqual(60);
      expect(normalizeRustDeskFps(0)).assertEqual(0);
      expect(normalizeRustDeskFps(45)).assertEqual(0);
      expect(normalizeRustDeskFps(-1)).assertEqual(0);
      expect(RUSTDESK_FPS_CHOICES.length).assertEqual(3);
    });

    it('quality_first_owns_a_fixed_30_fps_cap', 0, (): void => {
      expect(RUSTDESK_BEST_QUALITY_FPS).assertEqual(30);
      expect(rustDeskFpsLockedByQuality(2)).assertTrue();
      expect(rustDeskFpsLockedByQuality(1)).assertFalse();
      expect(rustDeskFpsLockedByQuality(0)).assertFalse();
      expect(rustDeskFpsSummary(2, 60)).assertEqual('画质优先固定 30 帧');
    });

    it('other_tiers_follow_the_user_choice', 0, (): void => {
      expect(rustDeskFpsSummary(1, 60)).assertEqual('60 帧');
      expect(rustDeskFpsSummary(0, 30)).assertEqual('30 帧');
      expect(rustDeskFpsSummary(0, 0)).assertEqual('自动 · 30 帧');
      expect(rustDeskFpsSummary(1, 0)).assertEqual('自动 · 随画质档');
      expect(rustDeskFpsChoiceLabel(0)).assertEqual('自动');
      expect(rustDeskFpsChoiceLabel(60)).assertEqual('60 帧');
    });

    it('frame_rate_preference_stays_device_local', 0, (): void => {
      expect(deviceLocalUserSettingNames().indexOf('rustdeskFps') >= 0).assertTrue();
    });
  });
}

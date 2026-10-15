import { describe, expect, it } from '@ohos/hypium';
import {
  normalizeRemoteWindowSizingMode,
  planRemoteWindowSizing,
  RemoteWindowSizingInput,
  RemoteWindowSizingMode,
  RemoteWindowSizingPlan,
  remoteWindowSizingLabel
} from '../main/ets/services/RemoteWindowSizingPolicy';
import { defaultRemoteDisplayProfile, RemoteDisplayProfile } from '../main/ets/services/RemoteDisplayProfilePolicy';
import {
  deserializeRemoteDisplayProfileEnvelope,
  serializeRemoteDisplayProfileEnvelope
} from '../main/ets/services/RemoteDisplayProfileStore';

/** A 2560x1600 screen (density 2) with a 1360x1040 window whose picture area is 1360x960. */
function input(mode: RemoteWindowSizingMode, remoteWidth: number, remoteHeight: number): RemoteWindowSizingInput {
  return { mode, remoteWidth, remoteHeight, densityPixels: 2,
    windowLeft: 80, windowTop: 64, windowWidth: 1360, windowHeight: 1040,
    canvasWidth: 1360, canvasHeight: 960,
    areaLeft: 0, areaTop: 0, areaWidth: 2560, areaHeight: 1520,
    minWindowWidth: 720, minWindowHeight: 960 };
}

export default function remoteWindowSizingPolicyTest(): void {
  describe('RemoteWindowSizingPolicy', (): void => {
    it('default_mode_never_resizes', 0, (): void => {
      const plan: RemoteWindowSizingPlan = planRemoteWindowSizing(input('default', 1280, 720));
      expect(plan.apply).assertFalse();
      expect(normalizeRemoteWindowSizingMode('unknown')).assertEqual('default');
      expect(remoteWindowSizingLabel('fitPixels')).assertEqual('适配远端（1:1 像素）');
    });

    it('pixel_fit_maps_one_remote_pixel_to_one_screen_pixel_plus_chrome', 0, (): void => {
      const plan: RemoteWindowSizingPlan = planRemoteWindowSizing(input('fitPixels', 1280, 1024));
      expect(plan.apply).assertTrue();
      expect(plan.width).assertEqual(1280);
      expect(plan.height).assertEqual(1024 + 80);
      expect(plan.left).assertEqual(80);
      expect(plan.scaledDown).assertFalse();
    });

    it('scaled_fit_uses_the_system_density_and_shrinks_to_the_screen', 0, (): void => {
      // 1366x768 at density 2 wants 2732x1536 + 80 px chrome: larger than the usable area.
      const plan: RemoteWindowSizingPlan = planRemoteWindowSizing(input('fitScaled', 1366, 768));
      expect(plan.scaledDown).assertTrue();
      expect(plan.width <= 2560).assertTrue();
      expect(plan.height <= 1520).assertTrue();
      expect(Math.abs((plan.width) / (plan.height - 80) - 1366 / 768) < 0.01).assertTrue();
      expect(plan.left + plan.width <= 2560).assertTrue();
    });

    it('small_remote_is_kept_at_the_minimum_window', 0, (): void => {
      const plan: RemoteWindowSizingPlan = planRemoteWindowSizing(input('fitPixels', 640, 480));
      expect(plan.clampedToMinimum).assertTrue();
      expect(plan.width).assertEqual(720);
      expect(plan.height).assertEqual(960);
    });

    it('an_already_fitted_window_is_left_alone', 0, (): void => {
      const fitted: RemoteWindowSizingInput = input('fitPixels', 1360, 960);
      expect(planRemoteWindowSizing(fitted).apply).assertFalse();
    });

    it('profiles_saved_before_window_sizing_still_load_as_default', 0, (): void => {
      const profile: RemoteDisplayProfile = defaultRemoteDisplayProfile('host', 'rdp', 'default', 1);
      profile.windowSizing = 'fitScaled';
      const encoded: string | null = serializeRemoteDisplayProfileEnvelope(profile);
      expect(encoded !== null).assertTrue();
      const back: RemoteDisplayProfile | null = deserializeRemoteDisplayProfileEnvelope(encoded as string);
      expect(back !== null && back.windowSizing === 'fitScaled').assertTrue();
      const legacy: string = (encoded as string).replace(',"windowSizing":"fitScaled"', '');
      const old: RemoteDisplayProfile | null = deserializeRemoteDisplayProfileEnvelope(legacy);
      expect(old !== null && old.windowSizing === 'default').assertTrue();
    });
  });
}

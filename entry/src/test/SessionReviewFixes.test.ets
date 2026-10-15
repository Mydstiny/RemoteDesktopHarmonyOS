import { describe, expect, it } from '@ohos/hypium';
import { harmonyNativeKeyCaptureConfigured } from '../main/ets/services/HarmonyShortcutBlockingPolicy';
import { RemoteSessionInputOwner } from '../main/ets/services/RemoteSessionInputOwner';
import {
  REMOTE_INPUT_DIAGNOSTIC_EVENTS,
  RemoteInputDiagnosticEvent,
  remoteInputBoundedCount,
  remoteInputReasonCode,
  remoteInputReasonName
} from '../main/ets/services/RemoteInputDiagnosticEvents';
import { diagnosticEventIsAllowed, DIAGNOSTIC_EVENT_CATALOG_VERSION } from '../main/ets/services/DiagnosticCapturePolicy';
import { settleWithin } from '../main/ets/services/RemoteSessionWindowCoordinator';

export default function sessionReviewFixesTest(): void {
  describe('SessionReviewFixes', (): void => {
    it('full_key_capture_needs_its_own_opt_in', 0, (): void => {
      expect(harmonyNativeKeyCaptureConfigured(false, true)).assertFalse();
      expect(harmonyNativeKeyCaptureConfigured(true, false)).assertFalse();
      expect(harmonyNativeKeyCaptureConfigured(true, true)).assertTrue();
    });

    it('overlapping_instances_keep_input_blocked_until_both_disappear', 0, (): void => {
      const owner: RemoteSessionInputOwner = new RemoteSessionInputOwner();
      owner.appeared('sheet'); // instance A
      owner.appeared('sheet'); // instance B opened while A still animates out
      owner.disappeared('sheet'); // A finishes
      expect(owner.overlaysActive()).assertTrue();
      owner.disappeared('sheet'); // B closes
      expect(owner.overlaysActive()).assertFalse();
      owner.visible('menu', true);
      owner.visible('menu', true);
      owner.visible('menu', false); // state-driven overlays never stack
      expect(owner.blocked()).assertFalse();
    });

    it('overlay_query_does_not_move_the_epoch', 0, (): void => {
      const owner: RemoteSessionInputOwner = new RemoteSessionInputOwner();
      const epoch: number = owner.epoch();
      expect(owner.overlaysActive()).assertFalse();
      expect(owner.epoch()).assertEqual(epoch);
    });

    it('remote_input_events_are_cataloged_with_stable_reason_codes', 0, (): void => {
      expect(DIAGNOSTIC_EVENT_CATALOG_VERSION).assertEqual(6);
      REMOTE_INPUT_DIAGNOSTIC_EVENTS.forEach((event: RemoteInputDiagnosticEvent): void => {
        expect(diagnosticEventIsAllowed('core.app', event)).assertTrue();
      });
      expect(remoteInputReasonCode('geometry-unknown')).assertEqual(2);
      expect(remoteInputReasonCode('floating-right')).assertEqual(12);
      expect(remoteInputReasonCode('typed secret text')).assertEqual(0);
      expect(remoteInputReasonName(19)).assertEqual('presented');
      expect(remoteInputBoundedCount(-12.6)).assertEqual(13);
      expect(remoteInputBoundedCount(Number.NaN)).assertEqual(0);
    });

    it('page_close_wait_is_bounded', 0, async (): Promise<void> => {
      const never: Promise<void> = new Promise<void>((): void => {});
      expect(await settleWithin(never, 10)).assertFalse();
      expect(await settleWithin(Promise.resolve(), 1000)).assertTrue();
    });
  });
}

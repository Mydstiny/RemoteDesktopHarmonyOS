/**
 * RemoteScrollPolicy.test.ets - 远程滚动的线性换算与各协议粒度。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  accumulateRemoteScroll,
  axisEventCarriesWheelDetent,
  isTouchScrollDiscontinuity,
  MAC_TRACKPAD_UNITS_PER_PIXEL,
  mouseWheelUnits,
  REMOTE_SCROLL_GESTURE_IDLE_MS,
  REMOTE_SCROLL_MAX_UNITS_PER_SAMPLE,
  RemoteScrollState,
  RemoteScrollStep,
  remoteScrollWire,
  resetRemoteScrollState,
  touchpadWheelUnits,
  TOUCHPAD_WHEEL_UNITS_PER_VP,
  VNC_WHEEL_UNITS_PER_CLICK,
  WHEEL_UNITS_PER_NOTCH
} from '../main/ets/services/RemoteScrollPolicy';

function sendAll(samples: number[], wire: 'units' | 'pixels' | 'clicks' | 'notches', gesture: boolean,
  intervalMs: number = 8): number {
  let state: RemoteScrollState = resetRemoteScrollState();
  let sent: number = 0;
  for (let i = 0; i < samples.length; i++) {
    const step: RemoteScrollStep = accumulateRemoteScroll(samples[i], wire, state, 1000 + i * intervalMs, gesture);
    state = step.state;
    sent += step.amount;
  }
  return sent;
}

export default function remoteScrollPolicyTest(): void {
  describe('RemoteScrollPolicy', (): void => {
    it('picks_the_wire_by_protocol_and_peer', 0, (): void => {
      expect(remoteScrollWire('rdp', 0, false)).assertEqual('units');
      expect(remoteScrollWire('vnc', 0, true)).assertEqual('clicks');
      expect(remoteScrollWire('rustdesk', 1, false)).assertEqual('units');
      expect(remoteScrollWire('rustdesk', 2, true)).assertEqual('pixels');
      expect(remoteScrollWire('rustdesk', 2, false)).assertEqual('notches');
      expect(remoteScrollWire('rustdesk', 0, true)).assertEqual('notches');
    });

    it('scales_the_mouse_notch_by_the_speed_not_by_whole_notches', 0, (): void => {
      expect(mouseWheelUnits(15, 100)).assertEqual(WHEEL_UNITS_PER_NOTCH);
      expect(mouseWheelUnits(-1, 100)).assertEqual(-WHEEL_UNITS_PER_NOTCH);
      expect(mouseWheelUnits(45, 150)).assertEqual(180);
      expect(mouseWheelUnits(0, 100)).assertEqual(0);
      // 150% on a notch wire: 4 notches become exactly 6.
      expect(sendAll([180, 180, 180, 180], 'notches', false)).assertEqual(6);
      // 150% on RDP units: every notch is 180 units, no alternating 1/2-notch bursts.
      expect(sendAll([180, 180, 180, 180], 'units', false)).assertEqual(720);
    });

    it('is_linear_in_touch_distance_whatever_the_sampling', 0, (): void => {
      const unitsPerVp: number = touchpadWheelUnits(1, 1, 100);
      expect(unitsPerVp).assertEqual(TOUCHPAD_WHEEL_UNITS_PER_VP);
      const fine: number[] = [];
      for (let i = 0; i < 300; i++) { fine.push(touchpadWheelUnits(0.5, 1, 100)); }
      const coarse: number[] = [];
      for (let i = 0; i < 15; i++) { coarse.push(touchpadWheelUnits(10, 1, 100)); }
      // 150 vp of travel either way: the same scroll, with no per-flush cap dropping the fast swipe.
      expect(sendAll(fine, 'units', true)).assertEqual(sendAll(coarse, 'units', true));
      expect(sendAll(fine, 'notches', true)).assertEqual(sendAll(coarse, 'notches', true));
      expect(sendAll(coarse, 'units', true)).assertEqual(150 * TOUCHPAD_WHEEL_UNITS_PER_VP);
    });

    it('keeps_slow_motion_as_a_carried_fraction', 0, (): void => {
      const slow: number[] = [];
      for (let i = 0; i < 30; i++) { slow.push(touchpadWheelUnits(0.5, 1, 100)); }
      // 15 vp = 120 units = one notch, reached without losing the sub-notch samples.
      expect(sendAll(slow, 'notches', true)).assertEqual(1);
      expect(sendAll(slow, 'clicks', true)).assertEqual(120 / VNC_WHEEL_UNITS_PER_CLICK);
      expect(sendAll(slow, 'pixels', true)).assertEqual(120 / MAC_TRACKPAD_UNITS_PER_PIXEL);
    });

    it('drops_the_fraction_on_reversal_and_after_an_idle_gap', 0, (): void => {
      const first: RemoteScrollStep = accumulateRemoteScroll(100, 'notches', resetRemoteScrollState(), 1000, true);
      expect(first.amount).assertEqual(0);
      const reversed: RemoteScrollStep = accumulateRemoteScroll(-30, 'notches', first.state, 1010, true);
      expect(reversed.state.pending).assertEqual(-30);
      const later: RemoteScrollStep = accumulateRemoteScroll(30, 'notches', first.state,
        1000 + REMOTE_SCROLL_GESTURE_IDLE_MS + 1, true);
      expect(later.state.pending).assertEqual(30);
      // A mouse wheel keeps its fraction across pauses (150% stays 150% when scrolled slowly).
      const mouse: RemoteScrollStep = accumulateRemoteScroll(60, 'notches', first.state,
        1000 + REMOTE_SCROLL_GESTURE_IDLE_MS + 1, false);
      expect(mouse.amount).assertEqual(1);
    });

    it('bounds_one_huge_sample', 0, (): void => {
      const step: RemoteScrollStep = accumulateRemoteScroll(1000000, 'units', resetRemoteScrollState(), 1, true);
      expect(step.amount).assertEqual(REMOTE_SCROLL_MAX_UNITS_PER_SAMPLE);
    });

    it('ignores_wheel_gesture_end_and_finger_jumps', 0, (): void => {
      expect(axisEventCarriesWheelDetent(0)).assertTrue();
      expect(axisEventCarriesWheelDetent(1)).assertTrue();
      expect(axisEventCarriesWheelDetent(2)).assertTrue();
      expect(axisEventCarriesWheelDetent(3)).assertFalse();
      expect(axisEventCarriesWheelDetent(4)).assertFalse();
      expect(isTouchScrollDiscontinuity(4)).assertFalse();
      expect(isTouchScrollDiscontinuity(-200)).assertTrue();
      expect(isTouchScrollDiscontinuity(NaN)).assertTrue();
    });
  });
}

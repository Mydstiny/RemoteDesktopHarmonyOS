import { describe, expect, it } from '@ohos/hypium';
import { RemoteSessionInputOwner } from '../main/ets/services/RemoteSessionInputOwner';
import { SessionTrafficSampler, SessionTrafficSnapshot, trafficDelta } from '../main/ets/services/SessionTrafficSampler';

export default function sessionOwnershipTrafficTest(): void {
  describe('SessionOwnershipTraffic', (): void => {
    it('nested_editor_and_late_callback_are_fenced', 0, (): void => {
      const owner: RemoteSessionInputOwner = new RemoteSessionInputOwner();
      const stale: () => boolean = owner.guardedAction((): boolean => true);
      const menu: number = owner.acquire('menu');
      const editor: number = owner.acquire('editor', 'editor');
      owner.release(menu);
      let allowed: boolean = true;
      owner.runAction((): void => { allowed = owner.allowsInput(); });
      expect(allowed).assertFalse();
      owner.release(editor);
      expect(owner.allowsInput()).assertTrue();
      expect(stale()).assertFalse();
    });
    it('local_release_cannot_leak_into_remote_after_close', 0, (): void => {
      const owner: RemoteSessionInputOwner = new RemoteSessionInputOwner();
      expect(owner.allowsPhysical(2017, true)).assertTrue();
      const token: number = owner.acquire('menu');
      owner.release(token);
      expect(owner.allowsPhysical(2017, false)).assertFalse();
      expect(owner.allowsPhysical(2017, true)).assertTrue();
      expect(owner.allowsPhysical(2017, false)).assertTrue();
    });
    it('large_uint64_delta_remains_exact', 0, (): void => {
      expect(trafficDelta(0x200000, 8, 0x200000, 7)).assertEqual(1);
      expect(trafficDelta(8, 2, 7, 0xfffffffe)).assertEqual(4);
      expect(trafficDelta(7, 0, 8, 0)).assertEqual(-1);
    });
    it('new_generation_is_unknown_and_measured_idle_is_zero', 0, (): void => {
      const sampler: SessionTrafficSampler = new SessionTrafficSampler();
      const first: SessionTrafficSnapshot = { available: true, sessionId: 1, generation: 'a', scope: 'tcp',
        sampleMs: 1000, rxHigh: 0, rxLow: 100, txHigh: 0, txLow: 200 };
      expect(sampler.sample(first).rateAvailable).assertFalse();
      const second: SessionTrafficSnapshot = { available: true, sessionId: 1, generation: 'a', scope: 'tcp',
        sampleMs: 2000, rxHigh: 0, rxLow: 100, txHigh: 0, txLow: 200 };
      const idle = sampler.sample(second);
      expect(idle.rateAvailable).assertTrue(); expect(idle.receivedPerSecond).assertEqual(0);
      const reconnect: SessionTrafficSnapshot = { available: true, sessionId: 1, generation: 'b', scope: 'tcp',
        sampleMs: 3000, rxHigh: 0, rxLow: 0, txHigh: 0, txLow: 0 };
      expect(sampler.sample(reconnect).rateAvailable).assertFalse();
    });
  });
}
